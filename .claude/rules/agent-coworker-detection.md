# Agent Coworker Detection

How an agent detects that another agent is already working in the same repository clone, and how it avoids destroying that coworker's in-flight changes.

## The Problem

When two agents run concurrently in the **same checkout** (rather than separate worktrees), they observe each other's uncommitted changes through `git status`. A naive agent sees files it did not touch, assumes the tree is dirty, and runs `git stash`, `git restore`, or `git checkout -- .` to "clean up". The coworker then finds its work has disappeared and may attempt its own recovery, compounding the loss.

The root cause is missing coordination: each agent assumes it is the sole writer in the working tree.

## Detection Signals

No single signal is reliable. Combine these five and treat any positive as "assume a coworker is present".

| Signal | Detects | Cost | Platform |
|--------|---------|------|----------|
| **Baseline drift** — snapshot `git status --porcelain` + `git stash list` at session start; diff at risky moments | Files that appeared after we started, regardless of who created them | Free | All |
| **Session marker** — write `.git/.claude-session-<pid>` on start, delete on exit; scan siblings | Other agents that adopt the same convention | Free | All |
| **Process scan** — find other `claude`/`node` processes whose `cwd` is the same repo | Ad-hoc agents that do not write markers | ~100ms | Linux/macOS differ |
| **Taskwarrior `+ACTIVE` claims** — query `task project:<repo-basename> +ACTIVE export` for claims by other agent IDs | Coworkers that picked up coordination work via `/taskwarrior:task-claim`, even from a different process tree or host | ~50ms | Any host with `task` + `jq` |
| **Worktree leak** — every untracked file in the parent is probed against the working tree and HEAD of each linked `git worktree` | Transient leaks where a child `Agent(isolation: "worktree")` writes a file that briefly appears in the parent checkout at the same relative path (issue #1319) | ~10ms per worktree | All |

### Baseline drift

At the start of each session / skill invocation, capture a baseline:

```bash
git status --porcelain=v2 --branch > .git/.claude-baseline-$$
git stash list > .git/.claude-stash-baseline-$$
```

Before any destructive operation (`stash`, `restore`, `checkout -- .`, `reset --hard`), compare current state against the baseline. Entries present now but not in the baseline are **coworker changes**, not session changes — never stash or discard them.

### Session marker file

Marker path: `.git/.claude-session-<pid>` (kept inside `.git/` so it is never staged and is wiped by `git clean -x`).

```bash
marker=".git/.claude-session-$$"
printf '%s\t%s\t%s\n' "$$" "$(date -Iseconds)" "$(hostname)" > "$marker"
trap 'rm -f "$marker"' EXIT
```

Siblings: `ls .git/.claude-session-*` matching PIDs other than `$$`. For each, `kill -0 <pid> 2>/dev/null` confirms the process is still alive; stale markers from crashed sessions are safe to ignore.

### Process scan

Linux (cross-reference `/proc/*/cwd` symlinks against the repo root):

```bash
repo_root="$(git rev-parse --show-toplevel)"
for pid_dir in /proc/[0-9]*; do
  pid="${pid_dir##*/}"
  [ "$pid" = "$$" ] && continue
  cwd="$(readlink "$pid_dir/cwd" 2>/dev/null)" || continue
  case "$cwd" in "$repo_root"|"$repo_root"/*) echo "$pid" ;; esac
done
```

macOS uses `lsof -a -d cwd -c claude -c node -Fpn` since `/proc` is not available. The process-scan signal is a fallback — do not depend on it working in sandboxed environments (Claude Code on the web, restricted sandboxes) where process enumeration may be blocked.

### Taskwarrior `+ACTIVE` claims

When agents coordinate via `taskwarrior-plugin`, every claimed task is `task start`-ed (which sets the `+ACTIVE` virtual tag) and stamped with identity UDAs by `/taskwarrior:task-claim`:

| UDA | Source on claim |
|-----|-----------------|
| `agent` | `claude-${CLAUDE_SESSION_ID:0:8}` |
| `pid` | `$$` at claim time |
| `host` | `hostname` |
| `branch` | `git branch --show-current` |
| `worktree` | `git rev-parse --show-toplevel` |

Probe for active claims by other agents without contacting their processes:

```bash
project="$(basename "$(git rev-parse --show-toplevel)")"
task project:"$project" +ACTIVE export \
  | jq '.[] | {id, agent, pid, host, branch, worktree, start}'
```

The query is parallel-safe (`export` returns `[]` and exits 0 on no matches; see `.claude/rules/parallel-safe-queries.md`). Each row's `agent` is compared against `claude-${CLAUDE_SESSION_ID:0:8}` — matches are own claims and are reported as `OWN_CLAIM_*`; anything else counts toward `TW_CLAIM_COUNT` and raises the `coworker_detected` verdict.

This signal is the only one that survives:

- **Different hosts.** Taskwarrior stores can be synced via TaskChampion, so a claim on host A is visible to host B.
- **Crashed Claude processes.** The claim outlives the process; staleness is reported separately by filtering on `start.before:now-Nh` (default 4h) without auto-stopping.
- **Worktrees in the same project.** Taskwarrior records the project basename — not the worktree path — so two agents in sibling worktrees of the same repo still see each other's claims.

The cross-link cuts both ways: when one agent claims via `/taskwarrior:task-claim`, the next agent's `/git:coworker-check` sees the claim before its destructive op even if that agent never invoked taskwarrior itself. The four-signal verdict is only as strong as the weakest signal that fires, so opting in to taskwarrior coordination strengthens the guard for every clone of the project.

### Worktree leak (issue #1319)

`Agent(isolation: "worktree")` is supposed to give the child a sealed filesystem view: writes inside the worktree should not be visible in the parent checkout. In practice we have observed a transient leak where the child's brand-new file briefly appears in the **parent** at the same relative path as an **untracked file**, before vanishing when the child commits. From the issue:

> The worktree's filesystem did **not** contain `check-runtime.sh`. The parent checkout's filesystem **did** contain `check-runtime.sh` as an untracked file. A few minutes later the agent committed and pushed; the file is correctly present in the agent's pushed branch. At that point, the orphan in the parent checkout had vanished.

A naive parent session that saw the orphan would `git stash` or `git add -A; git commit` the file onto the wrong branch. The fifth signal exists to catch the leak shape before that happens.

Detection walks `git worktree list --porcelain` for linked worktrees, then probes each untracked file in the parent against every linked worktree:

```bash
for wt in $(git worktree list --porcelain | awk '/^worktree / && $2 != repo_root {print $2}'); do
  for path in $(git status --porcelain --untracked-files=all | awk '/^\?\? / {sub(/^\?\? /,""); print}'); do
    # Match if the path exists in the linked worktree (working tree or HEAD).
    if [ -e "$wt/$path" ] || git -C "$wt" cat-file -e "HEAD:$path" 2>/dev/null; then
      echo "WORKTREE_LEAK_PATH=$path WORKTREE=$wt"
    fi
  done
done
```

A leak match yields the dedicated verdict `worktree_leak_suspected`. The response is the same as for any coworker signal — **leave the working tree alone** — with one addition: do not commit on the parent branch while child worktree agents are running, because the parent's untracked entry will be reclaimed by the child's commit.

Limitations:

- Two agents writing genuinely independent files that happen to share a path will produce a false-positive leak match. Treat the verdict as a strong hint, not a proof.
- A bare-clone style harness that doesn't use `git worktree` won't produce any `LINKED_WORKTREE_COUNT > 0`, so the signal silently degrades to a no-op there.

## Response Rules

When any signal reports a coworker:

1. **Do not stash, restore, or reset.** Leave the working tree alone.
2. **Scope operations to your own files.** Use `git add <explicit paths>` — never `git add -A` or `git add .`.
3. **Warn the user** with the list of other PIDs or changed files, and let them decide.
4. **Prefer a worktree.** If starting a new session in a dirty clone with a live coworker, create `git worktree add ../<repo>-<task>` instead of working in-place.

When no signal reports a coworker, still prefer explicit paths over bulk staging — the detection is best-effort, not a guarantee.

## Integration Points

| Where | How |
|-------|-----|
| `git-coworker-check` skill | User-invocable diagnostic — runs all three signals and reports |
| `git-commit*` skills | Call the baseline-drift check before staging; fail loudly if drift is detected |
| `git-maintain` skill | Never runs `git stash` or `git clean` without first running the coworker check |
| SessionStart hook (optional) | Write the session marker; capture the baseline snapshot |
| PreToolUse hook (optional) | Block `git stash`, `git checkout -- .`, `git reset --hard` when a coworker is detected |

The skill is the primary surface; hooks are an enforcement layer that users can opt into via `hooks-plugin`.

## Anti-Patterns

| Don't | Do |
|-------|-----|
| `git stash` on "unexpected" changes | Compare against baseline first |
| `git add -A` / `git add .` | Stage explicit paths you know you touched |
| `git clean -fd` as cleanup | Never auto-clean in a shared checkout |
| Trust `git status` as "my changes" | Treat it as "everyone's changes" until proven otherwise |
| Block on the process scan alone | Treat it as a hint; the baseline + markers are authoritative |

## Limitations

- **Marker files** only help when both agents adopt the convention. An agent that skips writing a marker is invisible to marker-based detection.
- **Process scans** fail silently in sandboxes without `/proc` or `lsof` — rely on baseline drift in those environments.
- **Baseline drift** cannot tell "my earlier edit I forgot about" from "a coworker's edit". When in doubt, ask the user.
- None of these signals handle concurrent writes to the **same file** — they only detect that a coworker exists, not that you are about to clobber its work.

## Related Rules

- `.claude/rules/handling-blocked-hooks.md` — how to respond when a PreToolUse coworker-check hook blocks a command
- `.claude/rules/agent-development.md` — worktree isolation as the preferred answer to concurrency
- `.claude/rules/sandbox-guidance.md` — `/proc` and `lsof` availability in the web sandbox
