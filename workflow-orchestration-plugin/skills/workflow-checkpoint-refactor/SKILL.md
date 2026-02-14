---
model: opus
name: workflow-checkpoint-refactor
description: |
  Multi-phase refactoring with persistent checkpoint files that survive context
  limits. Use when refactoring spans 10+ files, requires multiple phases, or
  risks hitting conversation context limits. Each phase reads/writes a plan file,
  enabling resume from any point. Supports "continue the refactor" across sessions.
args: "[--init|--continue|--status|--phase=N]"
allowed-tools: Bash(git status *), Bash(git diff *), Bash(git log *), Bash(git add *), Bash(git commit *), Bash(npm run *), Bash(npx *), Bash(uv run *), Bash(cargo *), Read, Write, Edit, Grep, Glob, Task, TodoWrite
argument-hint: --init to create plan, --continue to resume, --status to check progress
created: 2026-02-08
modified: 2026-02-14
reviewed: 2026-02-08
---

# /workflow:checkpoint-refactor

Multi-phase refactoring with persistent state that survives context limits and session boundaries.

## When to Use This Skill

| Use this skill when... | Use direct refactoring instead when... |
|------------------------|---------------------------------------|
| Refactoring spans 10+ files | Changing 1-5 files |
| Work will exceed context limits | Small, focused change |
| Need to resume across sessions | Single-session task |
| Multiple dependent phases | Independent file changes |
| Team coordination on large refactor | Solo quick fix |

## Context

- Repo root: !`git rev-parse --show-toplevel 2>/dev/null`
- Plan file exists: !`test -f REFACTOR_PLAN.md && echo "yes" || echo "no"`
- Git status: !`git status --porcelain 2>/dev/null`
- Recent commits: !`git log --oneline -5 2>/dev/null`

## Parameters

- **`--init`**: Create a new refactoring plan interactively
- **`--continue`**: Resume from the last completed phase
- **`--status`**: Show current plan progress
- **`--phase=N`**: Execute a specific phase

## Plan File Format

The plan file (`REFACTOR_PLAN.md`) serves as persistent state:

```markdown
# Refactor Plan: {description}

Created: {date}
Last updated: {date}
Base commit: {hash}

## Overview
{What is being refactored and why}

## Phase 1: {phase name}
- **Status**: done | in-progress | pending | needs-review
- **Files**: file1.ts, file2.ts, file3.ts
- **Description**: {what this phase does}
- **Acceptance criteria**: {how to verify success}
- **Result**: {summary of changes made, filled in after completion}

## Phase 2: {phase name}
- **Status**: pending
- **Files**: file4.ts, file5.ts
- **Description**: {what this phase does}
- **Acceptance criteria**: {how to verify success}
- **Result**: {empty until completed}

...
```

## Execution

### Mode: --init

Create a new refactoring plan.

1. **Analyze scope**: Read the files to be refactored, understand dependencies
2. **Define phases**: Break work into phases where each phase:
   - Touches a bounded set of files (ideally 3-7)
   - Has clear acceptance criteria (tests pass, types check)
   - Can be committed independently
   - Builds on previous phases
3. **Write plan file**: Create `REFACTOR_PLAN.md` at repo root
4. **Record base commit**: `git log --format='%H' -1`

**Phase ordering principles**:
- Shared utilities/types first (other phases depend on these)
- Leaf components last (depend on shared changes)
- Tests alongside their implementation phase
- Each phase should leave the codebase in a working state

### Mode: --continue

Resume from the last completed phase.

1. **Read plan file**: `REFACTOR_PLAN.md`
2. **Find next pending phase**: First phase with status `pending` or `needs-review`
3. **Verify prerequisites**: All prior phases are `done`
4. **Execute phase** (see Phase Execution below)
5. **Update plan file**: Mark phase as `done` with result summary
6. **Commit**: `git commit -m "refactor phase N: {description}"`

### Mode: --status

Show current progress.

