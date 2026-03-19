# Issue Management Reference

Extended reference for the `git-issue-manage` skill.

## Custom Issue Fields API

### Overview

Custom issue fields are org-level configurations that add structured metadata to issues beyond labels and milestones. Fields have types (text, number, date, single_select, iteration) and can be set per-issue.

### Endpoints

| Method | Endpoint | Description |
|--------|----------|-------------|
| `GET` | `/orgs/{org}/issue-fields` | List all fields for org |
| `POST` | `/orgs/{org}/issue-fields` | Create a new field |
| `PATCH` | `/orgs/{org}/issue-fields/{field_id}` | Update field definition |
| `DELETE` | `/orgs/{org}/issue-fields/{field_id}` | Delete field |
| `GET` | `/repos/{owner}/{repo}/issues/{number}/issue-field-values` | Get values for issue |
| `POST` | `/repos/{owner}/{repo}/issues/{number}/issue-field-values` | Set value for issue |
| `DELETE` | `/repos/{owner}/{repo}/issues/{number}/issue-field-values/{field_id}` | Clear value |

### Field Types

| Type | Value Format | Example |
|------|-------------|---------|
| `text` | String | `"High priority migration"` |
| `number` | Numeric | `42` |
| `date` | ISO 8601 | `"2026-03-19"` |
| `single_select` | Option ID | `"option-id-abc123"` |
| `iteration` | Iteration ID | `"iteration-id-xyz789"` |

### Example: List Fields

```bash
gh api orgs/my-org/issue-fields --jq '.[] | {name, type, id}'
```

Response:
```json
[
  {"name": "Priority", "type": "single_select", "id": "field_001"},
  {"name": "Sprint", "type": "iteration", "id": "field_002"},
  {"name": "Story Points", "type": "number", "id": "field_003"},
  {"name": "Due Date", "type": "date", "id": "field_004"}
]
```

### Example: Set Field Value

```bash
# Set a number field
gh api repos/my-org/my-repo/issues/42/issue-field-values \
  -X POST -f field_id="field_003" -f value="8"

# Set a date field
gh api repos/my-org/my-repo/issues/42/issue-field-values \
  -X POST -f field_id="field_004" -f value="2026-04-01"

# Set a single_select field (use option ID)
gh api repos/my-org/my-repo/issues/42/issue-field-values \
  -X POST -f field_id="field_001" -f value="option-id-high"
```

### Example: Get All Field Values for an Issue

```bash
gh api repos/my-org/my-repo/issues/42/issue-field-values \
  --jq '.[] | "\(.field.name): \(.value)"'
```

Output:
```
Priority: High
Sprint: Sprint 12
Story Points: 8
Due Date: 2026-04-01
```

### Example: Clear a Field Value

```bash
gh api repos/my-org/my-repo/issues/42/issue-field-values/field_003 -X DELETE
```

## Transfer Prerequisites

| Requirement | Details |
|-------------|---------|
| Write access | Must have write access to both source and target repos |
| Same owner | Both repos should be owned by the same user or organization |
| Comments preserved | All comments transfer with the issue |
| Labels | Labels are preserved if they exist in target repo |
| Assignees | Assignees are preserved if they have access to target repo |
| Milestones | Milestones do NOT transfer (different per repo) |
| Projects | Project associations do NOT transfer |

## Lock Reasons Reference

| Reason | Displayed As | When to Use |
|--------|-------------|-------------|
| `off-topic` | "This conversation was marked as off-topic" | Discussion drifted |
| `too heated` | "This conversation was marked as too heated" | Unproductive argument |
| `resolved` | "This conversation was marked as resolved" | Issue fixed, no more input needed |
| `spam` | "This conversation was marked as spam" | Spam content |
| (none) | "This conversation has been locked" | General lock, no specific reason |

## gh issue develop Requirements

- **Minimum gh version:** 2.30.0
- **GitHub feature:** Issue branch linking (generally available)
- **Default branch name:** `{issue-number}-{title-slug}` (e.g., `42-fix-auth-timeout`)
- **Linked on GitHub:** Branch automatically appears in issue sidebar under "Development"
