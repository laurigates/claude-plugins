---
created: 2025-12-16
modified: 2026-01-17
reviewed: 2025-12-16
description: "Execute a PRP with validation loop, TDD workflow, and quality gates"
allowed_tools: [Read, Write, Edit, Glob, Bash, Task, AskUserQuestion]
---

Execute a PRP (Product Requirement Prompt) with systematic implementation and validation.

**Usage**: `/blueprint:prp-execute [prp-name]`

**Prerequisites**:
- PRP exists in `docs/prps/[prp-name].md`
- Confidence score >= 7 (if lower, suggest `/blueprint:prp-create` refinement)

**Execution Phases**:

## Phase 1: Load Context

### 1.1 Read PRP
```bash
cat docs/prps/$PRP_NAME.md
```

### 1.2 Verify Confidence Score
- If score >= 9: Ready for autonomous execution
- If score 7-8: Proceed with some discovery expected
- If score < 7: **STOP** - Recommend refinement first

### 1.3 Read ai_docs References
Load all referenced ai_docs entries for context:
- `ai_docs/libraries/*.md`
- `ai_docs/project/patterns.md`

### 1.4 Plan Execution
Based on the Implementation Blueprint:
1. Create TodoWrite entries for each task
2. Order by dependencies
3. Identify validation checkpoints

## Phase 2: Run Initial Validation Gates

### 2.1 Pre-Implementation Validation
Run validation gates to establish baseline:

```bash
# Gate 1: Ensure linting passes before changes
[linting command from PRP]

# Gate 2: Ensure existing tests pass
[test command from PRP]
```

**Expected**: All gates pass (clean starting state)

**If gates fail**:
- Document existing issues
- Decide whether to fix first or proceed
- Update PRP notes if needed

## Phase 3: TDD Implementation

For each task in Implementation Blueprint:

### 3.1 Write Tests First (RED)

Following TDD Requirements from PRP:

```bash
# Create test file if needed
# Write test case as specified in PRP
```

Run tests:
```bash
[test command]
```

**Expected**: New test FAILS (proves test is meaningful)

### 3.2 Implement Minimal Code (GREEN)

Write minimum code to pass the test:
- Follow patterns from Codebase Intelligence
- Apply patterns from ai_docs
- Watch for Known Gotchas

Run tests:
```bash
[test command]
```

**Expected**: Test PASSES

### 3.3 Refactor (REFACTOR)

Improve code while keeping tests green:
- Extract common patterns
- Improve naming
- Add type hints
- Follow project conventions

Run tests:
```bash
[test command]
```

**Expected**: Tests STILL PASS

### 3.4 Run Validation Gates

After each significant change:

```bash
# Gate 1: Linting
[linting command]

# Gate 2: Type checking
[type check command]

# Gate 3: Unit tests
[test command]
```

**If any gate fails**:
1. Fix the issue
2. Re-run the gate
3. Continue only when passing

### 3.5 Update Progress
Mark task as complete in TodoWrite:
```
✅ Task N: [Description]
```

## Phase 4: Final Validation

### 4.1 Run All Validation Gates

Execute every gate from the PRP:

```bash
# Gate 1: Linting
[linting command]
# Expected: No errors

# Gate 2: Type Checking
[type check command]
# Expected: No errors

# Gate 3: Unit Tests
[unit test command]
# Expected: All pass

# Gate 4: Integration Tests (if applicable)
[integration test command]
# Expected: All pass

# Gate 5: Coverage Check
[coverage command]
# Expected: Meets threshold

# Gate 6: Security Scan (if applicable)
[security command]
# Expected: No high/critical issues
```

### 4.2 Verify Success Criteria

Check each success criterion from PRP:
- [ ] Criterion 1: [verified how]
- [ ] Criterion 2: [verified how]
- [ ] Criterion 3: [verified how]

### 4.3 Check Performance Baselines

If performance baselines defined:
```bash
# Run performance test
[performance command]
```

Compare results to baseline targets.

## Phase 4.5: Deferred Items Report

