---
name: git-coworker-check
description: "Detect coworker Claude agents in a shared checkout. Use when starting a session in a shared clone, before destructive git ops (stash, reset, checkout), or before bulk-edit / commit-loop workflows."
args: "[--check | --claim | --release]"
argument-hint: "[--claim | --release | --check (default)]"
allowed-tools: Bash(bash *), Bash(git status *), Bash(git stash *), Bash(git rev-parse *), Read, TodoWrite
created: 2026-04-21
modified: 2026-10-02
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

Signal design — what each signal survives and where it goes blind — is in
[REFERENCE.md](REFERENCE.md) § Signal design. The always-loaded response rules
are `.claude/rules/agent-coworker-detection.md`.

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

For a worked example of the "stop and inspect" branch (#1277), see [references/field-evidence.md](references/field-evidence.md).

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

Bulk-edit / commit-loop skills invoke this **before staging any files**. For the SlashCommand snippet other skills use, and where hook-based enforcement belongs, see [references/integration.md](references/integration.md).

## Agentic Optimizations

| Context | Command |
|---------|---------|
| Cheapest detection (no baseline) | `bash scripts/detect-coworkers.sh --project-dir "$(pwd)"` |
| Full detection with drift | Add `--baseline-status` + `--baseline-stash` from a `--claim` run |
| One-line verdict check | `... \| awk -F= '/^VERDICT=/ {print $2}'` |

## Recovery

When detection failed to prevent a collision, or the verdict is `bare_flip_suspected`, read [references/recovery.md](references/recovery.md) before any further git op: symptom triage, bare-flip / leaked `GIT_DIR` recovery (#1692), and commit-early guidance.

## Related Skills

- `/git:maintain` — invokes this before any stash/clean operation
- `/git:commit` — invokes this before staging when working in a shared checkout
- `git-commit-workflow` — invokes this as a precondition for bulk-edit / per-plugin commit loops
- `git-branch-pr-workflow` — recommends worktrees as the structural fix
- `/taskwarrior:task-claim` — sister signal; writes the `+ACTIVE` claim that this skill now reads
- `/taskwarrior:task-release` — drops the claim that contributes to `TW_CLAIM_COUNT`
