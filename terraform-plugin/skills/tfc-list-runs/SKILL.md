---
name: tfc-list-runs
description: List Terraform Cloud runs for a workspace with filtering by status, operation type, and date. Use when reviewing run history, finding failed runs, or auditing infrastructure changes. Requires TFE_TOKEN environment variable.
allowed-tools: Bash, Read
---

# Terraform Cloud List Runs

List and filter runs from Terraform Cloud workspaces with formatted output.

## Prerequisites

```bash
export TFE_TOKEN="your-api-token"        # User or team token
export TFE_ADDRESS="app.terraform.io"    # Optional
```

## Core Commands

### List Recent Runs for a Workspace

```bash
#!/bin/bash
set -euo pipefail

TOKEN="${TFE_TOKEN:?TFE_TOKEN not set}"
BASE_URL="https://${TFE_ADDRESS:-app.terraform.io}/api/v2"
WORKSPACE_ID="${1:?Usage: $0 <workspace-id> [limit]}"
LIMIT="${2:-10}"

curl -sf --header "Authorization: Bearer $TOKEN" \
  "$BASE_URL/workspaces/$WORKSPACE_ID/runs?page[size]=$LIMIT" | \
  jq -r '.data[] | [
    .id,
    .attributes.status,
    .attributes."created-at"[0:19],
    (.attributes.message // "No message")[0:50]
  ] | @tsv' | \
  column -t -s $'\t'
```

### List Runs by Workspace Name (requires org)

```bash
TOKEN="${TFE_TOKEN:?TFE_TOKEN not set}"
BASE_URL="https://${TFE_ADDRESS:-app.terraform.io}/api/v2"
ORG="ForumViriumHelsinki"
WORKSPACE="infrastructure-gcp"

# Get workspace ID first
WS_ID=$(curl -sf --header "Authorization: Bearer $TOKEN" \
  "$BASE_URL/organizations/$ORG/workspaces/$WORKSPACE" | \
  jq -r '.data.id')

# List runs
curl -sf --header "Authorization: Bearer $TOKEN" \
  "$BASE_URL/workspaces/$WS_ID/runs?page[size]=10" | \
  jq -r '.data[] | "\(.id) | \(.attributes.status) | \(.attributes."created-at"[0:19]) | \(.attributes.message // "No message")"'
```

### Filter by Status

```bash
TOKEN="${TFE_TOKEN:?TFE_TOKEN not set}"
BASE_URL="https://${TFE_ADDRESS:-app.terraform.io}/api/v2"
WORKSPACE_ID="ws-abc123"

# Filter by single status
curl -sf --header "Authorization: Bearer $TOKEN" \
  "$BASE_URL/workspaces/$WORKSPACE_ID/runs?filter[status]=errored" | \
  jq -r '.data[] | "\(.id) | \(.attributes.status) | \(.attributes."created-at")"'

# Filter by multiple statuses
curl -sf --header "Authorization: Bearer $TOKEN" \
  "$BASE_URL/workspaces/$WORKSPACE_ID/runs?filter[status]=errored,canceled" | \
  jq -r '.data[] | "\(.id) | \(.attributes.status)"'
```

### Filter by Status Group

```bash
# Non-final runs (in progress)
curl -sf --header "Authorization: Bearer $TOKEN" \
  "$BASE_URL/workspaces/$WORKSPACE_ID/runs?filter[status_group]=non_final"

# Final runs (completed)
curl -sf --header "Authorization: Bearer $TOKEN" \
  "$BASE_URL/workspaces/$WORKSPACE_ID/runs?filter[status_group]=final"

# Discardable runs
curl -sf --header "Authorization: Bearer $TOKEN" \
  "$BASE_URL/workspaces/$WORKSPACE_ID/runs?filter[status_group]=discardable"
```

### Include Plan-Only Runs

By default, plan-only runs are excluded. To include them:

```bash
curl -sf --header "Authorization: Bearer $TOKEN" \
  "$BASE_URL/workspaces/$WORKSPACE_ID/runs?filter[operation]=plan_and_apply,plan_only,save_plan,refresh_only,destroy"
```