**Purpose**: Create an audit trail for any items not implemented during this execution.

### 4.5.1 Identify Deferred Items

Review the PRP's Implementation Blueprint and identify:
- **Deferred (Phase 2)** tasks that were not implemented
- **Nice-to-Have** tasks that were skipped
- Any **Required** tasks that couldn't be completed (blockers)

### 4.5.2 Document Deferred Items

Create a deferred items table:

```markdown
### Deferred Items Report

| Item | Category | Reason | Follow-up Action |
|------|----------|--------|------------------|
| [Task name] | Phase 2 | [Why deferred] | GitHub issue |
| [Task name] | Nice-to-Have | Time constraint | None |
| [Task name] | Required (Blocked) | [Blocker description] | GitHub issue |
```

### 4.5.3 Create GitHub Issues for Phase 2 Items

**Required**: All "Deferred (Phase 2)" and "Required (Blocked)" items MUST have GitHub issues created.

For each item requiring an issue:

```bash
gh issue create \
  --title "[PRP Follow-up] [Task name]" \
  --body "## Context
This task was deferred during PRP execution for: **[feature-name]**

**Original PRP**: \`docs/prps/[feature-name].md\`

## Task Description
[Description from PRP]

## Reason Deferred
[Reason from deferred items table]

## Acceptance Criteria
[Relevant criteria from original PRP]

## Labels
- \`deferred-from-prp\`
- \`[priority label if applicable]\`" \
  --label "deferred-from-prp"
```

### 4.5.4 Update PRP with Deferred Items

Add deferred items section to the PRP:

```markdown
## Deferred Items (Post-Execution)

| Item | GitHub Issue | Reason |
|------|--------------|--------|
| [Task] | #[issue-number] | [Reason] |
| [Task] | N/A (Nice-to-Have) | [Reason] |
```

### 4.5.5 Summary Output

Include in execution report:

```markdown
### Deferred Items Summary
- **Phase 2 items deferred**: N (GitHub issues: #X, #Y, #Z)
- **Nice-to-Have skipped**: N
- **Required items blocked**: N (GitHub issues: #A, #B)
```

**Important**: Do not proceed to Phase 5 until all Phase 2 and blocked items have GitHub issues created.

## Phase 5: Sync Feature Tracker

**Purpose**: Automatically keep the feature tracker in sync as features are implemented.

### 5.1 Check if Feature Tracking is Enabled

```bash
# Check if feature tracker exists
test -f docs/blueprint/feature-tracker.json && echo "enabled" || echo "disabled"
```

**If disabled**: Skip to Phase 6 (Report)

### 5.2 Identify Implemented Features

From the PRP's Implementation Blueprint, identify which feature requirement (FR) codes were addressed:
- Extract FR codes from task descriptions (e.g., "FR2.1", "FR2.1.1")
- Map completed tasks to their corresponding features
- Note any features that are now fully complete vs. partially implemented

### 5.3 Update Feature Tracker

For each identified FR code:

1. **Update status**:
   - `complete` if all acceptance criteria verified
   - `partial` if some criteria met but more work needed
   - `in_progress` if work started but not yet passing tests

2. **Update implementation metadata**:
   ```json
   {
     "implementation": {
       "files": ["list of modified/created files"],
       "tests": ["list of test files"],
       "commits": ["commit hash from this PRP execution"],
       "notes": "Brief implementation notes"
     }
   }
   ```

3. **Recalculate statistics**:
   - Update counts for complete/partial/in_progress/not_started
   - Recalculate completion percentage
   - Update phase status if applicable

### 5.4 Sync with Documentation

Update sync targets:

**work-overview.md:**
- Move completed features to "Completed" section
- Update "In Progress" section with partially completed features

**TODO.md:**
- Check boxes for completed features: `[ ]` → `[x]`
- Add notes for partial completion if needed

### 5.5 Feature Sync Summary

Include in execution report:

