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

### State-lock pipe guard

`terraform-lock-pipe-guard.sh` is a second PreToolUse hook on the Bash tool
(#3849). `plan`, `apply`, `destroy`, `refresh`, `import` and the writing `state`
subcommands hold the remote backend lock for their whole run. A reader that
exits early closes the pipe, SIGPIPE kills tofu/terraform mid-run, and the lock
is left behind until a manual `force-unlock`. Until then it blocks every later
plan and CI apply.

| Command | Verdict |
|---------|---------|
| `tofu plan \| head -20`, `cd infra && terraform plan 2>&1 \| grep -m1 Plan`, `tofu plan \| sed 30q`, `tofu plan \| tee log \| grep -q x` | Blocked: the message prescribes `mkdir -p tmp && <stage> > tmp/tf-<subcommand>.txt 2>&1`, then Read |
| `just plan \| head`, `make plan \| head`, `mise run tf:plan \| head`, `terragrunt plan \| head` | Nudge (exit 0 with `additionalContext`): the hook cannot see the recipe body |
| `tofu plan > tmp/plan.txt 2>&1 && head tmp/plan.txt` | Allowed: tofu is not in the pipe |
| `tofu plan \| tail`, `tofu plan \| grep Plan`, `tofu plan \| tee log` | Allowed: the reader consumes all input |
| `tofu plan -lock=false \| head`, `tofu state list \| head`, `tofu validate \| head` | Allowed: no lock is taken |
| The phrase quoted in a PR body, `echo`, or heredoc | Allowed |

It decides command position with `ast-grep`, as the apply gate does, but reads
the pipe from the source text between two command nodes rather than from
tree-sitter's `pipeline` node. tree-sitter-bash parses `a && b | c` as
`(a && b) | c`, while bash runs `a && (b | c)`. Known gaps: a tofu stage that is
not the last command of a group before the pipe (`(tofu plan; echo) | head`),
process substitution, and readers other than `head`, `sed …q` and `grep -m/-q`.
Like the apply gate, it **fails open where `ast-grep` is not installed**.
Recovering an orphaned lock is covered in the `infrastructure-terraform` skill.

## Prerequisites

All skills require a Terraform Cloud API token:

```bash
# TFE_TOKEN: user or team token (not organization token).
# Keep it in a secret manager and inject it into the command that needs it
# instead of exporting it, e.g. `fnox exec --only TFE_TOKEN -- <cmd>` or `op run -- <cmd>`.
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
