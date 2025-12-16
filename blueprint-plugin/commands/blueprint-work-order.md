---
description: "Create work-order with minimal context for isolated subagent execution"
allowed_tools: [Read, Write, Glob, Bash]
---

Generate a work-order document for isolated subagent execution.

**Prerequisites**:
- Blueprint Development initialized (`.claude/blueprints/` exists)
- At least one PRD exists
- `work-overview.md` exists

**Steps**:

1. **Analyze current state**:
   - Read `work-overview.md` to understand current phase
   - Run `git status` to check uncommitted work
   - Run `git log -5 --oneline` to see recent work
   - Find existing work-orders (count them for numbering)

2. **Read relevant PRDs**:
   - Read PRD files to understand requirements
   - Identify next logical work unit based on:
     * Work-overview progress
     * PRD phase/section ordering
     * Git history (what's been done)

3. **Determine next work unit**:
   - Should be:
     * **Specific**: Single feature/component/fix
     * **Isolated**: Minimal dependencies
     * **Testable**: Clear success criteria
     * **Focused**: 1-4 hours of work

   Examples of good work units:
   - "Implement JWT token generation methods"
   - "Add input validation to registration endpoint"
   - "Create database migration for users table"

   Examples of bad work units (too broad):
   - "Implement authentication" (too large)
   - "Fix bugs" (not specific)

4. **Determine minimal context**:
   - **Files to modify/create** (only relevant ones):
     * Implementation file(s)
     * Test file(s)
     * Related files for reference

   - **PRD sections** (only relevant sections):
     * Don't include entire PRD
     * Only specific requirements for this task

   - **Existing code** (only relevant excerpts):
     * Don't include full files
     * Only code that needs integration

   - **Dependencies**:
     * External libraries needed
     * Environment variables required

5. **Generate work-order**:
   - Number: Find highest existing work-order number and add 1 (001, 002, etc.)
   - Name: `NNN-brief-task-description.md`
   - Use template from `.claude/docs/blueprint-development/work-order-template.md`

   **Work-order structure**:
   ```markdown
   # Work-Order NNN: [Task Name]

   ## Objective
   [One sentence describing what needs to be accomplished]

   ## Context

   ### Required Files
   [Only files needed - list with purpose]

   ### PRD Reference
   [Link to specific PRD section, not entire PRD]

   ### Technical Decisions
   [Only decisions relevant to this specific task]

   ### Existing Code
   [Only relevant code excerpts needed for integration]

   ## TDD Requirements

   ### Test 1: [Test Description]
   [Exact test to write, with code template]
   **Expected Outcome**: Test should fail

   ### Test 2: [Test Description]
   [Exact test to write]
   **Expected Outcome**: Test should fail

   [More tests as needed]

   ## Implementation Steps

   1. **Write Test 1** - Run: `[test_command]` - Expected: **FAIL**
   2. **Implement Test 1** - Run: `[test_command]` - Expected: **PASS**
   3. **Refactor (if needed)** - Run: `[test_command]` - Expected: **STILL PASS**
   [Repeat for all tests]

   ## Success Criteria
   - [ ] All specified tests written and passing
   - [ ] [Specific functional requirement met]
   - [ ] [Performance/security baseline met]
   - [ ] No regressions (existing tests pass)

   ## Notes
   [Additional context, gotchas, considerations]

   ## Related Work-Orders
   - **Depends on**: Work-Order NNN (if applicable)
   - **Blocks**: Work-Order NNN (if applicable)
   ```

6. **Save work-order**:
   - Save to `.claude/blueprints/work-orders/NNN-task-name.md`
   - Ensure zero-padded numbering (001, 002, 010, 100)

7. **Update `work-overview.md`**:
   - Add new work-order to "Pending" section
   - Keep overview current

8. **Report**:
   ```
   ✅ Work-order created!

   Work-Order: 003-jwt-token-generation.md
   Location: .claude/blueprints/work-orders/003-jwt-token-generation.md

   Objective: [Brief objective]

   Context included:
   - Files: [List files]
   - Tests: [Number of tests specified]
   - Dependencies: [Key dependencies]

   Ready for execution:
   - Can be executed by subagent with isolated context
   - TDD workflow enforced (tests specified first)
   - Clear success criteria defined

   To execute:
   1. Hand work-order to appropriate subagent
   2. Or: Work on it directly with `/project:continue`

   Updated work-overview.md with new pending task.
   ```

**Important**:
- **Minimal context**: Only what's needed, not full files/PRDs
- **Specific tests**: Exact test cases, not vague descriptions
- **TDD enforced**: Tests specified before implementation
- **Clear criteria**: Unambiguous success checkboxes
- **Isolated**: Task should be doable with only provided context

**Error Handling**:
- If no PRDs → Guide to write PRDs first
- If work-overview empty → Ask for current phase/status
- If task unclear → Ask user what to work on next
