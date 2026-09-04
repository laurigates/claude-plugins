# Terraform Plugin

Terraform Cloud (TFC) automation for infrastructure management - list runs, check status, fetch logs, and analyze plan JSON output.

## Overview

This plugin provides comprehensive Terraform Cloud API automation for monitoring and analyzing infrastructure runs, plans, and applies. Work with TFC workspaces, retrieve logs, analyze plan changes, and track run status directly from Claude Code.

## Skills

| Skill | Description |
|-------|-------------|
| `tfc-run-logs` | Retrieve plan and apply logs from Terraform Cloud runs |
| `tfc-workspace-runs` | Convenience wrapper for listing runs in configured workspaces |
| `tfc-list-runs` | List and filter runs from Terraform Cloud workspaces |
| `tfc-run-status` | Quick status check for TFC runs with resource changes and actions |
| `tfc-plan-json` | Download and analyze structured Terraform plan JSON output |

## Hooks

`validate-terraform-apply.sh` is a PreToolUse hook on the Bash tool that gates
an unreviewed apply.

| Command | Verdict |
|---------|---------|
| `terraform apply` | Blocked — nothing was reviewed |
| `terraform apply -auto-approve` (any form, plan file or not) | Blocked |
| `terraform apply tfplan` | Allowed — applies exactly the saved plan |
| A quoted argument, heredoc body, or comment carrying the phrase | Allowed |
| `bash -c "terraform apply"`, `echo "$(terraform apply)"` | Blocked — that text is shell, not data |

The hook matches in **command position**: it drops heredoc bodies and trailing
comments, collapses quoted spans to a placeholder, splits the command into
statements, and fires only where the invoked program resolves to `terraform`. A
PR body or search query quoting `terraform apply` executes nothing and is not
gated (#2506). Two spans inside quotes are still parsed as shell, because the
shell runs them: a `$(…)`/backtick substitution, and the script argument of
`bash -c` / `eval`.

A plan file is a positional operand carrying no `=` and not consumed as a
preceding bare flag's value, so `-var foo=bar` and `-target aws_x.y` do not
count as one. Name it **literally**: a `$VAR` or command substitution cannot be
resolved here — it could expand to `-auto-approve` — so it is treated as an
unreviewed apply.

## Prerequisites

All skills require a Terraform Cloud API token:

```bash
export TFE_TOKEN="your-api-token"        # User or team token (not organization token)
export TFE_ADDRESS="app.terraform.io"    # Optional, defaults to app.terraform.io
```

## Common Use Cases

### Check Workspace Runs

List recent runs for a workspace:

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
/plugin install terraform-plugin@laurigates-claude-plugins
```

## License

MIT
