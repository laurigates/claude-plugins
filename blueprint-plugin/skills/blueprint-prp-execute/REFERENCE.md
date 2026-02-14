# Blueprint PRP Execute - Reference

Detailed reference material for the PRP execution skill, including deferred items workflow, feature tracker sync details, report templates, and error handling patterns.

## Deferred Items Workflow

### Identifying Deferred Items

Review the PRP's Implementation Blueprint and identify:
- **Deferred (Phase 2)** tasks that were not implemented
- **Nice-to-Have** tasks that were skipped
- Any **Required** tasks that couldn't be completed (blockers)

### Deferred Items Table Format

```markdown
### Deferred Items Report

| Item | Category | Reason | Follow-up Action |
|------|----------|--------|------------------|
| [Task name] | Phase 2 | [Why deferred] | GitHub issue |
| [Task name] | Nice-to-Have | Time constraint | None |
| [Task name] | Required (Blocked) | [Blocker description] | GitHub issue |
```

### Creating GitHub Issues for Deferred Items

All "Deferred (Phase 2)" and "Required (Blocked)" items MUST have GitHub issues created.

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

### Updating PRP with Deferred Items

Add this section to the PRP after execution:

```markdown
## Deferred Items (Post-Execution)

| Item | GitHub Issue | Reason |
|------|--------------|--------|
| [Task] | #[issue-number] | [Reason] |
| [Task] | N/A (Nice-to-Have) | [Reason] |
```

### Deferred Items Summary Output

Include in the execution report:

```markdown
### Deferred Items Summary
- **Phase 2 items deferred**: N (GitHub issues: #X, #Y, #Z)
- **Nice-to-Have skipped**: N
- **Required items blocked**: N (GitHub issues: #A, #B)
```

**Important**: Do not proceed to the feature tracker sync phase until all Phase 2 and blocked items have GitHub issues created.

## Feature Tracker Sync Details

### Check if Feature Tracking is Enabled

```bash
test -f docs/blueprint/feature-tracker.json && echo "enabled" || echo "disabled"
```

If disabled, skip to the report phase.

### Identify Implemented Features

From the PRP's Implementation Blueprint:
- Extract FR codes from task descriptions (e.g., "FR2.1", "FR2.1.1")
- Map completed tasks to their corresponding features
- Note any features that are now fully complete vs. partially implemented

### Update Feature Tracker

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

### Sync with Documentation

Update sync targets:

**TODO.md:**
- Check boxes for completed features: `[ ]` -> `[x]`
- Add notes for partial completion if needed

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

## Error Handling Patterns

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

## Agent Teams (Optional)

For large multi-module PRPs, spawn teammates per module with a shared task list:

| Teammate | Focus | Value |
|----------|-------|-------|
| Module A implementer | Implement module A tasks from blueprint | Parallel implementation |
| Module B implementer | Implement module B tasks from blueprint | Parallel implementation |
| Validation runner | Run gates continuously as teammates complete tasks | Continuous quality feedback |

Use this when the PRP's Implementation Blueprint has clearly independent modules. Each teammate works on its module while the shared task list tracks overall progress. This is optional - single-session execution works for smaller PRPs.
