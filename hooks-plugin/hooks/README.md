# Claude Code Hooks

This directory contains hooks that enforce best practices and remind Claude to use the correct tools.

## bash-antipatterns.sh

A PreToolUse hook that intercepts Bash commands and blocks those that should use built-in tools instead.

### Anti-patterns Detected

| Pattern | Reminder |
|---------|----------|
| `cat file` (whole command only — #2148) | Use **Read** tool instead |
| `head`/`tail file` (whole command only — #2148) | Use **Read** tool with offset/limit |
| `sed -i` on repo files (targets under `/tmp`, `/private/tmp`, `/var/folders`, `$TMPDIR` are exempt — #2052) | Use **Edit** tool instead |
| `echo > file` | Use **Write** tool instead |
| `cat > file` | Use **Write** tool instead |
| `timeout cmd` | Remove timeout (Bash tool has its own, human approval time exceeds it anyway); append a `# allow-timeout` comment to bound a genuinely-never-exiting process (REPL, stdio server) — #2041 |
| `cat/tail ...tasks/*.output` (whole command only — #2148) | Use **Read** tool on the output path (or pipe an extraction for large files) |
| `git add -A` / `git add .` | Stage specific files by name instead of broad staging |
| `git X && git Y` where **both** X and Y modify the index (`add`, `commit`, `rm`, `mv`, `reset`) | Run the two git commands as separate Bash calls (avoids index.lock race condition). Chaining one index writer to a read-only git command — `git add f && git status --short` — is allowed |
| `git reset --hard` | Use safer alternatives; if truly needed, ask user to run manually |

### Structural classification (ast-grep) and fail-open (#2008)

The scoping-sensitive read/write detectors — `cat`/`head`/`tail` reads,
`echo`/`printf`/`cat` writes, `sed -i`, and task-output reads — are classified
**structurally** with `ast-grep --lang bash` (tree-sitter-bash) rather than
regex. A real parse gives distinct AST node shapes for "`cat` reading a file"
vs "`cat` in a pipeline" vs "`cat <<EOF`" vs "`cat > file`" vs a `cat`
*mentioned* inside a string or heredoc body — distinctions the old regex path
faked with three pre-stripping passes and a remote-exec guard, and repeatedly
got wrong (#1701, #1721, #1722, #1848, #1900, #2052, #2058). A read command
inside `ssh host <<EOF … EOF`, `ssh host 'ls|grep'`, or `kubectl exec … -- cat`
is a heredoc-body / string / argument node, never a `command_name`, so it is
never mis-detected — the remote-exec guard is no longer needed.

**Read detectors fire only on a whole-command read (#2148).** The structural
port widened the read block from "a bare read as the whole command" (the
pre-#2114 regex scope) to "a bare read anywhere in a compound command"; W31
friction measured the cost as a 15.2% → **46.3%** same-session repeat-block
rate. The three read rules (`cat-read`, `head-tail-read`, `task-output-read`)
now additionally require `inside: { kind: program }` plus a first-and-last
`nthChild` gate (comment siblings excluded), so `cat f.md` blocks while
`cd repo && cat f.md` and `ls d/; head -20 f` pass. The three **write**
detectors keep their original scope — they guard file mutation, not context
budget. See `.claude/rules/bash-tool-replacements.md`.

These are **style nudges** and **fail open**: when `ast-grep` is absent
(sandboxes, subagents) they simply do not fire. Losing a "use Read instead of
`cat`" steer where the parser is unavailable costs nothing irreversible, and
there is deliberately **no regex twin** to keep in lockstep. The **safety /
correctness blocks** (`curl|bash`, `chmod 777`, `git add -A`, `git reset
--hard`, `git push -u` footgun, block-device writes, fork bombs, the index-lock
chain, the grep-chain test-output scrape, `awk`/`cat`-to-commit-file) stay
pure-regex and fire in **every** context. Set
`CLAUDE_HOOKS_BASH_ANTIPATTERNS_NO_ASTGREP=1` to force the no-op path (used by
the regression suite to exercise fail-open).

### Line-anchored safety blocks skip heredoc bodies (#2431)

Four blocks stay pure-regex and are anchored with `^`: `timeout`, `git add -A`,
`git reset --hard`, and the `git push -u <src>:<dst>` footgun. `^` in `grep`
matches the start of **every line**, not the start of the command, so in a
multi-line command a heredoc *body* line beginning with a watched word was read
as if it were the command. The reported break: a `git commit -F - <<EOF` whose
message described a *connection timeout* was blocked with "REMINDER: The
'timeout' command is usually unnecessary — remove the timeout wrapper". There
was no wrapper; the word was prose.

All four now scan `COMMAND_SHELL_ONLY` (heredoc bodies and trailing `#` comments
removed) instead of the raw command. The per-line anchoring is **kept** — a
genuine command on line 2 of a multi-line Bash call is still the start of a
command and still blocks; only heredoc-body lines are exempt. The `timeout`
escape hatch reads a separate `COMMAND_NO_HEREDOC` view (comments intact),
because `# allow-timeout` is itself a comment.

### Demoted to opt-in teach nudges (not blocked)

`find` (→ **Glob**, #1871), `grep`/`rg` (→ **Grep**, #1909), `ls <glob>`
(→ **Glob**, #2036), and **long pipelines** (5+ pipes fed from a
cat/echo/printf or redundant grep|grep head, #1873/#2051/#2052) are
intentionally **not** blocked by this hook. None of those blocks did safety
work, and each hard-dead-ended subagents whose toolset lacks the suggested
alternative. The steers survive as non-blocking hints in
`bash-antipatterns-teach.sh`, opt-in via
`CLAUDE_HOOKS_ENABLE_BASH_ANTIPATTERNS_TEACH=1`. The long-pipeline nudge
counts pipes **per pipeline** (statement-split on newlines/`;`/`&&`/`||`),
not per Bash invocation, so independent single-pipe statements never sum past
the threshold (#2051). See `.claude/rules/bash-tool-replacements.md` and
`.claude/rules/hook-block-vs-nudge.md`.

### Handling Blocked Commands

When a command is blocked:

1. **Read the reminder** - It explains why and suggests alternatives
2. **Use the alternative** - Most of the time, the suggested approach is correct
3. **If truly needed** - Don't retry; ask the user to run the command manually with an explanation

**Important**: User permission does not bypass hook blocks. If a command is blocked, retrying will fail again. For rare edge cases where the blocked command is legitimately required, ask the user to run it manually and explain why.

### How It Works

1. The hook receives JSON input from Claude Code containing the Bash command
2. It extracts the command and checks against known anti-patterns
3. If an anti-pattern is detected, it exits with code 2 (blocking error) and prints a helpful reminder
4. The reminder is shown to Claude, who will then use the correct tool

### Configuration

The hook is configured in `.claude/settings.json`:

```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Bash",
        "hooks": [
          {
            "type": "command",
            "command": "bash $CLAUDE_PROJECT_DIR/.claude/hooks/bash-antipatterns.sh",
            "timeout": 5
          }
        ]
      }
    ]
  }
}
```

### Testing

To test the hook manually:

```bash
echo '{"tool_input": {"command": "cat README.md"}}' | bash .claude/hooks/bash-antipatterns.sh
echo $?  # Should be 2 (blocked)

echo '{"tool_input": {"command": "git status"}}' | bash .claude/hooks/bash-antipatterns.sh
echo $?  # Should be 0 (allowed)

echo '{"tool_input": {"command": "git stash && git checkout -b branch"}}' | bash .claude/hooks/bash-antipatterns.sh
echo $?  # Should be 2 (blocked - chained git commands cause lock race conditions)
```

### Customization

Edit `bash-antipatterns.sh` to:
- Add new anti-patterns
- Modify reminder messages
- Adjust detection regex patterns
- Whitelist specific commands

### Exit Codes

- **0**: Command allowed
- **2**: Command blocked with reminder (Claude sees the message)

---

## validate-kubectl-context.sh

A PreToolUse hook that enforces explicit Kubernetes context selection to prevent accidental operations on the wrong cluster.

### Why This Hook Exists

Running `kubectl` or `helm` commands without specifying `--context` uses whatever context is currently active in your kubeconfig. This can lead to:

- Accidentally deploying to production instead of staging
- Deleting resources from the wrong cluster
- Applying configuration changes to unintended environments

This hook blocks kubectl/helm commands that don't explicitly specify their target context, forcing the agent to be explicit about which cluster it's operating on.

### Commands Blocked

| Tool | Flag Required | Example |
|------|---------------|---------|
| `kubectl` | `--context=NAME` | `kubectl --context=staging get pods` |
| `helm` | `--kube-context=NAME` | `helm --kube-context=production list` |

### Safe Commands (Not Blocked)

Some commands are safe without context specification:

**kubectl safe commands:**
- `kubectl config` (manages kubeconfig, not cluster resources)
- `kubectl version` (shows client/server versions)
- `kubectl api-resources` (lists available resources)
- `kubectl api-versions` (lists API versions)
- `kubectl explain` (shows resource documentation)
- `kubectl completion` (shell completion)

**helm safe commands:**
- `helm version` / `helm completion` / `helm env`
- `helm repo` (manages chart repositories)
- `helm search` (searches for charts)
- `helm show` (shows chart information)
- `helm plugin` (manages plugins)
- `helm create` / `helm package` / `helm template` (local chart operations)

### Configuration

**Automatic (via plugin):** This hook is automatically enabled when the hooks-plugin is installed. The configuration is included in `plugin.json`.

**Manual (standalone):** To use this hook without the full plugin, add to your `.claude/settings.json`:

```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Bash",
        "hooks": [
          {
            "type": "command",
            "command": "bash /path/to/validate-kubectl-context.sh",
            "timeout": 3000
          }
        ]
      }
    ]
  }
}
```

### Testing

```bash
# Should be blocked (no context)
echo '{"tool_input": {"command": "kubectl get pods"}}' | bash validate-kubectl-context.sh
echo $?  # 2

# Should be allowed (has context)
echo '{"tool_input": {"command": "kubectl --context=staging get pods"}}' | bash validate-kubectl-context.sh
echo $?  # 0

# Should be allowed (safe command)
echo '{"tool_input": {"command": "kubectl config get-contexts"}}' | bash validate-kubectl-context.sh
echo $?  # 0

# Helm - should be blocked
echo '{"tool_input": {"command": "helm list"}}' | bash validate-kubectl-context.sh
echo $?  # 2

# Helm - should be allowed
echo '{"tool_input": {"command": "helm --kube-context=production list"}}' | bash validate-kubectl-context.sh
echo $?  # 0
```

### Error Message

When blocked, the agent receives a helpful message explaining:
- Why the context is required
- How to specify the context
- How to list available contexts
- Example commands with proper context usage

---

## git-stash-session-init.sh

A SessionStart hook that records the current git stash baseline for session-scoped tracking. Required by `git-stash-reminder.sh`.

### How It Works

1. Receives JSON input with `cwd` and `session_id`
2. Lists all current stash commit hashes with `git stash list --format='%H'`
3. Writes them to `<baseline-dir>/{session_id}.d/<sha256-of-git-common-dir>`, and
   stamps `<baseline-dir>/{session_id}.d/.session-start` whose **mtime** is the
   session start
4. The Stop hook uses both: the baseline to ignore pre-existing stashes, and the
   marker as the age bound for "created during this session"

`<baseline-dir>` defaults to `/tmp/claude-stash-baselines`; override with
`CLAUDE_STASH_BASELINE_DIR`. The key is the **git common dir**
(`git rev-parse --git-common-dir`, realpath'd), *not* the repo root — `refs/stash`
lives in the common dir and is shared by every linked worktree, so one stash
namespace maps to exactly one baseline.

### Behavior

| Event | Action |
|-------|--------|
| Session startup | Records all stash commit hashes as baseline and stamps `.session-start` |
| Session resume / compact / clear | **Leaves both alone** — each write is once-per-session, so a re-fire cannot move the age bound and retroactively un-report an already-flagged stash |
| Not a git repo | Silent exit |
| No stashes | Writes a baseline containing only its `# <namespace>` header |

Baselines are **never empty**: every one carries a `# <namespace>` header line,
and that non-emptiness is what distinguishes a legitimately stash-free repo from
a capture that failed. A 0-byte baseline is read as UNKNOWN, and the reminder
stays silent rather than guessing.

### Configuration

Configured in `.claude-plugin/plugin.json` as a SessionStart event with matcher `""` (all events).

---

## git-stash-reminder.sh

A Stop hook that checks for git stashes **created during the current session**. Pre-existing stashes (recorded at session start by `git-stash-session-init.sh`) are ignored. Only blocks when session-created stashes remain unaddressed.

### Behavior

| Condition | Action |
|-----------|--------|
| Session stashes exist | Block exit, recommend `git stash pop` |
| Only pre-existing stashes | Silent exit (no block) |
| No stashes at all | Silent exit |
| No baseline file | Silent exit (avoids false positives) |
| `stop_hook_active` is true | Silent exit (prevents infinite loops) |
| Not a git repo | Silent exit |

### How It Works

1. The hook receives JSON input with `cwd`, `session_id`, and `stop_hook_active`
2. Guards against infinite loops (`stop_hook_active` check)
3. Lists current stashes with `git stash list --format='%H|%gd|%ct|%gs'`
4. Loads the baseline file for this session (written by `git-stash-session-init.sh`)
5. Filters out stashes whose commit hashes appear in the baseline
6. If new (session-created) stashes remain, outputs `{"decision": "block", "reason": "..."}`
7. Claude sees the list of session stashes with recommended actions

### Edge Cases

- **No stashes**: Exits silently with code 0
- **Not a git repo**: Exits silently with code 0
- **No `cwd` in input**: Exits silently with code 0
- **No baseline file**: Exits silently (avoids false positives on first use)
- **`stop_hook_active` is true**: Exits silently (loop prevention)
- **Stash subjects containing `|`**: Handled safely via `IFS='|' read` (subject captures remainder)
- **Pre-existing stashes only**: All filtered out by baseline comparison, silent exit

### Configuration

The hook is configured in `.claude-plugin/plugin.json` as a Stop event:

```json
{
  "hooks": {
    "Stop": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "bash ${CLAUDE_PLUGIN_ROOT}/hooks/git-stash-reminder.sh",
            "timeout": 10000
          }
        ]
      }
    ]
  }
}
```

### Testing

```bash
# Setup test repo
cd /tmp && git init test-stash && cd test-stash
echo "test" > file.txt && git add . && git commit -m "init"

# Create a pre-existing stash
echo "old" > file.txt && git stash push -m "pre-existing"

# Record baseline (simulates SessionStart)
echo '{"cwd": "/tmp/test-stash", "session_id": "test-123"}' | \
  bash hooks/git-stash-session-init.sh

# Test: only pre-existing stashes (should exit 0, no output)
echo '{"cwd": "/tmp/test-stash", "session_id": "test-123"}' | \
  bash hooks/git-stash-reminder.sh

# Create a new stash during the "session"
echo "new" > file.txt && git stash push -m "session stash"

# Test: new session stash (should output block JSON)
echo '{"cwd": "/tmp/test-stash", "session_id": "test-123"}' | \
  bash hooks/git-stash-reminder.sh
# Expected: {"decision":"block","reason":"Found 1 git stash(es) created during this session..."}

# Test: stop_hook_active guard (should exit 0, no output)
echo '{"cwd": "/tmp/test-stash", "session_id": "test-123", "stop_hook_active": true}' | \
  bash hooks/git-stash-reminder.sh

# Test: missing baseline (should exit 0, no output)
echo '{"cwd": "/tmp/test-stash", "session_id": "no-baseline"}' | \
  bash hooks/git-stash-reminder.sh

# Cleanup
rm -rf /tmp/test-stash
rm -rf /tmp/claude-stash-baselines/test-123.d
```

The baseline is a per-session **directory** (`<session_id>.d/`), so `rm -f` on the
flat path removes nothing the hooks write — that path only ever matches a
pre-#2306 legacy baseline.

---

## repo-deletion-safety.sh

A PreToolUse hook that blocks `rm -rf` on a git repository whose history exists
nowhere else — no remote, or a remote that has never been pushed to.

### Why This Hook Exists

`rm -rf` on such a checkout destroys committed history, the working tree, every
stash and every unpushed branch in one stroke. There is no reflog, no
`git fsck --lost-found`, no PR and no coworker's clone to recover from. This is
the one deletion shape with a strictly empty recovery path, which is why it is a
hard block (exit 2) rather than a nudge — see
[`.claude/rules/hook-block-vs-nudge.md`](../../.claude/rules/hook-block-vs-nudge.md)
and the source skill `git-plugin:git-repo-delete-check`.

The block message reports what the preflight **found** in that repo (commits,
uncommitted changes, stashes, local branches) and points at
`git-plugin:git-repo-delete-check` for the remediation options — that skill is
their single authority, and the message deliberately does not restate them
(#2454).

The one option it keeps verbatim is the tar backup to `$CLAUDE_REPO_BACKUP_DIR`,
because that command is what makes the block **self-extinguishing**: writing the
tarball (like pushing) changes the world state the hook reads, so the retried
`rm -rf` succeeds on the next attempt with no override. That property is what
keeps the same-session repeat-block rate near zero, and it is why the one
surviving overlap with the skill has a mechanical reason to be there.

Every findings probe is **capped** (`FINDINGS_CAP`, 500). `emit_block` runs on
the blocking path and this hook fails **open** on timeout, so an unbounded
`git rev-list --all --count` would turn an already-decided hard block into a
deletion on a large repo — measured at 1281 ms over a 200,000-commit graph
against 21 ms with `--max-count=500`. A capped value renders as `500+`. A repo
with **no commits** gets a different headline and an explicit note, so an
all-zero findings report never reads as an argument against its own block.

### Commands Blocked

| Condition | Behavior |
|-----------|----------|
| `rm -r`/`-rf`/`-fr`/`--recursive` on a repo **root** with no remote (tier 1a) | **Blocked** (exit 2) |
| Same, on a repo whose remote has never been pushed to — no `refs/remotes` (tier 1b) | **Blocked** (exit 2) |
| Same, on a plain directory that *holds* repos (scanned to depth 3, capped at 20 hits) | **Blocked** per offending repo |
| A remote-backed repo carrying uncommitted / unpushed / stashed work (tier 2) | `permissionDecision: "ask"` — **opt-in**, off by default |

The operand must be a repo **root**: the hook compares
`git rev-parse --absolute-git-dir` against `<dir>/.git` (or `<dir>` for a bare
repo). That single predicate excludes subdirectories, linked worktrees and
submodules, whose `.git` resolves elsewhere. Leading `VAR=value` assignments and
`sudo`/`command`/`env`/`nice` wrappers are stripped before classification, so an
inline bypass attempt is still classified as the `rm` it is. Safety blocks
deliberately fire inside compound commands and pipelines — only the
context-budget read-blocks were narrowed to whole-command scope (#2148).

### Safe Commands (Not Blocked)

- `rm -rf node_modules` / `dist` / any path **inside** a repo — not a repo root.
- A linked worktree or a submodule directory — `--absolute-git-dir` points into the parent.
- A symlink to a repo — `rm -rf link` removes the link, not the target.
- `rm -f <file>` and any `rm` with no recursion flag.
- Repos under `/tmp`, `/private/tmp`, `/var/folders`, `$TMPDIR` (default; see Configuration).
- A repo for which a dated `<basename>-*.tar.*` already exists in `$CLAUDE_REPO_BACKUP_DIR`.
- The command text appearing inside a quoted string (`git commit -m "rm -rf old"`).
- Remote-exec first tokens: `ssh`, `scp`, `rsync`, `docker`, `podman`, `kubectl`, `nerdctl` (#1900).

### Known Gaps

The hook **fails open** by design; a reader must not over-trust it. Uncovered, in
full:

| Gap | Why |
|-----|-----|
| Unresolvable operands — `$VAR`, `$(…)`, backticks, `{}` from `find -exec` | The hook cannot know the target, so it declines to guess |
| Globs — `rm -rf repo/*` | Without `dotglob`, `*` does not match `.git`, so history survives; but `rm -rf repo/.[!.]*` therefore **slips through**. Accepted |
| Symlinks | `rm` removes the link, not the repo |
| Remote-exec commands | The deletion targets a filesystem this hook cannot inspect |
| Temp dirs, by default | This repo's own fixtures create remote-less repos under `mktemp -d` and clean them up with `rm -rf` |
| A remote whose URL is itself a local path | Counts as "has a remote" and clears the block — not decidable inside a hook |
| Sibling deletion verbs | `git clean -xdff`, `trash`, `mv repo /tmp`, `rmdir`, `shred`, `find … -delete` are **out of scope** |

### Configuration

| Variable | Default | Effect |
|----------|---------|--------|
| `CLAUDE_HOOKS_DISABLE_REPO_DELETION_SAFETY` | unset | `1` disables the hook. Honored **only** from the operator's exported shell environment — an inline `VAR=1 rm -rf …` prefix is not honored (the parser strips leading assignments), so do not self-serve it |
| `CLAUDE_REPO_BACKUP_DIR` | `$HOME/Backups` | Where an existing `<basename>-*.tar.*` clears the block; also the directory named in the block message |
| `CLAUDE_HOOKS_REPO_DELETION_TMP_EXEMPT` | `1` | `0` also guards repos under `/tmp`, `/private/tmp`, `/var/folders`, `$TMPDIR` |
| `CLAUDE_HOOKS_REPO_DELETION_WARN_DIRTY` | `0` | `1` enables the tier-2 `ask` on a remote-backed repo carrying uncommitted / unpushed / stashed work |

### Testing

```bash
# Blocks (exit 2). The fixture lives under mktemp -d, which the hook exempts by
# DEFAULT — CLAUDE_HOOKS_REPO_DELETION_TMP_EXEMPT=0 is what makes it a real test.
T=$(mktemp -d) && git init -q "$T/lonely" && git -C "$T/lonely" commit -q --allow-empty -m init
echo "{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"rm -rf $T/lonely\"},\"cwd\":\"$T\"}" \
  | CLAUDE_HOOKS_REPO_DELETION_TMP_EXEMPT=0 bash hooks-plugin/hooks/repo-deletion-safety.sh; echo $?   # 2

# Same command with the default tmp exemption: allowed.
echo "{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"rm -rf $T/lonely\"},\"cwd\":\"$T\"}" \
  | bash hooks-plugin/hooks/repo-deletion-safety.sh; echo $?                                          # 0
rm -rf "$T"

# A path inside a repo is never a repo root: allowed.
echo '{"tool_name":"Bash","tool_input":{"command":"rm -rf node_modules"},"cwd":"'"$PWD"'"}' \
  | bash hooks-plugin/hooks/repo-deletion-safety.sh; echo $?                                          # 0

bash hooks-plugin/hooks/test-repo-deletion-safety.sh   # 83 passed, 0 failed
```

### Exit Codes

- **0**: Command allowed — or the opt-in tier-2 `ask` envelope was printed on stdout.
- **2**: Tier-1 block via the standard `block()` convention; the message is shown to Claude.

Tier 2 deliberately does **not** use `block()`: it prints a `PreToolUse`
`permissionDecision: "ask"` JSON envelope and exits 0.

---

## branch-base-guard.sh

A PreToolUse hook that nudges before cutting a new branch from a local default
branch that is **ahead of its remote** — `git-hazards.md` trap #2: unpushed
commits on local `main` ride into the new branch, get bundled into that branch's
PR under an unrelated title, and a squash-merge hides them everywhere except the
file list.

### Why This Hook Exists

Nothing here is irreversible — the worst case is a PR whose file list is wider
than its title, fixable with a single `git rebase --onto`. So this is a **nudge**
(`permissionDecision: "ask"`), never a deny, matching the tier of its sibling
`git-plugin/hooks/check-branch-sync-on-push.sh`. It fires at most once per
session+repo+default per TTL, stays completely silent when the ahead-count is 0,
and self-extinguishes once `main` is pushed or the branch is cut from
`origin/<default>`.

The default branch is **resolved** (`refs/remotes/origin/HEAD`, then a probed
`main`/`master` fallback), never hardcoded — `origin/HEAD` is unset in most agent
worktrees, `--single-branch` clones and CI checkouts, so the fallback is the
usual path rather than the exception.

Unlike `branch-protection.sh`, this hook does **not** defer under permission mode
`"auto"`: auto mode's classifier reasons about protected-branch writes and
force-pushes and has no notion of which base a branch is cut from, so deferring
would leave the hazard ungated rather than avoid a double-gate.

### When It Nudges

`git switch -c/-C/--create/--force-create <b>`, `git checkout -b/-B <b>`, and
`git worktree add … -b/-B <b>` — when **all** of:

1. HEAD is the resolved default branch,
2. no explicit start-point was given, and
3. local `<default>` is ≥1 commit ahead of `origin/<default>`.

### Safe Commands (Not Nudged)

- Any create with an explicit start-point — `git switch -c feat/x origin/main`. This is the hook's own suggested fix and is exempt **by design**; getting it wrong would make the corrected command re-trigger the nudge.
- `--track` / `-t <upstream>` forms.
- Creating from a feature branch (stacking is deliberate).
- A default branch already in sync; repos with no `origin`; detached HEAD.
- `git switch <b>` / `git checkout <b>` with no create flag; **all** `git branch` forms.
- The command appearing inside a quoted string (`git commit -m "git switch -c x"`) — quoted segments are scrubbed before matching.
- `ssh` / `docker` / `podman` / `kubectl` / `nerdctl` remote-exec.

### Known Gaps

- **Bare `git branch <name>` is deliberately out of scope.** Listing, deleting and `-vv` dominate its real-world use, so disambiguating creation costs more false positives than the coverage buys.
- A **stale** `refs/remotes/origin/<default>` that was never fetched can **overstate** — never understate — the ahead-count. Opt into a fetch with `CLAUDE_HOOKS_BRANCH_BASE_FETCH=1`.
- Cutting from an equally-ahead **feature** branch is not covered.

### Configuration

| Variable | Default | Effect |
|----------|---------|--------|
| `CLAUDE_HOOKS_DISABLE_BRANCH_BASE_GUARD` | unset | `1` disables the hook entirely. The documented answer for a repo that legitimately develops on its default branch (dotfiles, personal repos). Honored only from the operator's exported shell environment — an inline `VAR=1 git switch -c …` prefix is intentionally ignored |
| `CLAUDE_HOOKS_BRANCH_BASE_TTL` | `300` | Dedup window (seconds) per session+repo+default |
| `CLAUDE_HOOKS_BRANCH_BASE_FETCH` | `0` | `1` runs `git fetch --quiet origin <default>` on a cache miss before measuring — a network round-trip for a fresher ahead-count |

### Testing

The nudge needs a local default branch that is ahead of its remote, so the
fixture below builds one. Running the snippets against an arbitrary checkout
usually prints nothing — a feature branch, or a `main` in sync, is exempt.

```bash
T=$(mktemp -d) && git init -q --bare "$T/origin.git" && git init -q -b main "$T/repo" \
  && git -C "$T/repo" -c user.email=t@t -c user.name=T commit -q --allow-empty -m init \
  && git -C "$T/repo" remote add origin "$T/origin.git" && git -C "$T/repo" push -q -u origin main \
  && git -C "$T/repo" -c user.email=t@t -c user.name=T commit -q --allow-empty -m "stray commit on main"

# Nudges (prints the `ask` envelope) — local main is ahead of origin/main:
echo "{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"git switch -c feat/x\"},\"cwd\":\"$T/repo\",\"session_id\":\"t1\"}" \
  | bash hooks-plugin/hooks/branch-base-guard.sh; echo $?   # envelope on stdout, exit 0

# Silent — the suggested fix must never re-trigger the nudge:
echo "{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"git switch -c feat/x origin/main\"},\"cwd\":\"$T/repo\",\"session_id\":\"t2\"}" \
  | bash hooks-plugin/hooks/branch-base-guard.sh; echo $?   # no output, exit 0
rm -rf "$T"

bash hooks-plugin/hooks/test-branch-base-guard.sh   # 59 passed, 0 failed
```

Use a distinct `session_id` per invocation, or the TTL dedup silences the second
call regardless of its content.

### Exit Codes

Always **0**. The nudge is signalled by a `PreToolUse`
`permissionDecision: "ask"` JSON envelope on stdout; absence of output means
"allow silently". This hook deliberately does not use the `block()` / exit-2
convention.
