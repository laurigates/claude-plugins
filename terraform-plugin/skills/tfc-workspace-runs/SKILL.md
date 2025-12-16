---
name: tfc-workspace-runs
description: |
  Convenience wrapper for listing Terraform Cloud runs in Forum Virium Helsinki
  workspaces (github, sentry, gcp, onelogin, twingate). Requires TFE_TOKEN.
  Use when user mentions TFC runs, Terraform Cloud workspace, listing TFC runs,
  infrastructure run history, or checking Terraform Cloud status.
allowed-tools: Bash, Read
---

# Terraform Cloud Workspace Runs

Convenience wrapper for quick access to runs in Forum Virium Helsinki Terraform Cloud workspaces.

## Prerequisites

```bash
export TFE_TOKEN="your-api-token"        # User or team token
export TFE_ADDRESS="app.terraform.io"    # Optional
```

## Known Workspaces

| Shorthand | Full Workspace Name |
|-----------|---------------------|
| `github` | `infrastructure-github` |
| `sentry` | `infrastructure-sentry` |
| `gcp` | `infrastructure-gcp` |
| `onelogin` | `infrastructure-onelogin` |
| `twingate` | `infrastructure-twingate` |

## Core Commands

### Quick List Runs

```bash
#!/bin/bash
set -euo pipefail

TOKEN="${TFE_TOKEN:?TFE_TOKEN not set}"
BASE_URL="https://${TFE_ADDRESS:-app.terraform.io}/api/v2"
ORG="ForumViriumHelsinki"

# Map shorthand to full workspace name
case "${1:-}" in
  github)   WORKSPACE="infrastructure-github" ;;
  sentry)   WORKSPACE="infrastructure-sentry" ;;
  gcp)      WORKSPACE="infrastructure-gcp" ;;
  onelogin) WORKSPACE="infrastructure-onelogin" ;;
  twingate) WORKSPACE="infrastructure-twingate" ;;
  *)
    echo "Usage: $0 <workspace> [limit]"
    echo "Workspaces: github, sentry, gcp, onelogin, twingate"
    exit 1
    ;;
esac

LIMIT="${2:-10}"

# Get workspace ID
WS_ID=$(curl -sf --header "Authorization: Bearer $TOKEN" \
  "$BASE_URL/organizations/$ORG/workspaces/$WORKSPACE" | \
  jq -r '.data.id')

# List runs
echo "Recent runs for $WORKSPACE:"
echo ""

curl -sf --header "Authorization: Bearer $TOKEN" \
  "$BASE_URL/workspaces/$WS_ID/runs?page[size]=$LIMIT&include=plan" | \
  jq -r '
    ["RUN_ID", "STATUS", "+", "~", "-", "CREATED", "MESSAGE"],
    (.data[] |
      .relationships.plan.data.id as $pid |
      [
        .id,
        .attributes.status,
        ((.included[] | select(.id == $pid) | .attributes."resource-additions") // 0 | tostring),
        ((.included[] | select(.id == $pid) | .attributes."resource-changes") // 0 | tostring),
        ((.included[] | select(.id == $pid) | .attributes."resource-destructions") // 0 | tostring),
        .attributes."created-at"[0:16],
        (.attributes.message // "No message")[0:30]
      ]
    ) | @tsv' | column -t
```

### One-Liner Examples

```bash
# GCP workspace - recent runs
curl -sf -H "Authorization: Bearer $TFE_TOKEN" \
  "https://app.terraform.io/api/v2/organizations/ForumViriumHelsinki/workspaces/infrastructure-gcp" | \
  jq -r '.data.id' | \
  xargs -I{} curl -sf -H "Authorization: Bearer $TFE_TOKEN" \
    "https://app.terraform.io/api/v2/workspaces/{}/runs?page[size]=5" | \
  jq -r '.data[] | "\(.id) | \(.attributes.status) | \(.attributes."created-at"[0:16])"'

# GitHub workspace - failed runs only
curl -sf -H "Authorization: Bearer $TFE_TOKEN" \
  "https://app.terraform.io/api/v2/organizations/ForumViriumHelsinki/workspaces/infrastructure-github" | \
  jq -r '.data.id' | \
  xargs -I{} curl -sf -H "Authorization: Bearer $TFE_TOKEN" \
    "https://app.terraform.io/api/v2/workspaces/{}/runs?filter[status]=errored" | \
  jq -r '.data[] | "\(.id) | \(.attributes.status) | \(.attributes.message)"'
```

### Get Latest Run for Each Workspace

