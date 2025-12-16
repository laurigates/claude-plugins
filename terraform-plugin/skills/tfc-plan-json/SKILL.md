---
name: tfc-plan-json
description: Download and analyze structured Terraform plan JSON output from Terraform Cloud. Use when analyzing resource changes, diffing infrastructure, or programmatically inspecting plan details. Requires TFE_TOKEN environment variable.
allowed-tools: Bash, Read
---

# Terraform Cloud Plan JSON

Download and analyze structured plan JSON output from Terraform Cloud runs for detailed resource change analysis.

## Prerequisites

```bash
export TFE_TOKEN="your-api-token"        # User or team token with admin workspace access
export TFE_ADDRESS="app.terraform.io"    # Optional
```

## Core Commands

### Download Plan JSON

```bash
#!/bin/bash
set -euo pipefail

TOKEN="${TFE_TOKEN:?TFE_TOKEN not set}"
BASE_URL="https://${TFE_ADDRESS:-app.terraform.io}/api/v2"
RUN_ID="${1:?Usage: $0 <run-id> [output-file]}"
OUTPUT="${2:-plan.json}"

# Download with redirect following (API returns 307)
curl -Lsf --header "Authorization: Bearer $TOKEN" \
  -o "$OUTPUT" \
  "$BASE_URL/runs/$RUN_ID/plan/json-output"

echo "Plan JSON saved to: $OUTPUT"
```

### Download via Plan ID

```bash
TOKEN="${TFE_TOKEN:?TFE_TOKEN not set}"
PLAN_ID="plan-xyz789"

curl -Lsf --header "Authorization: Bearer $TOKEN" \
  -o plan.json \
  "https://app.terraform.io/api/v2/plans/$PLAN_ID/json-output"
```

## Analysis Commands

### Resource Change Summary

```bash
curl -Lsf --header "Authorization: Bearer $TFE_TOKEN" \
  "https://app.terraform.io/api/v2/runs/$RUN_ID/plan/json-output" | \
  jq '{
    terraform_version: .terraform_version,
    format_version: .format_version,
    summary: {
      create: [.resource_changes[] | select(.change.actions | contains(["create"]))] | length,
      update: [.resource_changes[] | select(.change.actions | contains(["update"]))] | length,
      delete: [.resource_changes[] | select(.change.actions | contains(["delete"]))] | length,
      replace: [.resource_changes[] | select(.change.actions | contains(["delete", "create"]))] | length,
      read: [.resource_changes[] | select(.change.actions | contains(["read"]))] | length,
      no_op: [.resource_changes[] | select(.change.actions == ["no-op"])] | length
    }
  }'
```

### List Resources Being Created

```bash
curl -Lsf --header "Authorization: Bearer $TFE_TOKEN" \
  "https://app.terraform.io/api/v2/runs/$RUN_ID/plan/json-output" | \
  jq -r '.resource_changes[] | select(.change.actions | contains(["create"])) | .address'
```

### List Resources Being Destroyed

```bash
curl -Lsf --header "Authorization: Bearer $TFE_TOKEN" \
  "https://app.terraform.io/api/v2/runs/$RUN_ID/plan/json-output" | \
  jq -r '.resource_changes[] | select(.change.actions | contains(["delete"])) | .address'
```

### List Resources Being Updated

```bash
curl -Lsf --header "Authorization: Bearer $TFE_TOKEN" \
  "https://app.terraform.io/api/v2/runs/$RUN_ID/plan/json-output" | \
  jq -r '.resource_changes[] | select(.change.actions | contains(["update"])) | .address'
```

### Resources Being Replaced

```bash
curl -Lsf --header "Authorization: Bearer $TFE_TOKEN" \
  "https://app.terraform.io/api/v2/runs/$RUN_ID/plan/json-output" | \
  jq -r '.resource_changes[] | select(.change.actions | contains(["delete", "create"])) |
    "\(.address) (replace due to: \(.action_reason // "unknown"))"'
```

### Detailed Resource Changes

```bash
curl -Lsf --header "Authorization: Bearer $TFE_TOKEN" \
  "https://app.terraform.io/api/v2/runs/$RUN_ID/plan/json-output" | \
  jq '.resource_changes[] | select(.change.actions != ["no-op"]) | {
    address: .address,
    actions: .change.actions,
    before: .change.before,
    after: .change.after
  }'
```

### Show What's Changing in a Specific Resource

