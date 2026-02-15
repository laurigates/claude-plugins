# Blueprint PRP Execute - Reference

Detailed reference material for the PRP execution skill, including validation gates, deferred items workflow, feature tracker sync details, report templates, and error handling patterns.

## Validation Gates

Validation gates are quality checks that run throughout PRP execution to maintain code quality and confirm success criteria.

### Gate Categories

**Pre-Implementation Gates** (Step 2 - establish baseline):
- Linting: `[cmd from PRP]` - Ensure starting state is clean
- Existing tests: `[cmd from PRP]` - Verify no regressions

**During Implementation** (Step 3 - frequent validation):
- After RED phase: Confirm test FAILS
- After GREEN phase: Confirm test PASSES
- After REFACTOR phase: Confirm all tests still PASS
- After significant changes: Run linting, type checking

**Final Validation Gates** (Step 4 - comprehensive check):
- Linting: No errors
- Type checking: No errors
- Unit tests: All pass (count and report)
- Integration tests: All pass (if applicable)
- Coverage check: Meets threshold from PRP
- Security scan: No high/critical issues (if applicable)
- Performance tests: Meets baselines (if defined)

### Gate Failure Handling

| Scenario | Action |
|----------|--------|
| Gate fails | Stop, analyze error, fix issue, re-run gate |
| Multiple gates fail | Fix them in order, re-run entire validation suite |
| Gate timeout | Investigate performance, fix issue, retry |
| Gate disabled/not found | Document, skip if optional, investigate if required |

## Deferred Items Workflow

Deferred items track work not completed during this execution.

### Item Categorization

**Phase 2 (Required Future)**:
- Parts of Implementation Blueprint marked as Phase 2
- Must have GitHub issue created
- Should be executed in follow-up PRP or work-order

**Nice-to-Have**:
- Enhancement features beyond core requirements
- Optional, no GitHub issue required
- Good candidates for future PRPs

**Blocked (Required but Cannot Complete)**:
- Tasks prevented by external blocker
- Must have GitHub issue documenting blocker
- Include "Blocked on:" section explaining dependency

### Creating GitHub Issues for Deferred Items

For each Phase 2 or Blocked item:

```bash
gh issue create \
  --title "[PRP Follow-up] [Task name]" \
  --body "## Context
This task was deferred during PRP execution for: **[feature-name]**

**Original PRP**: \`docs/prps/[feature-name].md\`

## Task Description
[Description from PRP]

## Reason Deferred
[Why it wasn't completed]

## Acceptance Criteria
[Relevant criteria from original PRP]

## Known Dependencies
[Any blockers or dependencies]

## Related Work
[Links to related issues or work-orders]" \
  --label "deferred-from-prp"
```

### Deferred Items Report Format

```markdown
### Deferred Items Report

| Item | Category | Reason | GitHub Issue |
|------|----------|--------|--------------|
| [Task name] | Phase 2 | Time constraint | #123 |
| [Task name] | Blocked | Waiting for API | #124 |
| [Task name] | Nice-to-Have | Enhancement | N/A |

**Summary**:
- **Phase 2 items deferred**: N (GitHub issues: #X, #Y, #Z)
- **Nice-to-Have skipped**: N (no issues needed)
- **Required items blocked**: N (GitHub issues: #A, #B)

**All Phase 2 and Blocked items have GitHub issues created.**
```

### Updating PRP with Deferred Items

Add section to PRP after execution:

```markdown
## Deferred Items (Post-Execution)

Deferred during execution on [date]:

| Item | GitHub Issue | Reason | Category |
|------|--------------|--------|----------|
| [Task] | #[issue-number] | [Reason] | Phase 2 |
| [Task] | N/A | [Reason] | Nice-to-Have |
```

## Feature Tracker Sync

### Feature Code Mapping

Extract feature codes (FR1, FR2.1, etc.) from PRP's Implementation Blueprint:

**Before mapping**:
```
Task 1: Write authentication middleware
Task 2: Add login endpoint
Task 3: Add logout endpoint
```

**After mapping**:
```
Task 1 (FR2.2.1): Write authentication middleware
Task 2 (FR2.1): Add login endpoint
Task 3 (FR2.1.1): Add logout endpoint
```

### Status Update Rules

