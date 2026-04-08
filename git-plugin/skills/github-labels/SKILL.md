---
created: 2025-12-16
modified: 2026-04-01
reviewed: 2026-04-01
name: github-labels
description: |
  Discover and apply labels to GitHub PRs and issues using the gh CLI. Use when
  you need to list available labels, add or remove labels on pull requests or issues,
  or create new labels for a repository. Trigger phrases: "label this PR", "add
  labels to issue", "what labels are available", "create a new label".
user-invocable: false
allowed-tools: Bash, Read, Grep, Glob
---

# GitHub Labels

Reference for discovering and applying labels to GitHub PRs and issues.

## When to Use This Skill

| Use this skill when... | Use something else when... |
|------------------------|---------------------------|
| Listing available labels in a repo | Creating or managing milestones |
| Adding or removing labels on PRs/issues | Managing GitHub Projects boards |
| Creating new labels with colors | Bulk-editing many issues at once |
| Inheriting labels from issue to PR | Setting PR reviewers or assignees |

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

## Agentic Optimizations

| Context | Command |
|---------|---------|
| List all labels (machine-readable) | `gh label list --json name,description,color --limit 50` |
| Get label names only | `gh label list --json name -q '.[].name'` |
| Add label to PR silently | `gh pr edit $PR --add-label "label"` |
| Check current issue labels | `gh issue view $ISSUE --json labels -q '.labels[].name'` |
| Inherit labels from issue to PR | `gh issue view $ISSUE --json labels -q '[.labels[].name] | join(",")' | xargs -I{} gh pr edit $PR --add-label {}` |
