# git-pr-feedback Reference

## Feedback Categories

| Category | Description | Priority |
|----------|-------------|----------|
| **Blocking** | "Request changes" reviews, critical bugs | Must address |
| **Substantive** | Code improvements, logic issues, missing tests | Should address |
| **Suggestions** | Style preferences, optional enhancements | Consider |
| **Questions** | Clarification requests | Respond inline |
| **Nitpicks** | Minor style/formatting | Low priority |
| **Resolved** | Already addressed or outdated | Skip |

## Decision Tree: Handling Different Feedback Types

```
Is it a "Request Changes" review?
├─ Yes → Must address all blocking concerns
└─ No → Is it an inline code comment?
         ├─ Yes → Does it suggest a specific fix?
         │        ├─ Yes → Implement the suggestion (or better alternative)
         │        └─ No → Analyze and determine best fix
         └─ No → Is it a general comment/question?
                  ├─ Yes → Note for PR reply
                  └─ No → Is it a resolved/outdated comment?
                           ├─ Yes → Skip
                           └─ No → Evaluate importance
```

## Commit Message Format

Group related fixes into logical commits:

```bash
git add <files-for-fix-1>
git commit -m "fix: address review feedback - <specific change>"
```

For multi-fix commits:

```
fix: address PR review feedback

- <Change 1 description>
- <Change 2 description>

Co-authored-by: <reviewer> (if they provided specific code)
```

Run pre-commit hooks if configured:

```bash
pre-commit run --all-files
git add -u  # Stage any formatter changes
```

## Summary Report Template

```markdown
## PR Feedback Summary

### Workflow Status
- CI Checks: [PASS/FAIL] - <details>
- Review Status: [Approved/Changes Requested/Pending]

### Feedback Addressed

| Category | Count | Status |
|----------|-------|--------|
| Blocking | N | ✅ Resolved |
| Substantive | N | ✅ Resolved |
| Suggestions | N | ✅/⏭️ Addressed/Deferred |
| Questions | N | 💬 Need response |

### Changes Made
- <File 1>: <description of change>
- <File 2>: <description of change>

### Next Steps
- [ ] Reply to clarification questions on PR
- [ ] Re-request review from <reviewer>
- [ ] Monitor CI for new run
```