| Criterion | Status | When |
|-----------|--------|------|
| All acceptance criteria verified | `complete` | All tests pass, all requirements met |
| Some criteria met, more work needed | `partial` | Some features working, needs follow-up |
| Work started but not passing tests | `in_progress` | Implementation begun but not finished |
| Not yet started | `not_started` | No work done (shouldn't update in tracker) |

### Feature Tracker Update JSON

```json
{
  "FR2.1": {
    "title": "Add login endpoint",
    "status": "complete",
    "implementation": {
      "files": ["src/auth/routes.ts", "src/auth/handlers.ts"],
      "tests": ["test/auth/login.test.ts"],
      "commits": ["abc1234def5678"],
      "notes": "Login endpoint with email/password auth, rate limiting enabled"
    }
  }
}
```

### Statistics Recalculation

After updating features, recalculate:

```json
{
  "summary": {
    "complete": 5,
    "partial": 2,
    "in_progress": 1,
    "not_started": 3,
    "total": 11,
    "completion_percentage": 45.5
  }
}
```

### Feature Sync Summary Output

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

## Execution Report Template

```markdown
## PRP Execution Complete: [Feature Name]

### Implementation Summary
- **Tasks completed**: X/Y
- **Tests added**: N
- **Files modified**: [list]

### Validation Results

| Gate | Command | Result |
|------|---------|--------|
| Linting | `[cmd]` | Pass |
| Type Check | `[cmd]` | Pass |
| Unit Tests | `[cmd]` | Pass (N tests) |
| Integration | `[cmd]` | Pass |
| Coverage | `[cmd]` | 85% (target: 80%) |

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
- **Changes**: FR2.1 (not_started -> complete), FR2.1.1 (partial -> complete)

### New Gotchas Discovered
[Document any new gotchas for future reference]

### Recommendations
- [Any follow-up work suggested]
- [Updates to ai_docs recommended]

### Ready for:
- [ ] Code review
- [ ] Merge to main branch
```

## Error Handling

### Validation Gate Failure
1. Identify which gate failed (output message indicates)
2. Analyze error details
3. Make minimal fix
4. Re-run ONLY that gate (don't repeat earlier steps)
5. Continue when gate passes

### Test Failure Loop (Stuck in RED)

When test fails repeatedly:

1. **Review Known Gotchas** from PRP - gotcha might explain failure
2. **Check ai_docs** - similar patterns might exist
3. **Search codebase** - find similar implementations
4. **Debug test** - add console.logs, run in isolation
5. **Ask for clarification** - if stuck, ask user

### Low Confidence Areas

When PRP doesn't cover something encountered:

1. Document the gap: "PRP doesn't specify pattern for X"
2. Research: Check ai_docs, codebase, project patterns
3. Make decision: Follow closest existing pattern
4. Document decision: Add to "New Gotchas Discovered" section
5. Update ai_docs: Document new pattern for future reference

### Blocked Progress

When unable to proceed:

1. **Identify blocker**: External dependency, missing tool, permission issue, etc.
2. **Document** the blocker clearly
3. **Categorize task** as Blocked in Deferred Items
4. **Create GitHub issue** documenting blocker
5. **Report to user** with options (continue with other tasks, create work-order for blocker, exit)

### Tips for Error Handling

- **Run gates frequently** - catch issues early, not at end
- **Trust the PRP** - it was researched for these patterns
- **Document gotchas** - new patterns are valuable for future PRPs
- **Commit after validation passes** - incremental commits are safer
- **Ask for help early** - don't spin on unsolvable problems

## Agent Teams (Optional)

For large multi-module PRPs, coordinate parallel execution:

### When to Use Agent Teams

Use agent teams when:
- Implementation Blueprint has 3+ clearly independent modules
- Modules have no dependencies on each other
- Each module has 3+ tasks
- Parallel execution will save significant time

### Team Structure

| Role | Responsibility | Tools |
|------|-----------------|-------|
| Module A Implementer | Execute Module A tasks from blueprint | Read, Write, Edit, Bash, Task |
| Module B Implementer | Execute Module B tasks from blueprint | Read, Write, Edit, Bash, Task |
| Validation Runner | Run gates continuously, report status | Bash (continuous validation) |
| Coordinator | Track progress, create GitHub issues, sync tracker | Read, Bash, Write |

### Shared Task List Pattern

Create shared task list in `docs/blueprint/feature-tracker.json`:

```json
{
  "execution_tasks": [
    {
      "id": "A.1",
      "module": "Authentication",
      "description": "Implement auth middleware",
      "status": "pending",
      "owner": "auth-implementer",
      "depends_on": []
    },
    {
      "id": "B.1",
      "module": "API",
      "description": "Create base API routes",
      "status": "pending",
      "owner": "api-implementer",
      "depends_on": ["A.1"]
    }
  ]
}
```

### Coordination Flow

1. **Coordinator**: Create task list, assign tasks to teammates
2. **Implementers**: Work on assigned module tasks in parallel
3. **Validation Runner**: Run gates after each implementer completes a task
4. **Coordinator**: Track progress, update feature tracker
5. **All**: When done, run final comprehensive validation together

### Single Session Fallback

If parallel execution is not suitable:
- Execute PRP in single session (recommended for most cases)
- Use agent teams only for large, well-structured PRPs
- Document decisions in execution report

## Success Criteria Verification

### Verification Methods

| Criterion Type | Verification Method |
|---|---|
| Feature works end-to-end | Integration test passes |
| API endpoint returns correct data | API test with sample data |
| Performance target met | Performance test results |
| No security issues | Security scan results |
| Code matches patterns | Code review checklist |
| User flow works | E2E test or manual verification |

### Documentation in Report

```markdown
### Success Criteria

- [x] Login endpoint accepts valid credentials
  - Verified via: Integration test in test/auth/login.test.ts

- [x] Rate limiting prevents brute force
  - Verified via: Load test shows rate limit at 5 attempts/minute

- [x] Errors don't leak sensitive info
  - Verified via: Security scan shows no exposed secrets

- [x] Performance meets baseline (<200ms response)
  - Verified via: Performance test shows 145ms average
```

## PRP Status After Execution

Mark PRP as executed:

```markdown
## Status: EXECUTED

**Executed on**: 2026-02-14T14:30:00Z
**Branch**: feature/auth-oauth2
**Commit**: abc1234def5678
**Execution URL**: [link to work-order or session notes]

### Execution Notes
- Completed all Phase 1 tasks, deferred Phase 2 cosmetics
- Discovered new gotcha: OAuth token refresh timing
- Updated ai_docs with token refresh pattern
- All success criteria verified
- GitHub issues created for deferred work
```

## Next Action Prompt

After completion, prompt with AskUserQuestion:

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
- "Commit changes" - Run `/git:commit` or guide through commit
- "Create work-order" - Run `/blueprint:work-order`
- "Update ai_docs" - Run `/blueprint:curate-docs` for relevant patterns
- "Continue to next PRP" - List available PRPs and run `/blueprint:prp-execute [next]`
- "I'm done" - Exit
