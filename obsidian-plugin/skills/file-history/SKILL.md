---
created: 2026-04-30
modified: 2026-04-30
reviewed: 2026-04-30
name: file-history
description: |
  Inspect, diff, and restore previous versions of notes from Obsidian's local
  File Recovery store and from Obsidian Sync version history. Critical safety
  net for agentic edits — lets you compare versions, recover overwritten
  content, and audit changes. Use when the user mentions undo, restoring a
  previous version, file recovery, version history, or comparing what changed.
user-invocable: false
allowed-tools: Bash(obsidian *), Read, Grep, Glob
---

# Obsidian File History & Recovery

## When to Use This Skill

| Use this skill when... | Use the alternative instead when... |
|---|---|
| Recovering an overwritten or accidentally deleted note | Editing a current note — use `vault-files` |
| Diffing what changed between two versions of a note | Searching the current vault state — use `search-discovery` |
| Auditing the history of a single file before a destructive edit | Restoring a deleted file from disk-level backups — use OS tools |

Obsidian keeps two parallel version stores:

- **File Recovery** — local snapshots, configurable in Settings → File Recovery (`history:*`).
- **Sync history** — server-side versions, available with Obsidian Sync (`sync:history`, `sync:read`, `sync:restore`).

`diff` unifies both: by default it lists every available version (newest = 1)
across both stores. `filter=local|sync` narrows the source.

## Prerequisites

- Obsidian desktop v1.12.4+ with CLI enabled
- Obsidian must be running
- File Recovery enabled (Settings → File Recovery) for local history
- Active Obsidian Sync subscription for `sync:*` commands

## Diff Versions

```bash
# List all available versions of the active file
obsidian diff

# List versions of a specific file
obsidian diff file=Recipe

# Compare the latest version (1) to current state
obsidian diff file=Recipe from=1

# Compare two specific versions (newest = 1)
obsidian diff file=Recipe from=2 to=1

# Restrict to one source
obsidian diff file=Recipe filter=local
obsidian diff file=Recipe filter=sync
```

## Local File Recovery

```bash
# History entries for a file
obsidian history file=Recipe

# Every file that has local history
obsidian history:list

# Read a specific version (default: version=1, newest)
obsidian history:read file=Recipe version=3

# Open the File Recovery view in the GUI
obsidian history:open file=Recipe

# Restore a previous version (overwrites current)
obsidian history:restore file=Recipe version=3
```

## Sync Version History

```bash
# Sync versions for a file
obsidian sync:history file=Recipe
obsidian sync:history file=Recipe total

# Read a specific sync version
obsidian sync:read file=Recipe version=2

# Restore a sync version (overwrites current)
obsidian sync:restore file=Recipe version=2

# Open the sync history view in the GUI
obsidian sync:open file=Recipe

# Files deleted via sync (recoverable)
obsidian sync:deleted
```

## Common Patterns

### "Show me what an agent changed since I last reviewed"

```bash
# Diff the most recent saved version against the current state
obsidian diff file="Notes/Project" from=1
```

### "Restore yesterday's version after a bad edit"

```bash
# 1. List versions to identify the right one (newest = 1)
obsidian history file=Daily/2026-04-29
# 2. Read it to confirm
obsidian history:read file=Daily/2026-04-29 version=2
# 3. Restore
obsidian history:restore file=Daily/2026-04-29 version=2
```

### "Audit history for every file an agent touched in this session"

```bash
# Given a list of changed paths in $changed_files
while read -r path; do
  echo "=== $path ==="
  obsidian diff path="$path" filter=local
done <<< "$changed_files"
```

### Pre-flight before destructive edits

For agentic workflows that overwrite or delete notes, capture the version
number first so a restore is one command away:

```bash
# Snapshot the current version
obsidian history file="Notes/Important" | head -2
# … perform edit …
# If something breaks:
obsidian history:restore file="Notes/Important" version=2
```

## Agentic Optimizations

| Context | Command |
|---------|---------|
| List all versions of a file | `obsidian diff file=X` |
| Diff latest version vs current | `obsidian diff file=X from=1` |
| Diff two specific versions | `obsidian diff file=X from=2 to=1` |
| Local-only versions | `obsidian diff file=X filter=local` |
| Read a local version | `obsidian history:read file=X version=N` |
| Restore a local version | `obsidian history:restore file=X version=N` |
| Read a sync version | `obsidian sync:read file=X version=N` |
| Restore a sync version | `obsidian sync:restore file=X version=N` |
| Files deleted via sync | `obsidian sync:deleted` |

## Related Skills

- **vault-files** — Read or write the current state of a note
- **publish-sync** — Sync service status (pause/resume) and published-file workflows
- **vault-management** — Switch vaults before inspecting their history
