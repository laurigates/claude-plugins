---
created: 2026-04-30
modified: 2026-04-30
reviewed: 2026-04-30
name: vault-management
description: |
  Inspect the active vault, enumerate known vaults, and target commands at a
  specific vault using the global `vault=` prefix. Use when the user asks
  about vault info (path, file count, size), works across multiple vaults,
  or wants to run a command against a non-active vault.
user-invocable: false
allowed-tools: Bash(obsidian *), Read, Grep, Glob
---

# Obsidian Vault Management

## When to Use This Skill

| Use this skill when... | Use the alternative instead when... |
|---|---|
| Listing every vault Obsidian knows about | Listing files inside the active vault — use `vault-files` |
| Targeting a non-active vault for one command | Switching the active vault permanently — `vault:open` (TUI only) |
| Reporting vault info (path, file count, size) for diagnostics | Reading a specific note — use `vault-files` |

The CLI defaults to the **active vault** (the one currently focused in the
Obsidian app), unless your terminal's working directory is itself inside a
vault folder — in which case that vault wins. The `vault=` prefix overrides
both, scoped to a single command invocation.

## Prerequisites

- Obsidian desktop v1.12.4+ with CLI enabled
- Obsidian must be running

## Vault Info

```bash
# Active vault overview
obsidian vault

# Specific fields only
obsidian vault info=name
obsidian vault info=path
obsidian vault info=files
obsidian vault info=folders
obsidian vault info=size
```

## Enumerate Known Vaults

```bash
# All known vaults (name only)
obsidian vaults

# Include vault paths (verbose)
obsidian vaults verbose

# Just the count
obsidian vaults total
```

## Target a Specific Vault

`vault=` is a **global prefix** — it must come before the command, not as
a normal parameter:

```bash
# Run against a specific vault by name
obsidian vault=Notes daily
obsidian vault="My Vault" search query="meeting"

# By vault ID (from `obsidian vaults verbose` or settings)
obsidian vault=abc123def files
```

In the TUI, `vault:open name=Notes` switches the active vault for the rest
of the session. Outside the TUI, prefer the `vault=` prefix per command.

## Working-Directory Default

If the terminal is `cd`-ed into a vault folder, that vault is the default —
no `vault=` needed:

```bash
cd ~/vaults/Work
obsidian search query="status::active"   # runs against ~/vaults/Work
```

This is convenient for shell scripts that live alongside a specific vault.

## Common Patterns

### "Diagnostic snapshot of every vault"

```bash
obsidian vaults verbose | while read -r line; do
  name=$(echo "$line" | awk '{print $1}')
  echo "=== $name ==="
  obsidian vault="$name" vault info=files
  obsidian vault="$name" vault info=size
done
```

### "Search across one vault while a different one is active"

```bash
obsidian vault=Personal search query="trip ideas" format=json
```

### "Confirm which vault a script will hit"

```bash
obsidian vault info=name
obsidian vault info=path
```

## Agentic Optimizations

| Context | Command |
|---------|---------|
| Active vault summary | `obsidian vault` |
| Active vault path only | `obsidian vault info=path` |
| Active vault file count | `obsidian vault info=files` |
| List vaults (verbose) | `obsidian vaults verbose` |
| Vault count | `obsidian vaults total` |
| Run command against a vault | `obsidian vault=NAME <command>` |

## Related Skills

- **vault-files** — File operations within the active or targeted vault
- **publish-sync** — Per-vault Obsidian Sync configuration and status
- **search-discovery** — Search inside a (possibly `vault=`-prefixed) vault
