---
description: "Analyze project state and continue development where left off"
allowed_tools: [Read, Bash, Grep, Glob, Edit, Write]
---

Continue project development by analyzing current state and resuming work.

**Note**: This is a generic template. Run `/blueprint:generate-commands` to create a project-specific version.

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

2. **Read project context**:
   - **PRDs**: Read all files in `.claude/blueprints/prds/`
     * Understand project goals and requirements
     * Identify features and phases
   - **Work Overview**: Read `.claude/blueprints/work-overview.md`
     * Current phase and progress
     * Completed, in-progress, and pending tasks
   - **Work Orders**: Check `.claude/blueprints/work-orders/`
     * Recent work-orders (see what's been done)
     * Pending work-orders (see what's planned)

3. **Analyze state and determine next task**:

   **If uncommitted changes exist**:
   - Review uncommitted files
   - Determine if work-in-progress should be continued
   - Ask user if they want to continue current work or start fresh

   **If on clean state**:
   - Compare work-overview against PRD requirements
   - Identify next logical task:
     * Next item in work-overview "Pending" section
     * Next requirement in PRD
     * Next work-order to execute
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

6. **Update work-overview as you go**:
   - Mark tasks in-progress
   - Mark tasks completed
   - Update next steps

**Important**:
- **Always start with tests** (TDD requirement)
- **Apply project skills** (architecture, testing, implementation, quality)
- **Commit incrementally** (after each successful cycle)
- **Update work-overview** (keep project state current)

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