```bash
#!/bin/bash
set -euo pipefail

TOKEN="${TFE_TOKEN:?TFE_TOKEN not set}"
BASE_URL="https://${TFE_ADDRESS:-app.terraform.io}/api/v2"
ORG="ForumViriumHelsinki"

WORKSPACES="infrastructure-github infrastructure-sentry infrastructure-gcp infrastructure-onelogin infrastructure-twingate"

echo "Latest run for each workspace:"
echo ""

for WS in $WORKSPACES; do
  WS_ID=$(curl -sf --header "Authorization: Bearer $TOKEN" \
    "$BASE_URL/organizations/$ORG/workspaces/$WS" | jq -r '.data.id')

  LATEST=$(curl -sf --header "Authorization: Bearer $TOKEN" \
    "$BASE_URL/workspaces/$WS_ID/runs?page[size]=1" | \
    jq -r '.data[0] | "\(.id) | \(.attributes.status) | \(.attributes."created-at"[0:16])"')

  echo "$WS: $LATEST"
done
```

### Check for In-Progress Runs

```bash
#!/bin/bash
set -euo pipefail

TOKEN="${TFE_TOKEN:?TFE_TOKEN not set}"
BASE_URL="https://${TFE_ADDRESS:-app.terraform.io}/api/v2"
ORG="ForumViriumHelsinki"

WORKSPACES="infrastructure-github infrastructure-sentry infrastructure-gcp infrastructure-onelogin infrastructure-twingate"

echo "Checking for in-progress runs..."
echo ""

for WS in $WORKSPACES; do
  WS_ID=$(curl -sf --header "Authorization: Bearer $TOKEN" \
    "$BASE_URL/organizations/$ORG/workspaces/$WS" | jq -r '.data.id')

  IN_PROGRESS=$(curl -sf --header "Authorization: Bearer $TOKEN" \
    "$BASE_URL/workspaces/$WS_ID/runs?filter[status_group]=non_final&page[size]=5" | \
    jq -r '.data | length')

  if [ "$IN_PROGRESS" -gt 0 ]; then
    echo "$WS: $IN_PROGRESS run(s) in progress"
    curl -sf --header "Authorization: Bearer $TOKEN" \
      "$BASE_URL/workspaces/$WS_ID/runs?filter[status_group]=non_final" | \
      jq -r '.data[] | "  - \(.id): \(.attributes.status)"'
  fi
done
```

## Quick Reference

### Get Workspace ID

```bash
# Generic pattern
curl -sf -H "Authorization: Bearer $TFE_TOKEN" \
  "https://app.terraform.io/api/v2/organizations/ForumViriumHelsinki/workspaces/infrastructure-gcp" | \
  jq -r '.data.id'
```

### Workspace URLs (for reference)

- **GitHub**: https://app.terraform.io/app/ForumViriumHelsinki/workspaces/infrastructure-github
- **Sentry**: https://app.terraform.io/app/ForumViriumHelsinki/workspaces/infrastructure-sentry
- **GCP**: https://app.terraform.io/app/ForumViriumHelsinki/workspaces/infrastructure-gcp
- **OneLogin**: https://app.terraform.io/app/ForumViriumHelsinki/workspaces/infrastructure-onelogin
- **Twingate**: https://app.terraform.io/app/ForumViriumHelsinki/workspaces/infrastructure-twingate

## Integration with Other Skills

### Get logs for latest GCP run

```bash
# Get latest run ID
RUN_ID=$(curl -sf -H "Authorization: Bearer $TFE_TOKEN" \
  "https://app.terraform.io/api/v2/organizations/ForumViriumHelsinki/workspaces/infrastructure-gcp" | \
  jq -r '.data.id' | \
  xargs -I{} curl -sf -H "Authorization: Bearer $TFE_TOKEN" \
    "https://app.terraform.io/api/v2/workspaces/{}/runs?page[size]=1" | \
  jq -r '.data[0].id')

# Then use tfc-run-logs skill to get logs
echo "Use tfc-run-logs with run ID: $RUN_ID"
```

### Quick status check for all workspaces

```bash
# Combine with tfc-run-status for detailed info on specific runs
```

## Customization

To add more workspaces, update the case statement in the script:

```bash
case "${1:-}" in
  github)   WORKSPACE="infrastructure-github" ;;
  sentry)   WORKSPACE="infrastructure-sentry" ;;
  gcp)      WORKSPACE="infrastructure-gcp" ;;
  onelogin) WORKSPACE="infrastructure-onelogin" ;;
  twingate) WORKSPACE="infrastructure-twingate" ;;
  # Add more here:
  newworkspace) WORKSPACE="infrastructure-newworkspace" ;;
  *)
    echo "Usage: $0 <workspace>"
    exit 1
    ;;
esac
```

## See Also

- `tfc-list-runs`: Full-featured run listing with all filters
- `tfc-run-logs`: Get plan/apply logs for a specific run
- `tfc-run-status`: Quick status check for a run
- `tfc-plan-json`: Get structured plan JSON output
- `terraform-workspace-manager`: Workspace orchestration and run management
