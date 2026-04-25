---
created: 2026-03-04
modified: 2026-04-25
reviewed: 2026-04-25
name: publish-sync
description: |
  Obsidian Publish and Sync management via the official CLI.
  Covers listing published notes, adding/removing notes from Publish,
  and checking Obsidian Sync status.
  Use when user mentions Obsidian Publish, publishing notes,
  Obsidian Sync, or sync status.
user-invocable: false
allowed-tools: Bash, Read, Grep, Glob
---

# Obsidian Publish & Sync

## When to Use This Skill

| Use this skill when... | Use the alternative instead when... |
|---|---|
| Listing, adding, or removing notes on Obsidian Publish | Creating or moving the underlying notes themselves — use `vault-files` |
| Checking Obsidian Sync status for the active vault | Managing community plugins or themes — use `plugins-themes` |
| Auditing which notes are currently public vs. private | Discovering orphaned or unresolved-link notes — use `search-discovery` |

Manage Obsidian Publish and Obsidian Sync services using the official CLI.

## Prerequisites

- Obsidian desktop v1.12.4+ with CLI enabled
- Obsidian must be running
- Active Obsidian Publish and/or Sync subscription for respective commands

## When to Use

Use this skill automatically when:
- User wants to list, add, or remove notes from Obsidian Publish
- User needs to check Obsidian Sync status
- User asks about publishing workflow or sync state

## Obsidian Publish

### List Published Notes

```bash
# All currently published notes
obsidian publish:list

# JSON output
obsidian publish:list format=json
```

### Add to Publish

```bash
# Publish a note
obsidian publish:add file="Public Note"

# Publish by path
obsidian publish:add path="blog/post.md"
```

### Remove from Publish

```bash
# Unpublish a note
obsidian publish:remove file="Draft Post"
```

## Obsidian Sync

### Check Status

```bash
# Current sync state
obsidian sync:status
```

## Publishing Workflow

### Batch Publish

```bash
# Find all notes tagged for publish, then add them
obsidian search query="[tag:publish]" format=json
# Then publish each result
obsidian publish:add file="Note Name"
```

### Publish Audit

```bash
# Compare published notes with tagged notes
obsidian publish:list format=json
obsidian tag tagname=publish
```

## Agentic Optimizations

| Context | Command |
|---------|---------|
| List published (structured) | `obsidian publish:list format=json` |
| Publish a note | `obsidian publish:add file="X"` |
| Unpublish a note | `obsidian publish:remove file="X"` |
| Sync status | `obsidian sync:status` |

## Related Skills

- **vault-files** — Create and manage notes before publishing
- **properties** — Set publish-related properties on notes
- **search-discovery** — Find notes tagged for publishing
