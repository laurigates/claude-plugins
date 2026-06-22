---
name: git-coworker-check
description: "Detect coworker Claude agents in a shared checkout. Use when starting a session in a shared clone, before destructive git ops (stash, reset, checkout), or before bulk-edit / commit-loop workflows."
args: "[--check | --claim | --release]"
argument-hint: "[--claim | --release | --check (default)]"
allowed-tools: Bash(bash *), Bash(git status *), Bash(git stash *), Bash(git rev-parse *), Read, TodoWrite
created: 2026-04-21
modified: 2026-05-27
reviewed: 2026-05-19
---

# /git:coworker-check

Detect another agent working in the same repo clone and warn before
destructive operations that could destroy its uncommitted changes.

## When to Use This Skill

| Use this skill when... | Use a worktree instead when... |
|------------------------|-------------------------------|
| Session starts in a clone that may already be in use | You control the session and can create `git worktree add ../<task>` |
| About to run `git stash`, `git reset --hard`, `git checkout -- .` | You already know the working tree is yours alone |
| `git status` shows files you don't remember touching | Baseline + markers are already confirming you are alone |
| **Bulk-edit / commit-loop fan-out** about to start (per-plugin, per-package commits across many subdirectories) | Each iteration is already isolated in its own worktree |
| A collision already happened and you need to recover | See [REFERENCE.md](REFERENCE.md) — Recovery section |

See `.claude/rules/agent-coworker-detection.md` for the full rationale and
signal design.

## Bulk-edit / commit-loop precondition

Bulk-edit and commit-loop workflows (`git-commit-workflow` "Bulk-edit / per-plugin commit loops", per-package release-please loops, mass refactors) **MUST** run this check **up front, before staging any files** — not opportunistically partway through.

**Why front-loaded, not opportunistic.** A real divergence scenario from the field: two Claude sessions converged on the same trim-descriptions task. Session A used `general-purpose` subagents in the main checkout; session B used worktrees + per-plugin commits. Session B landed 11 clean per-plugin commits and stopped. Session A's first commit then grabbed **all 30 remaining plugins** in a single mega-commit, because session A had previously hit a `git commit -a` failure that left everything pre-staged, and session B's loop never noticed because it ran `/git:coworker-check` *during* its work rather than *before*. The end result was correct, but the commit history said `docs(configure-plugin): ...` for changes spanning 30 plugins.

The rule: **the orchestrator stops before fan-out if the playing field is contended.** Mid-loop checks let "the agent who happens to look first wins" — which is non-deterministic and produces misleading commit histories.