```markdown
### Feature Tracker Updated
- **Features updated**: {count}
- **Completion**: {complete}/{total} ({percentage}%)
- **Phase {N} status**: {status}

| FR Code | Description | Previous | New |
|---------|-------------|----------|-----|
| FR2.1 | [desc] | not_started | complete |
| FR2.1.1 | [desc] | partial | complete |
```

**Note**: If no FR codes are found in the PRP, skip the sync and note:
```
Feature tracker sync skipped: No FR codes found in this PRP.
Consider adding FR code references to Implementation Blueprint tasks.
```

---

## Phase 6: Report

### 6.1 Execution Summary

Generate completion report:

```markdown
## PRP Execution Complete: [Feature Name]

### Implementation Summary
- **Tasks completed**: X/Y
- **Tests added**: N
- **Files modified**: [list]

### Validation Results

| Gate | Command | Result |
|------|---------|--------|
| Linting | `[cmd]` | ✅ Pass |
| Type Check | `[cmd]` | ✅ Pass |
| Unit Tests | `[cmd]` | ✅ Pass (N tests) |
| Integration | `[cmd]` | ✅ Pass |
| Coverage | `[cmd]` | ✅ 85% (target: 80%) |

### Success Criteria

- [x] Criterion 1: Verified via [method]
- [x] Criterion 2: Verified via [method]
- [x] Criterion 3: Verified via [method]

### Deferred Items Summary
- **Phase 2 items deferred**: N (GitHub issues: #X, #Y, #Z)
- **Nice-to-Have skipped**: N
- **Required items blocked**: N (GitHub issues: #A, #B)

### Feature Tracker Status
- **Features updated**: N
- **Overall completion**: X/Y (Z%)
- **Changes**: FR2.1 (not_started → complete), FR2.1.1 (partial → complete)

### New Gotchas Discovered
[Document any new gotchas for future reference]

### Recommendations
- [Any follow-up work suggested]
- [Updates to ai_docs recommended]

### Ready for:
- [ ] Code review
- [ ] Merge to main branch
```

### 6.2 Update ai_docs

If new patterns or gotchas discovered:
- Update relevant ai_docs entries
- Create new entries if needed
- Document lessons learned

### 6.3 Mark PRP Complete

Move or annotate PRP as executed:
```markdown
## Status: EXECUTED
**Executed on**: [date]
**Commit**: [hash]
**Notes**: [any notes]
```

## Error Handling

### Validation Gate Failure
1. Identify the failing check
2. Analyze the error message
3. Fix the issue
4. Re-run the gate
5. Continue when passing

### Test Failure Loop
If stuck in RED phase (test keeps failing):
1. Review Known Gotchas in PRP
2. Check ai_docs for patterns
3. Search codebase for similar implementations
4. Ask user for clarification if blocked

### Low Confidence Areas
When encountering areas not covered by PRP:
1. Document the gap
2. Research as needed
3. Update PRP for future reference
4. Proceed with best judgment

### Blocked Progress
If unable to proceed:
1. Document the blocker
2. Create work-order for blocker resolution
3. Report to user with options

### 6.4 Prompt for next action (use AskUserQuestion):

```
question: "PRP execution complete. What would you like to do next?"
options:
  - label: "Commit changes (Recommended)"
    description: "Create a commit with conventional message for this feature"
  - label: "Create work-order for follow-up"
    description: "Package remaining work or enhancements"
  - label: "Update ai_docs"
    description: "Document new patterns or gotchas discovered"
  - label: "Continue to next PRP"
    description: "If there are more PRPs to execute"
  - label: "I'm done for now"
    description: "Exit - changes are saved locally"
```

**Based on selection:**
- "Commit changes" → Run `/git:commit` or guide through commit
- "Create work-order" → Run `/blueprint:work-order`
- "Update ai_docs" → Run `/blueprint:curate-docs` for relevant patterns
- "Continue to next PRP" → List available PRPs and run `/blueprint:prp-execute [next]`
- "I'm done" → Exit

**Tips**:
- Trust the PRP - it was researched for a reason
- Run validation gates frequently (not just at the end)
- Document any new gotchas discovered
- Update ai_docs with lessons learned
- Commit after each passing validation cycle
