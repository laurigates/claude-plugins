---
description: "Next task from the feature tracker and PRDs, then implement it. Use when resuming coding in a blueprint project, picking the next tracker task, or resuming a TDD cycle after a break."
args: "[--task <id>] [--skip-status]"
argument-hint: "--task to resume specific task, --skip-status to skip state analysis"
allowed-tools: Read, Bash(git status *), Bash(git log *), Bash(git branch *), Grep, Glob, Edit, Write, Skill
created: 2025-12-16
modified: 2026-10-12
reviewed: 2026-06-05
name: project-continue
---

# /project:continue

## When to Use This Skill

| Use this skill when... | Use project-discovery instead when... |
|---|---|
| Resuming work on a known project with PRDs and feature-tracker state | Entering an unfamiliar codebase needing orientation on tooling/structure |
| Reading tracker state and then implementing the next task in this repo | Use `session-plugin:session-spinup` instead for a read-only briefing of open tasks, PRs, and journal todos that edits nothing |
| Picking the next task off the feature tracker after a break | Use project-test-loop instead when the next step is iterating on failing tests |
| Asking "what's next" in a project with established blueprint state | Use project-init instead when no project structure exists yet |
| Resuming coding yourself — reading state, then implementing the next task in this session | Use `/blueprint:execute` (pick and run the next blueprint action: derive/sync/work-order) or `/blueprint:status` (report blueprint state only) when blueprint, not you, should choose or report the next blueprint action |

Continue project development by analyzing current state and resuming work.

**Note**: Configure project-specific test/build commands in `CLAUDE.md` or `.claude/rules/` for automatic detection.

**Steps**:

1. **Check current state**:
   ```bash
   # Check git status
   git status

   # Check recent commits
   git log -5 --oneline

   # Check current branch
   git branch --show-current
   ```

2. **Read project context** — branch on whether the repo uses blueprint:

   **Blueprint repo** (`docs/blueprint/` exists):
   - Invoke `/blueprint:status --report-only` via the Skill tool and read
     its report for phase, feature progress, and pending work-orders.
   - Do **not** open or parse blueprint's own state files yourself. Their
     format is owned by blueprint-plugin and migrates under
     `/blueprint:upgrade`; `/blueprint:status` always reads the current
     format, while a hand-parse silently reads a stale one (issue #2184).
   - For ready-to-start features in detail, also invoke
     `/blueprint:feature-tracker-status`.

   **No blueprint** (no `docs/blueprint/`): skip the blueprint calls
   entirely and derive the next task from what the repo does have:
   - PRDs in `docs/prds/`, if present
   - Issues or TODOs the user points at, and `CLAUDE.md` notes
   - Plain git state from Step 1 (uncommitted work, recent commits, branch)

   **Either way**:
   - **PRDs**: Read all files in `docs/prds/` when that directory exists
     * Understand project goals and requirements
     * Identify features and phases

3. **Analyze state and determine next task**:

   **If uncommitted changes exist**:
   - Review uncommitted files
   - Determine if work-in-progress should be continued
   - Ask user if they want to continue current work or start fresh

   **If on clean state**:
   - Compare the reported tracker progress (blueprint repos) against PRD requirements
   - Identify next logical task:
     * Next pending feature reported by `/blueprint:status`
     * Next requirement in PRD
     * Next pending work-order reported by `/blueprint:status`
     * Without blueprint: next PRD requirement, else the work-in-progress
       implied by git state
   - Consider dependencies (start with unblocked tasks first)

4. **Report status before starting**:
   ```
   📊 Project Status:

   Current Branch: [branch]
   Uncommitted Changes: [yes/no - list files if yes]

   Recent Work:
   - [Last 3 commits]

   PRDs Found:
   - [List PRD files with brief summary]

   Work Overview: Phase [N] - [Phase name]
   ✅ Completed: [N] tasks
   ⏳ In Progress: [Current task if any]
   ⏹️ Pending: [N] tasks

   Next Task: [Identified next task]
   Approach: [Brief plan]
   ```

5. **Begin work following TDD**:
   - Activate project-specific skills automatically:
     * Architecture patterns
     * Testing strategies
     * Implementation guides
     * Quality standards
   - Follow **RED → GREEN → REFACTOR** workflow:
     * Write failing test first
     * Minimal implementation to pass
     * Refactor while keeping tests green
   - Commit incrementally:
     * Use conventional commits
     * Commit after each RED → GREEN → REFACTOR cycle
     * Reference PRD or issue in commit message

6. **Update feature tracker as you go** (blueprint repos only):
   - Invoke `/blueprint:feature-tracker-sync` via the Skill tool after
     completing a task, rather than hand-editing blueprint state files
   - Without blueprint, record progress in commit messages and any task
     tracker the project already uses

**Important**:
- **Always start with tests** (TDD requirement)
- **Apply project skills** (architecture, testing, implementation, quality)
- **Commit incrementally** (after each successful cycle)
- **Update feature tracker** via `/blueprint:feature-tracker-sync` in blueprint repos (keep project state current)

**Handling Common Scenarios**:

**Scenario: Starting new feature**:
1. Create work-order first with `/blueprint:work-order`
2. Then continue with this command

**Scenario: Blocked by dependency**:
1. Report the blocker
2. Suggest working on a different task
3. Or: Suggest implementing the dependency first

**Scenario: Tests failing**:
1. Analyze failures
2. Fix failing tests (always complete RED step first)
3. Continue once tests pass

**Scenario: Unclear what to do next**:
1. Review PRDs for requirements
2. Ask user for clarification
3. Suggest creating work-orders for clarity

## Agent Teams (Optional)

For large codebases with multiple work fronts, spawn teammates for parallel progress:

| Teammate | Focus | Value |
|----------|-------|-------|
| Research teammate | Investigate codebase state, PRDs, the `/blueprint:status` report | Parallel context gathering |
| Implementation teammate | Begin work on next task from feature tracker | Start implementation immediately |

The research teammate gathers project state while the implementation teammate begins the most obvious next task. This is optional — single-session continuation works for most projects.
