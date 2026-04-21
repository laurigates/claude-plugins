---
name: git-coworker-check
description: |
  Detect whether another Claude agent is working in the same repo clone before
  running destructive git operations (stash, reset, checkout --). Use when
  starting a session in a non-worktree checkout, or before any "clean up the
  working tree" action that could wipe a coworker's in-flight changes.
argument-hint: [--claim | --release | --check (default)]
allowed-tools: Bash(bash *), Bash(git status *), Bash(git stash *), Bash(git rev-parse *), Read, TodoWrite
created: 2026-04-21
modified: 2026-04-21
reviewed: 2026-04-21
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

See `.claude/rules/agent-coworker-detection.md` for the full rationale and
signal design.

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

Look up the current session's baseline files (if `--claim` was run earlier this session). Then run detection:

```
bash ${CLAUDE_SKILL_DIR}/scripts/detect-coworkers.sh \
  --project-dir "$(pwd)" \
  --baseline-status .git/.claude-baseline-$$.status \
  --baseline-stash .git/.claude-baseline-$$.stash
```

If no `--claim` was run, omit the `--baseline-*` flags — drift detection will return `unknown` but marker and process signals still work.

### Step 4: Interpret the verdict

Parse the `VERDICT=` line from the script's output:

| Verdict | Meaning | Action |
|---------|---------|--------|
| `clear` | No coworker detected | Proceed; still prefer explicit `git add <paths>` over `git add -A` |
| `drift_detected` | Files appeared since baseline but no other process/marker found | Inspect `NEW_STATUS_LINES` — may be coworker or may be a forgotten earlier edit. Ask the user before stashing. |
| `coworker_detected` | Another agent/process is active in this clone | **Do not stash, restore, or reset.** Report the `MARKER_PID` / `PROC_PID` entries. Recommend the user switch to a worktree. |

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

Other git-plugin skills should invoke this via SlashCommand before destructive operations:

```markdown
Before staging: Use SlashCommand to invoke `/git:coworker-check`.
If the verdict is not `clear`, stop and ask the user how to proceed.
```

Hook-based enforcement (blocking `git stash` / `git reset --hard` when a coworker is detected) belongs in `hooks-plugin`, not here.

## Agentic Optimizations

| Context | Command |
|---------|---------|
| Cheapest detection (no baseline) | `bash scripts/detect-coworkers.sh --project-dir "$(pwd)"` |
| Full detection with drift | Add `--baseline-status` + `--baseline-stash` from a `--claim` run |
| One-line verdict check | `... \| awk -F= '/^VERDICT=/ {print $2}'` |

## Related Skills

- `/git:maintain` — invokes this before any stash/clean operation
- `/git:commit` — invokes this before staging when working in a shared checkout
- `git-branch-pr-workflow` — recommends worktrees as the structural fix
