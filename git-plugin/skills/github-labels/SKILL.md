---
created: 2025-12-16
modified: 2025-12-16
reviewed: 2025-12-16
---

# GitHub Labels

Reference for discovering and applying labels to GitHub PRs and issues.

## Discovering Available Labels

```bash
# List all labels with details
gh label list --json name,description,color --limit 50

# Search for specific labels
gh label list --search "bug"

# Output as simple list
gh label list --json name -q '.[].name'
```

## Adding Labels to PRs

```bash
# Single label
gh pr create --label "bug"

# Multiple labels (repeat flag)
gh pr create --label "bug" --label "priority:high"

# Comma-separated
gh pr create --label "bug,priority:high"

# Add to existing PR
gh pr edit 123 --add-label "ready-for-review"
```

## Adding Labels to Issues

```bash
# Create with labels
gh issue create --label "bug,needs-triage"

# Add to existing issue
gh issue edit 123 --add-label "in-progress"

# Remove label
gh issue edit 123 --remove-label "needs-triage"
```

## Common Label Categories

| Category | Examples |
|----------|----------|
| Type | `bug`, `feature`, `enhancement`, `documentation`, `chore` |
| Priority | `priority:critical`, `priority:high`, `priority:medium`, `priority:low` |
| Status | `needs-triage`, `in-progress`, `blocked`, `ready-for-review` |
| Area | `frontend`, `backend`, `infrastructure`, `testing`, `ci-cd` |

## Label Inheritance Pattern

When creating a PR from an issue:
1. Read issue labels via `gh issue view N --json labels`
2. Apply same labels to PR: `gh pr create --label "label1,label2"`

This maintains traceability and consistent categorization.