| Verdict from up-front check | What to do |
|-----------------------------|-----------|
| `clear` | Proceed with the bulk-edit / commit loop |
| `drift_detected` | Inspect the new files. If they are yours from earlier in the session, proceed with explicit paths. If unknown, stop and ask. |
| `worktree_leak_suspected` | A child worktree-isolated agent is leaking an untracked file into the parent (issue #1319). **Do not stage or stash the matching path.** Wait for the child's commit, then re-run the check before continuing. |
| `bare_flip_suspected` | The shared checkout was flipped to `core.bare=true`, or a leaked `GIT_DIR` / `GIT_WORK_TREE` env points away from the repo (issue #1692). **Stop and recover** before any further git ops — see the Recovery section. Do not start the loop. |
| `coworker_detected` | **Stop.** Recommend `git worktree add ../<repo>-<task>` for a fresh isolated checkout, or wait for the other session to finish. Do not start the loop. |

### Worked example: detection enables defensive restoration (#1277)

A second positive scenario from the field — the "stop and inspect" rather than "stop and abort" branch. A description-trimming refactor agent ran in a checkout that already had ~7 active `claude` processes touching the same files. The `coworker_detected` verdict fired off the **process-scan signal** alone (the `ps`-based fallback, well before any taskwarrior coordination existed for this batch). Per the verdict-to-action table above, the agent did not stash or reset; it scoped its pass to the remaining 17 files and inspected the coworker's already-landed edits before writing.

That inspection caught a real regression: in `git-fork-workflow`, the coworker had cut the description from 358 → 240 chars and dropped the sibling cross-reference `For creating upstream PRs, see git-upstream-pr`. The agent re-added the line on its own pass. Eight other skills had a stale `modified:` date for the same reason and were stamped forward. No work was lost; a silent cross-reference regression became an explicit recovery. `Evidence: issue #1277.`

## Context

- Repo root: !`git rev-parse --show-toplevel`
- Git dir: !`git rev-parse --git-dir`
- Current status: !`git status --porcelain=v2 --branch`
- Stash count: !`git stash list`
- Existing markers: !`find . -path './.git/.claude-session-*' -maxdepth 3`

## Parameters

Parse `$ARGUMENTS` for the mode flag. Default is `--check`.

| Flag | Action |
|------|--------|
| `--check` (default) | Run detection. Report verdict without writing anything. |
| `--claim` | Write a session marker and baseline snapshot for this session. Run at session start. |
| `--release` | Remove this session's marker and baseline files. Run on session exit. |

## Execution

Execute this detection workflow:

### Step 1: Resolve mode

Inspect `$ARGUMENTS`. If it contains `--claim`, go to Step 2a. If it contains `--release`, go to Step 2b. Otherwise (including empty), go to Step 3.

### Step 2a: Claim (write marker + baseline)

Run:

```
bash ${CLAUDE_SKILL_DIR}/scripts/claim-session.sh --project-dir "$(pwd)"
```

Report the three file paths printed. These are the marker and baseline files — do not commit or delete them. They live inside `.git/` and are not tracked.

Stop here.

### Step 2b: Release (remove marker + baseline)

Run:

```
bash ${CLAUDE_SKILL_DIR}/scripts/release-session.sh --project-dir "$(pwd)"
```

No output is expected. Stop here.

### Step 3: Detect coworkers

Look up the current session's baseline files (if `--claim` was run earlier this session). Then run detection. Pass `--self-agent claude-${CLAUDE_SESSION_ID:0:8}` so taskwarrior claims by this same session are reported as `OWN_CLAIM_*` rather than counted as coworkers:

```
bash ${CLAUDE_SKILL_DIR}/scripts/detect-coworkers.sh \
  --project-dir "$(pwd)" \
  --self-agent claude-${CLAUDE_SESSION_ID:0:8} \
  --baseline-status .git/.claude-baseline-$$.status \
  --baseline-stash .git/.claude-baseline-$$.stash
```

If no `--claim` was run, omit the `--baseline-*` flags — drift detection will return `unknown` but marker, process, and taskwarrior signals still work.

The taskwarrior signal is best-effort: when `task` or `jq` is not on `PATH`, the script reports `TW_SCAN_METHOD=unavailable` and the verdict falls back to the three git-side signals.

### Step 4: Interpret the verdict

Parse the `VERDICT=` line from the script's output:

| Verdict | Meaning | Action |
|---------|---------|--------|
| `clear` | No coworker detected | Proceed; still prefer explicit `git add <paths>` over `git add -A` |
| `drift_detected` | Files appeared since baseline but no other process/marker/claim found | Inspect `NEW_STATUS_LINES` — may be coworker or may be a forgotten earlier edit. Ask the user before stashing. |
| `worktree_leak_suspected` | Untracked file in parent matches a path held by a linked worktree (issue #1319) | **Do not stash or commit** the matching path. Wait for the child worktree's commit to reclaim it. Avoid committing on the parent branch until child agents are done. |
| `bare_flip_suspected` | `CORE_BARE=true` on a shared working checkout, or a `LEAKED_GIT_DIR` / `LEAKED_GIT_WORK_TREE` env points away from the repo (issue #1692) | **Stop and recover.** Flip `core.bare` back to false and/or unset the leaked env before any further git ops — see the Recovery section below. Recover any wiped untracked work from the reflog / agent worktree branches. |
| `coworker_detected` | Another agent/process/taskwarrior claim is active in this clone | **Do not stash, restore, or reset.** Report the `MARKER_PID` / `PROC_PID` / `TW_CLAIM_*` entries. Recommend the user switch to a worktree. |

The six signals are independent — any one of `MARKER_COUNT > 0`, `PROC_COUNT > 0`, or `TW_CLAIM_COUNT > 0` raises `coworker_detected`. A non-zero `WORKTREE_LEAK_COUNT` on its own raises `worktree_leak_suspected`, and a non-zero `BARE_FLIP_COUNT` raises `bare_flip_suspected` (ranked first, since a bare flip breaks git for every linked worktree). `OWN_CLAIM_*` lines are this session's own taskwarrior claims and do not contribute to the count.

### Step 5: Report findings

Print a short summary:

1. Verdict
2. Count of markers + processes + drift entries
3. If non-clear, the specific PIDs or changed files
4. Recommended next action (worktree, ask user, proceed with explicit paths)

## Post-actions

- On `drift_detected` or `coworker_detected`: do not run `git stash`, `git reset --hard`, `git checkout -- .`, or `git clean` in this session. Stage only explicit paths.
- Suggest the user run `git worktree add ../$(basename $(git rev-parse --show-toplevel))-<task>` for a clean isolated checkout.

## Integration

Other git-plugin skills should invoke this via SlashCommand before destructive operations or fan-out:

```markdown
Before staging (or before starting a per-plugin commit loop):
Use SlashCommand to invoke `/git:coworker-check`.
If the verdict is not `clear`, stop and ask the user how to proceed.
```

Bulk-edit / commit-loop skills (`git-commit-workflow`, per-plugin release-please loops, mass refactors) must invoke this **before staging any files** — see the "Bulk-edit / commit-loop precondition" section above for why an opportunistic mid-loop check is insufficient.

Hook-based enforcement (blocking `git stash` / `git reset --hard` when a coworker is detected) belongs in `hooks-plugin`, not here.

## Agentic Optimizations

| Context | Command |
|---------|---------|
| Cheapest detection (no baseline) | `bash scripts/detect-coworkers.sh --project-dir "$(pwd)"` |
| Full detection with drift | Add `--baseline-status` + `--baseline-stash` from a `--claim` run |
| One-line verdict check | `... \| awk -F= '/^VERDICT=/ {print $2}'` |

## Recovery

Detection prevents corruption. When prevention fails — a coworker
session moved HEAD between your steps, your commit landed on the
wrong branch, your branch accumulated commits you didn't make — see
[REFERENCE.md](REFERENCE.md) for procedural recovery.

Quick triage:

| Symptom | Action |
|---|---|
| Your commit is on a branch you didn't expect | REFERENCE.md § Scenario 1 (mixed-reset + `git branch -f` + cherry-pick) |
| `git switch` carried unfamiliar WIP into the new branch | REFERENCE.md § Scenario 2 (selective `git checkout HEAD -- <paths>`) |
| `git stash list` is shorter than you remember | REFERENCE.md § Scenario 3 (recover via `git fsck --unreachable`) |
| You force-pushed the polluted branch already | REFERENCE.md § Scenario 4 (only `--force-with-lease` mitigations) |
| Every `git status`/`commit` fails with "fatal: this operation must be run in a work tree" | Bare-flip recovery below (`core.bare false` + unset leaked env) |

**Always run `git reflog -20` first.** The reflog is the ground truth
for every HEAD move and ref update during the collision window —
recovery procedures all begin from a clear reflog read.

### Recovering from a bare flip / leaked GIT_DIR (issue #1692)

When detection returns `bare_flip_suspected`, the shared checkout was
flipped to `core.bare=true` (or a `GIT_DIR` / `GIT_WORK_TREE` env was
leaked) by a concurrent agent fleet. Recover before any further git ops:

1. **Flip `core.bare` back to false** so the working tree is usable again:

   ```
   git config core.bare false
   ```

   If even `git config` refuses, drive it explicitly with the recovery
   override the issue used (note `-c core.bare=false` plus an explicit
   `GIT_DIR`/`GIT_WORK_TREE`):

   ```
   GIT_DIR=.git GIT_WORK_TREE=. git -c core.bare=false status
   ```

2. **Unset any leaked env** reported as `LEAKED_GIT_DIR` /
   `LEAKED_GIT_WORK_TREE` so git stops targeting another tree:

   ```
   unset GIT_DIR GIT_WORK_TREE
   ```

3. **Recover wiped untracked work.** A concurrent branch switch / reset
   can silently delete *uncommitted, untracked* files. Untracked files
   are not in the reflog, so check first for any copy a sibling agent
   committed — `git fsck --unreachable` and the agent worktree branches
   are the best source:

   ```
   git reflog -20
   git fsck --unreachable
   git worktree list
   git branch -a
   ```

   A file an agent worktree committed survives on its branch even when
   the parent's untracked copy was wiped. If no committed copy exists,
   the work is unrecoverable — which is why committing early matters.

### Commit early to minimize untracked-file exposure

Untracked files are the only work a concurrent branch switch/reset can
destroy with no recovery path (committed work survives in the reflog;
untracked work does not). When many sibling worktrees are active in one
clone — high `LINKED_WORKTREE_COUNT`, or a `coworker_detected` /
`bare_flip_suspected` verdict — **commit or stash new files promptly**
rather than leaving them untracked, and prefer working in your own
`git worktree add ../<repo>-<task>` so a flip in the shared checkout
cannot reach your tree.

## Related Skills

- `/git:maintain` — invokes this before any stash/clean operation
- `/git:commit` — invokes this before staging when working in a shared checkout
- `git-commit-workflow` — invokes this as a precondition for bulk-edit / per-plugin commit loops
- `git-branch-pr-workflow` — recommends worktrees as the structural fix
- `/taskwarrior:task-claim` — sister signal; writes the `+ACTIVE` claim that this skill now reads
- `/taskwarrior:task-release` — drops the claim that contributes to `TW_CLAIM_COUNT`
