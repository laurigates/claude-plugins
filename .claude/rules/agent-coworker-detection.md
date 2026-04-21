# Agent Coworker Detection

How an agent detects that another agent is already working in the same repository clone, and how it avoids destroying that coworker's in-flight changes.

## The Problem

When two agents run concurrently in the **same checkout** (rather than separate worktrees), they observe each other's uncommitted changes through `git status`. A naive agent sees files it did not touch, assumes the tree is dirty, and runs `git stash`, `git restore`, or `git checkout -- .` to "clean up". The coworker then finds its work has disappeared and may attempt its own recovery, compounding the loss.

The root cause is missing coordination: each agent assumes it is the sole writer in the working tree.

## Detection Signals

No single signal is reliable. Combine these three and treat any positive as "assume a coworker is present".

| Signal | Detects | Cost | Platform |
|--------|---------|------|----------|
| **Baseline drift** — snapshot `git status --porcelain` + `git stash list` at session start; diff at risky moments | Files that appeared after we started, regardless of who created them | Free | All |
| **Session marker** — write `.git/.claude-session-<pid>` on start, delete on exit; scan siblings | Other agents that adopt the same convention | Free | All |
| **Process scan** — find other `claude`/`node` processes whose `cwd` is the same repo | Ad-hoc agents that do not write markers | ~100ms | Linux/macOS differ |

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
