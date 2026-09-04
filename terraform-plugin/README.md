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
| `terraform apply -auto-approve`, including the quoted spellings and alongside a plan file | Blocked |
| `terraform apply -refresh=false`, `terraform apply 2>&1 \| tee log` | Blocked — no plan file anywhere in the command |
| `timeout 300 terraform apply`, `env -i terraform apply`, `for d in …; do terraform apply; done` | Blocked — the wrapper and the loop keyword do not hide the program |
| `terraform apply tfplan` | Allowed — applies exactly the saved plan |
| A quoted argument, heredoc body, or comment carrying the phrase | Allowed |
| `bash -c "terraform apply"`, `echo "$(terraform apply)"` | Blocked — that text is shell, not data |

The hook decides command position with **`ast-grep --lang bash`**
(tree-sitter-bash), the classifier `hooks-plugin/hooks/bash-antipatterns.sh`
adopted in #2008. Each `command` node of the Bash call is examined on its own,
so a heredoc body is never a command, a redirection's fd digit is never an
argument, a `do`/`then` keyword is never glued to the program name, and any
wrapper — `sudo`, `timeout`, `nice`, `stdbuf`, `xargs`, `uv run` — is just the
front of the same node. A PR body or search query quoting `terraform apply`
executes nothing and is not gated (#2506). The one thing tree-sitter cannot see
into is a shell invoker's script argument, so `bash -c "…"`, `sh -c '…'` and
`eval "…"` have their quoted arguments re-parsed as shell.

A program name assembled from an expansion — `A='terraform apply
-auto-approve'; $A` — carries no `terraform` token and is not caught. Neither
the pre-#2506 regex nor any later version caught it; the gate stops the
unreviewed apply written by habit, not one written to evade it.

**Where `ast-grep` is not installed the hook does not fire at all.** It fails
open, exactly as `bash-antipatterns.sh` does, because a PreToolUse hook that
hard-fails without its parser breaks every Bash call. Install `ast-grep` (`brew
install ast-grep`, `cargo install ast-grep`) for the gate to be in effect.

Quotes are removed rather than masked, because the shell removes them: `terraform
apply "-auto-approve"` really delivers `-auto-approve` to the process, and is
blocked. A plan file is a positional operand carrying no `=`, not consumed as a
preceding bare flag's value (so `-var foo=bar` and `-target aws_x.y` do not
count as one), and named **literally** — a `$VAR`, `$(…)` or backtick operand
cannot be resolved here, could expand to `-auto-approve`, and is treated as an
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
