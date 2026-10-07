# blueprint-work-order — Work-Order Template (Step 5)

```markdown
---
id: WO-NNN
created: {YYYY-MM-DD}
status: pending
implements:                    # Source PRP or PRD
  - PRP-NNN
relates-to:                    # Related documents
  - ADR-NNNN
github-issues:
  - N
---

# Work-Order NNN: [Task Name]

**ID**: WO-NNN
**GitHub Issue**: #N
**Status**: pending

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
