---
created: 2026-04-21
modified: 2026-10-02
reviewed: 2026-10-02
---

# Agent Coworker Detection

How an agent detects that another agent is already working in the same repository clone, and how it avoids destroying that coworker's in-flight changes.

Unscoped on purpose: the hazard fires on a git **command** (`stash`, `reset`, `add -A`, `worktree remove`), not on editing a file of a known shape, so a `paths:` glob cannot scope it (`.claude/rules/context-engineering.md`).

## The Problem

When two agents run concurrently in the **same checkout** (rather than separate worktrees), they observe each other's uncommitted changes through `git status`. A naive agent sees files it did not touch, assumes the tree is dirty, and runs `git stash`, `git restore`, or `git checkout -- .` to "clean up". The coworker then finds its work has disappeared and may attempt its own recovery, compounding the loss.

The root cause is missing coordination: each agent assumes it is the sole writer in the working tree.

## Detection Signals

No single signal is reliable. Combine these seven and treat any positive as "assume a coworker is present".

| Signal | Detects | Cost | Platform |
|--------|---------|------|----------|
| **Baseline drift** — snapshot `git status --porcelain` + `git stash list` at session start; diff at risky moments | Files that appeared after we started, regardless of who created them | Free | All |
| **Session marker** — write `.git/.claude-session-<pid>` on start, delete on exit; scan siblings | Other agents that adopt the same convention | Free | All |
| **Process scan** — find other `claude`/`node` processes whose `cwd` is the same repo | Ad-hoc agents that do not write markers | ~100ms | Linux/macOS differ |
| **Taskwarrior `+ACTIVE` claims** — query `task project:<repo-basename> +ACTIVE export` for claims by other agent IDs | Coworkers that picked up coordination work via `/taskwarrior:task-claim`, even from a different process tree or host | ~50ms | Any host with `task` + `jq` |
| **Worktree leak** — every untracked file in the parent is probed against the working tree and HEAD of each linked `git worktree` | Transient leaks where a child `Agent(isolation: "worktree")` writes a file that briefly appears in the parent checkout at the same relative path (issue #1319) | ~10ms per worktree | All |
| **Bare flip** — the shared checkout reports `core.bare=true` via `git rev-parse --is-bare-repository`, or a leaked `GIT_DIR` / `GIT_WORK_TREE` env points away from the repo | A concurrent agent fleet flipping the shared repo to bare (every `git status`/`commit` then fails with "fatal: this operation must be run in a work tree") or redirecting git at another tree (issue #1692) | Free | All |
| **Cross-session discovery** — `ListAgents` (native, 2.1.224+) | Other live Claude Code sessions on this or other machines that have cross-session messaging enabled | Free (built-in tool call) | macOS/Linux (2.1.224), Windows (2.1.239) |

How each signal is computed, its platform caveats, and the verdict vocabulary live in `git-plugin:git-coworker-check` (`detect-coworkers.sh`, `claim-session.sh`, and its REFERENCE.md § Signal design). Run `/git:coworker-check` rather than re-deriving a probe by hand. Two of the signals are harness gotchas worth holding every turn:

### Worktree leak (issue #1319)

A child `Agent(isolation: "worktree")` can briefly leak a new file into the **parent** checkout as an untracked file at the same relative path; it vanishes when the child commits. Do not stash, stage, or commit that path — and do not commit on the parent branch at all while child worktree agents are running, because the parent's untracked entry will be reclaimed by the child's commit.

### Bare flip (issue #1692)

`fatal: this operation must be run in a work tree` on every `git status`/`commit` means the shared checkout was flipped to `core.bare=true`, or a leaked `GIT_DIR`/`GIT_WORK_TREE` redirected git at another tree. It is not your fault; stop and recover via `git-plugin:git-coworker-check` § Recovering from a bare flip. Worktree-isolation hardening (2.1.216, 2.1.222; `.claude/rules/agent-runtime.md` § Worktree Isolation) closes the isolation-driven path to this hazard on 2.1.222+; the *shared, non-isolated* checkout cause — a script/hook bug (the class `scripts/check-git-sandbox-guards.sh` guards against) or a bad `GIT_DIR` export — remains.

**Commit early.** Untracked files are the only work a concurrent branch switch / reset can destroy with no recovery path — committed work survives in the reflog, untracked work does not. When many sibling worktrees are active in one clone, commit or stash new files promptly and prefer working in your own `git worktree` so a flip in the shared checkout cannot reach your tree.

## Response Rules

When any signal reports a coworker:

1. **Do not stash, restore, or reset.** Leave the working tree alone.
2. **Scope operations to your own files.** Use `git add <explicit paths>` — never `git add -A` or `git add .`.
3. **Warn the user** with the list of other PIDs or changed files, and let them decide.
4. **Prefer a worktree.** If starting a new session in a dirty clone with a live coworker, create `git worktree add ../<repo>-<task>` instead of working in-place.

When no signal reports a coworker, still prefer explicit paths over bulk staging — the detection is best-effort, not a guarantee.

### Cleanup: never force-remove worktrees you don't own (issue: 2026-06-28)

A prune that removes **every worktree whose branch is not on origin** sweeps up
*other sessions'* in-flight worktrees — local-only branches are exactly what an
active peer is mid-work on — and `git worktree remove --force` then **discards
their uncommitted changes** with no recovery path.

**The rule:** scope worktree pruning to **your own session's** worktrees by name
(e.g. only `wf_<this-run-id>-*`, or paths you created this session). Never
`--force`-remove a worktree whose branch you did not create. To reclaim space
safely, prefer `git worktree prune` (removes only entries whose directory is
already gone) over enumerating-and-force-removing live ones. When unsure who owns
a worktree, leave it — a stale worktree costs disk; a force-removed one can cost a
coworker their afternoon.

**Correct scoping is not sufficient — "all PRs merged" is not the completion
signal.** A non-force remove refuses on a dirty tree, so it cannot lose data, but
an agent whose PR has merged may still be mid-rebase or messaging a peer, and
`SendMessage` to a removed worktree fails permanently, so the peer cannot even be
warned.

- **Gate removal on the agent-completion notification, never on PR state.** The
  harness reports each agent's completion; merged PRs say nothing about whether
  the agent has more to do.
- **Announce before removing shared state**, or simply don't — worktree cleanup
  is never urgent, and deferring it to the next session costs only disk.
- A `locked` worktree is a live-work signal. Leave it.

The incidents behind this section (~24 force-removed peer worktrees; the 2026-08-15 non-force cleanup that still killed two live peers) are recorded in `agent-patterns-plugin:parallel-agent-dispatch` `references/worktree-hazards.md` § Remedy.

## Anti-Patterns

| Don't | Do |
|-------|-----|
| `git stash` on "unexpected" changes | Compare against baseline first |
| `git add -A` / `git add .` | Stage explicit paths you know you touched |
| `git clean -fd` as cleanup | Never auto-clean in a shared checkout |
| `git worktree remove --force` on "branch not on origin" | Scope prune to your own `wf_<run>-*`; never force-remove a branch you didn't create |
| Resume a `Workflow` to recover a few failed worktree agents | Re-dispatch the failed ones fresh/sequentially (`agent-patterns-plugin:parallel-agent-dispatch` § Resuming a workflow, #1868) |
| Trust `git status` as "my changes" | Treat it as "everyone's changes" until proven otherwise |
| Block on the process scan alone | Treat it as a hint; the baseline + markers are authoritative |

## Limitations

- None of these signals handle concurrent writes to the **same file** — they only detect that a coworker exists, not that you are about to clobber its work.

The remaining per-signal caveats (marker adoption, sandboxed process scans, baseline ambiguity) are in `git-plugin:git-coworker-check` REFERENCE.md § Signal design.

## Related Rules

- `.claude/rules/handling-blocked-hooks.md` — how to respond when a PreToolUse coworker-check hook blocks a command
- `.claude/rules/agent-runtime.md` — worktree isolation as the preferred answer to concurrency
- `.claude/rules/sandbox-guidance.md` — `/proc` and `lsof` availability in the web sandbox
- `git-plugin:git-coworker-check` — the detection skill, its scripts, signal design, and recovery
- `agent-patterns-plugin:parallel-agent-dispatch` — `Workflow` resume (#1868) and worktree-cleanup incidents