### List Runs Across Organization

```bash
TOKEN="${TFE_TOKEN:?TFE_TOKEN not set}"
BASE_URL="https://${TFE_ADDRESS:-app.terraform.io}/api/v2"
ORG="ForumViriumHelsinki"

# All runs in org (limited info, no total count)
curl -sf --header "Authorization: Bearer $TOKEN" \
  "$BASE_URL/organizations/$ORG/runs?page[size]=20" | \
  jq -r '.data[] | "\(.id) | \(.attributes.status)"'

# Filter by workspace names
curl -sf --header "Authorization: Bearer $TOKEN" \
  "$BASE_URL/organizations/$ORG/runs?filter[workspace_names]=infrastructure-gcp,infrastructure-github"
```

## Formatted Output Examples

### Table Format with Resource Changes

```bash
curl -sf --header "Authorization: Bearer $TOKEN" \
  "$BASE_URL/workspaces/$WORKSPACE_ID/runs?page[size]=10&include=plan" | \
  jq -r '
    ["RUN_ID", "STATUS", "ADD", "CHG", "DEL", "CREATED"],
    (.data[] | [
      .id,
      .attributes.status,
      (.relationships.plan.data.id as $pid |
        (.included[] | select(.id == $pid) | .attributes."resource-additions" // 0)),
      (.relationships.plan.data.id as $pid |
        (.included[] | select(.id == $pid) | .attributes."resource-changes" // 0)),
      (.relationships.plan.data.id as $pid |
        (.included[] | select(.id == $pid) | .attributes."resource-destructions" // 0)),
      .attributes."created-at"[0:19]
    ]) | @tsv' | column -t
```

### JSON Output for Further Processing

```bash
curl -sf --header "Authorization: Bearer $TOKEN" \
  "$BASE_URL/workspaces/$WORKSPACE_ID/runs?page[size]=5" | \
  jq '[.data[] | {
    id: .id,
    status: .attributes.status,
    created: .attributes."created-at",
    message: .attributes.message,
    has_changes: .attributes."has-changes",
    auto_apply: .attributes."auto-apply"
  }]'
```

## Available Filter Parameters

| Parameter | Description | Example Values |
|-----------|-------------|----------------|
| `filter[status]` | Run status | `applied`, `errored`, `planned`, `canceled` |
| `filter[status_group]` | Status group | `non_final`, `final`, `discardable` |
| `filter[operation]` | Operation type | `plan_and_apply`, `plan_only`, `destroy` |
| `filter[source]` | Run source | `tfe-api`, `tfe-ui`, `tfe-configuration-version` |
| `filter[timeframe]` | Time period | `2024`, `year`, `month` |
| `search[user]` | VCS username | Username string |
| `search[commit]` | Commit SHA | SHA string |
| `search[basic]` | Combined search | Search term |

## Run Statuses

**Final States:** `applied`, `planned_and_finished`, `discarded`, `errored`, `canceled`, `force_canceled`, `policy_soft_failed`

**Non-Final States:** `pending`, `planning`, `planned`, `cost_estimating`, `policy_checking`, `confirmed`, `applying`, and others

## Pagination

```bash
# Page 2 with 20 items per page
curl -sf --header "Authorization: Bearer $TOKEN" \
  "$BASE_URL/workspaces/$WORKSPACE_ID/runs?page[number]=2&page[size]=20"

# Check pagination info
curl -sf --header "Authorization: Bearer $TOKEN" \
  "$BASE_URL/workspaces/$WORKSPACE_ID/runs" | \
  jq '.meta.pagination'
```

## Rate Limiting

The `/runs` endpoint has a special rate limit of **30 requests/minute** (not 30/second like most endpoints). Plan accordingly when scripting.

## See Also

- `tfc-run-logs`: Get plan/apply logs for a run
- `tfc-run-status`: Quick status check for a run
- `tfc-workspace-runs`: Convenience wrapper for known workspaces