```bash
# Parse plan file and display status table
```

| Phase | Description | Status | Files |
|-------|-------------|--------|-------|
| 1 | Extract shared types | done | 4 |
| 2 | Create utility module | done | 3 |
| 3 | Migrate component A | in-progress | 5 |
| 4 | Migrate component B | pending | 4 |
| 5 | Update tests | pending | 6 |

### Mode: --phase=N

Execute a specific phase.

### Phase Execution (shared logic)

For each phase:

1. **Read context from plan file** - Only the current phase's details
2. **Read only the files listed for this phase** - Minimize context usage
3. **Implement changes** - Edit files according to phase description
4. **Validate**:
   ```bash
   # TypeScript
   npx tsc --noEmit 2>&1 | head -30

   # Python
   uv run mypy . 2>&1 | head -30

   # Rust
   cargo check 2>&1 | head -30

   # Tests
   npm test 2>/dev/null || uv run pytest -x 2>/dev/null || cargo test 2>/dev/null
   ```
5. **If validation fails**:
   - Fix errors if straightforward
   - If complex, mark phase as `needs-review` in plan file with details
   - Commit partial work with `WIP:` prefix
6. **If validation passes**:
   - Update plan file: set status to `done`, write result summary
   - Commit: `git add -u && git commit -m "refactor phase N: {description}"`
7. **Check if more phases remain** - If yes, proceed to next phase or suggest `--continue`

### Sub-Agent Delegation

For large phases (7+ files), delegate to a Task sub-agent:

```
Agent prompt:
Read REFACTOR_PLAN.md and execute Phase {N}.

Files to modify: {file list}
Description: {phase description}
Acceptance criteria: {criteria}

After making changes:
1. Run validation: {typecheck/test command}
2. Update REFACTOR_PLAN.md Phase {N} status to "done" and add result summary
3. Stage changes: git add -u
4. Commit: git commit -m "refactor phase {N}: {description}"

If validation fails, set status to "needs-review" with error details.
```

## Recovery Patterns

| Situation | Action |
|-----------|--------|
| Context limit hit mid-phase | Start new session, run `--continue` |
| Phase marked needs-review | Read plan for details, fix issues, run `--phase=N` |
| Tests broken after a phase | Revert phase commit, investigate, re-execute |
| Plan needs adjustment | Edit REFACTOR_PLAN.md directly, update phases |
| Base branch moved | Rebase onto new base, re-validate completed phases |

## Agentic Optimizations

| Context | Command |
|---------|---------|
| Check plan exists | `test -f REFACTOR_PLAN.md && echo "exists"` |
| Quick typecheck | `npx tsc --noEmit --pretty 2>&1 \| head -20` |
| Quick test | `npm test -- --bail=1 2>&1 \| tail -20` |
| Phase commit | `git commit -m "refactor phase N: description"` |
| Verify working state | `npx tsc --noEmit && npm test -- --bail=1` |
| Show plan phases | `grep "^## Phase" REFACTOR_PLAN.md` |
| Show phase status | `grep -A1 "^## Phase" REFACTOR_PLAN.md \| grep Status` |

## Quick Reference

| Operation | Command |
|-----------|---------|
| Init new refactor | `/workflow:checkpoint-refactor --init` |
| Check progress | `/workflow:checkpoint-refactor --status` |
| Resume work | `/workflow:checkpoint-refactor --continue` |
| Run specific phase | `/workflow:checkpoint-refactor --phase=3` |
| Manual plan edit | Edit `REFACTOR_PLAN.md` directly |

## Related Skills

- [code-review-checklist](../../../code-quality-plugin/skills/code-review-checklist/SKILL.md) - Review refactored code
- [refactoring-patterns](../../../code-quality-plugin/skills/refactoring-patterns/SKILL.md) - Refactoring techniques
- [git-worktree-agent-workflow](../../../git-plugin/skills/git-worktree-agent-workflow/SKILL.md) - Parallel agent isolation