```bash
RESOURCE="aws_instance.web"

curl -Lsf --header "Authorization: Bearer $TFE_TOKEN" \
  "https://app.terraform.io/api/v2/runs/$RUN_ID/plan/json-output" | \
  jq --arg addr "$RESOURCE" '
    .resource_changes[] | select(.address == $addr) | {
      address: .address,
      actions: .change.actions,
      before: .change.before,
      after: .change.after,
      after_unknown: .change.after_unknown
    }'
```

### Provider Versions Used

```bash
curl -Lsf --header "Authorization: Bearer $TFE_TOKEN" \
  "https://app.terraform.io/api/v2/runs/$RUN_ID/plan/json-output" | \
  jq '.configuration.provider_config | to_entries | map({
    provider: .key,
    version: .value.version_constraint
  })'
```

### Output Values

```bash
curl -Lsf --header "Authorization: Bearer $TFE_TOKEN" \
  "https://app.terraform.io/api/v2/runs/$RUN_ID/plan/json-output" | \
  jq '.output_changes | to_entries | map({
    name: .key,
    actions: .value.actions,
    sensitive: .value.after_sensitive
  })'
```

### Variables Used

```bash
curl -Lsf --header "Authorization: Bearer $TFE_TOKEN" \
  "https://app.terraform.io/api/v2/runs/$RUN_ID/plan/json-output" | \
  jq '.variables | keys'
```

## Complete Analysis Script

```bash
#!/bin/bash
set -euo pipefail

TOKEN="${TFE_TOKEN:?TFE_TOKEN not set}"
RUN_ID="${1:?Usage: $0 <run-id>}"

PLAN=$(curl -Lsf --header "Authorization: Bearer $TOKEN" \
  "https://app.terraform.io/api/v2/runs/$RUN_ID/plan/json-output")

echo "=== Plan Analysis for $RUN_ID ==="
echo ""
echo "Terraform Version: $(echo "$PLAN" | jq -r '.terraform_version')"
echo ""

echo "Resource Changes:"
echo "  Create:  $(echo "$PLAN" | jq '[.resource_changes[] | select(.change.actions | contains(["create"]))] | length')"
echo "  Update:  $(echo "$PLAN" | jq '[.resource_changes[] | select(.change.actions | contains(["update"]))] | length')"
echo "  Delete:  $(echo "$PLAN" | jq '[.resource_changes[] | select(.change.actions | contains(["delete"]))] | length')"
echo "  Replace: $(echo "$PLAN" | jq '[.resource_changes[] | select(.change.actions | contains(["delete", "create"]))] | length')"
echo ""

echo "Resources to Create:"
echo "$PLAN" | jq -r '.resource_changes[] | select(.change.actions | contains(["create"])) | "  - " + .address'

echo ""
echo "Resources to Destroy:"
echo "$PLAN" | jq -r '.resource_changes[] | select(.change.actions | contains(["delete"])) | "  - " + .address'

echo ""
echo "Resources to Update:"
echo "$PLAN" | jq -r '.resource_changes[] | select(.change.actions | contains(["update"])) | "  - " + .address'
```

## Plan JSON Structure

The plan JSON output follows Terraform's JSON plan format:

```json
{
  "format_version": "1.2",
  "terraform_version": "1.5.0",
  "planned_values": { ... },
  "resource_changes": [
    {
      "address": "aws_instance.web",
      "mode": "managed",
      "type": "aws_instance",
      "name": "web",
      "provider_name": "registry.terraform.io/hashicorp/aws",
      "change": {
        "actions": ["create"],
        "before": null,
        "after": { ... },
        "after_unknown": { ... },
        "before_sensitive": false,
        "after_sensitive": { ... }
      }
    }
  ],
  "output_changes": { ... },
  "configuration": { ... },
  "variables": { ... }
}
```

### Change Actions

- `["create"]` - Resource will be created
- `["delete"]` - Resource will be destroyed
- `["update"]` - Resource will be updated in-place
- `["delete", "create"]` - Resource will be replaced
- `["read"]` - Data source will be read
- `["no-op"]` - No changes

## Important Notes

- **Requires Terraform 0.12+** for JSON output support
- **Returns 204 No Content** if plan hasn't completed yet
- **Follow redirects** - API returns HTTP 307 to temporary download URL
- **Temporary URL** - Download URL is valid for ~1 minute
- **Admin access required** - Need admin permissions on the workspace

## Error Handling

### 204 No Content
Plan hasn't completed yet. Check run status first.

### 401 Unauthorized
Token lacks admin workspace access or is invalid.

### 404 Not Found
Run doesn't exist or you don't have permission.

## See Also

- `tfc-run-logs`: Get plan/apply logs (human-readable)
- `tfc-run-status`: Quick status check for a run
- `tfc-list-runs`: List recent runs in a workspace
