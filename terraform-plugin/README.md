# Terraform Plugin

Terraform Cloud (TFC) automation for infrastructure management - list runs, check status, fetch logs, and analyze plan JSON output.

## Overview

This plugin provides comprehensive Terraform Cloud API automation for monitoring and analyzing infrastructure runs, plans, and applies. Work with TFC workspaces, retrieve logs, analyze plan changes, and track run status directly from Claude Code.

## Skills

| Skill | Description |
|-------|-------------|
| `tfc-run-logs` | Retrieve plan and apply logs from Terraform Cloud runs |
| `tfc-workspace-runs` | Convenience wrapper for listing runs in Forum Virium Helsinki workspaces |
| `tfc-list-runs` | List and filter runs from Terraform Cloud workspaces |
| `tfc-run-status` | Quick status check for TFC runs with resource changes and actions |
| `tfc-plan-json` | Download and analyze structured Terraform plan JSON output |

## Prerequisites

All skills require a Terraform Cloud API token:

```bash
export TFE_TOKEN="your-api-token"        # User or team token (not organization token)
export TFE_ADDRESS="app.terraform.io"    # Optional, defaults to app.terraform.io
```

## Common Use Cases

### Check Workspace Runs

List recent runs for a workspace (works with FVH workspaces):

```bash
# Using tfc-workspace-runs skill
# Supports: github, sentry, gcp, onelogin, twingate
```

### Get Run Logs

Retrieve plan and apply logs for debugging:

```bash
# Using tfc-run-logs skill
# Fetches both plan and apply logs for a run ID
```

### Analyze Plan Changes

Download and analyze structured plan JSON:

```bash
# Using tfc-plan-json skill
# Get detailed resource change information
```

### Monitor Run Status

Quick status check with resource counts:

```bash
# Using tfc-run-status skill
# Shows status, resource changes, and available actions
```

### Filter Runs

List runs by status, operation type, or date:

```bash
# Using tfc-list-runs skill
# Filter by: status, status group, operation, source, timeframe
```

## Installation

```bash
/plugin install terraform-plugin@lgates-claude-plugins
```

## License

MIT
