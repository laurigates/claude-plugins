---
description: "Execute a PRP with validation loop, TDD workflow, and quality gates"
allowed_tools: [Read, Write, Edit, Glob, Bash, Task]
---

Execute a PRP (Product Requirement Prompt) with systematic implementation and validation.

**Usage**: `/prp:execute [prp-name]`

**Prerequisites**:
- PRP exists in `.claude/blueprints/prps/[prp-name].md`
- Confidence score >= 7 (if lower, suggest `/prp:create` refinement)

**Execution Phases**:

## Phase 1: Load Context

### 1.1 Read PRP
```bash
cat .claude/blueprints/prps/$PRP_NAME.md
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

## Phase 5: Report

### 5.1 Execution Summary

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

### New Gotchas Discovered
[Document any new gotchas for future reference]

### Recommendations
- [Any follow-up work suggested]
- [Updates to ai_docs recommended]

### Ready for:
- [ ] Code review
- [ ] Merge to main branch
```

### 5.2 Update ai_docs

If new patterns or gotchas discovered:
- Update relevant ai_docs entries
- Create new entries if needed
- Document lessons learned

### 5.3 Mark PRP Complete

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

**Tips**:
- Trust the PRP - it was researched for a reason
- Run validation gates frequently (not just at the end)
- Document any new gotchas discovered
- Update ai_docs with lessons learned
- Commit after each passing validation cycle
