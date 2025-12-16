---
name: tfc-run-status
description: Quick status check for Terraform Cloud runs showing status, resource changes, timestamps, and available actions. Use when monitoring run progress or checking if a run can be applied/canceled. Requires TFE_TOKEN environment variable.
allowed-tools: Bash, Read
---

# Terraform Cloud Run Status

Quick status check for Terraform Cloud runs with resource change counts, timestamps, and available actions.

## Prerequisites

```bash
export TFE_TOKEN="your-api-token"        # User or team token
export TFE_ADDRESS="app.terraform.io"    # Optional
```

## Core Commands

### Complete Status Check

```bash
#!/bin/bash
set -euo pipefail

TOKEN="${TFE_TOKEN:?TFE_TOKEN not set}"
BASE_URL="https://${TFE_ADDRESS:-app.terraform.io}/api/v2"
RUN_ID="${1:?Usage: $0 <run-id>}"

curl -sf --header "Authorization: Bearer $TOKEN" \
  "$BASE_URL/runs/$RUN_ID?include=plan,apply,cost-estimate" | \
  jq -r '
    "Run ID:      " + .data.id,
    "Status:      " + .data.attributes.status,
    "Message:     " + (.data.attributes.message // "No message"),
    "Created:     " + .data.attributes."created-at",
    "Has Changes: " + (.data.attributes."has-changes" | tostring),
    "Auto-Apply:  " + (.data.attributes."auto-apply" | tostring),
    "",
    "Resource Changes:",
    "  Additions:    " + ((.included[] | select(.type == "plans") | .attributes."resource-additions") // 0 | tostring),
    "  Changes:      " + ((.included[] | select(.type == "plans") | .attributes."resource-changes") // 0 | tostring),
    "  Destructions: " + ((.included[] | select(.type == "plans") | .attributes."resource-destructions") // 0 | tostring),
    "",
    "Actions:",
    "  Confirmable:     " + (.data.attributes.actions."is-confirmable" | tostring),
    "  Cancelable:      " + (.data.attributes.actions."is-cancelable" | tostring),
    "  Discardable:     " + (.data.attributes.actions."is-discardable" | tostring),
    "  Force-Cancelable:" + (.data.attributes.actions."is-force-cancelable" | tostring)
  '
```

### Quick Status Only

```bash
TOKEN="${TFE_TOKEN:?TFE_TOKEN not set}"
RUN_ID="run-abc123"

curl -sf --header "Authorization: Bearer $TFE_TOKEN" \
  "https://app.terraform.io/api/v2/runs/$RUN_ID" | \
  jq -r '.data.attributes.status'
```

### Status with Timestamps

```bash
curl -sf --header "Authorization: Bearer $TFE_TOKEN" \
  "https://app.terraform.io/api/v2/runs/$RUN_ID" | \
  jq -r '
    .data.attributes |
    "Status: " + .status,
    "Timestamps:",
    "  Created:   " + (."created-at" // "N/A"),
    "  Planned:   " + (."status-timestamps"."planned-at" // "N/A"),
    "  Applied:   " + (."status-timestamps"."applied-at" // "N/A")
  '
```

### Check Available Actions

```bash
curl -sf --header "Authorization: Bearer $TFE_TOKEN" \
  "https://app.terraform.io/api/v2/runs/$RUN_ID" | \
  jq '.data.attributes.actions'
```

### Check Permissions

```bash
curl -sf --header "Authorization: Bearer $TFE_TOKEN" \
  "https://app.terraform.io/api/v2/runs/$RUN_ID" | \
  jq '.data.attributes.permissions'
```

## Poll Until Complete

```bash
#!/bin/bash
set -euo pipefail

TOKEN="${TFE_TOKEN:?TFE_TOKEN not set}"
RUN_ID="${1:?Usage: $0 <run-id>}"

FINAL_STATES="applied planned_and_finished planned_and_saved discarded errored canceled force_canceled policy_soft_failed"

while true; do
  STATUS=$(curl -sf --header "Authorization: Bearer $TOKEN" \
    "https://app.terraform.io/api/v2/runs/$RUN_ID" | \
    jq -r '.data.attributes.status')

  echo "$(date +%H:%M:%S) Status: $STATUS"

  if echo "$FINAL_STATES" | grep -qw "$STATUS"; then
    echo "Run completed with status: $STATUS"
    exit 0
  fi

  sleep 5
done
```

## JSON Output

### Full Run Details

```bash
curl -sf --header "Authorization: Bearer $TFE_TOKEN" \
  "https://app.terraform.io/api/v2/runs/$RUN_ID" | \
  jq '{
    id: .data.id,
    status: .data.attributes.status,
    message: .data.attributes.message,
    created_at: .data.attributes."created-at",
    has_changes: .data.attributes."has-changes",
    auto_apply: .data.attributes."auto-apply",
    is_destroy: .data.attributes."is-destroy",
    actions: .data.attributes.actions,
    timestamps: .data.attributes."status-timestamps"
  }'
```

### With Cost Estimate

```bash
curl -sf --header "Authorization: Bearer $TFE_TOKEN" \
  "https://app.terraform.io/api/v2/runs/$RUN_ID?include=cost-estimate" | \
  jq '
    if .included then
      (.included[] | select(.type == "cost-estimates")) as $ce |
      {
        status: .data.attributes.status,
        cost: {
          prior_monthly: $ce.attributes."prior-monthly-cost",
          proposed_monthly: $ce.attributes."proposed-monthly-cost",
          delta_monthly: $ce.attributes."delta-monthly-cost"
        }
      }
    else
      {status: .data.attributes.status, cost: "N/A"}
    end
  '
```

## Run Status Reference

### Final States (run completed)
- `applied` - Successfully applied
- `planned_and_finished` - Plan-only or no changes
- `planned_and_saved` - Saved plan ready for confirmation
- `discarded` - User discarded the run
- `errored` - Run encountered an error
- `canceled` - User canceled the run
- `force_canceled` - Forcefully terminated
- `policy_soft_failed` - Sentinel soft fail (plan-only)

### Non-Final States (in progress)
- `pending` - Initial state
- `fetching` / `fetching_completed` - Retrieving config
- `queuing` / `plan_queued` - Waiting for capacity
- `planning` - Plan in progress
- `planned` - Plan complete, awaiting confirmation
- `cost_estimating` / `cost_estimated` - Cost estimation
- `policy_checking` / `policy_checked` - Sentinel evaluation
- `policy_override` - Soft fail, override available
- `confirmed` - User confirmed the plan
- `apply_queued` / `applying` - Apply in progress

## Action States

| Action | When Available |
|--------|----------------|
| `is-confirmable` | Status is `planned`, `cost_estimated`, `policy_checked`, or `policy_override` |
| `is-cancelable` | Status is `planning` or `applying` |
| `is-discardable` | Status is `pending`, `planned`, `cost_estimated`, `policy_checked`, or `policy_override` |
| `is-force-cancelable` | Cancel was called and cooloff period elapsed |

## See Also

- `tfc-run-logs`: Get plan/apply logs for a run
- `tfc-list-runs`: List recent runs in a workspace
- `tfc-plan-json`: Get structured plan JSON output
