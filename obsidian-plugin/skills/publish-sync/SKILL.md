---
created: 2026-03-04
modified: 2026-04-30
reviewed: 2026-04-30
name: publish-sync
description: |
  Obsidian Publish and Obsidian Sync management via the official CLI —
  publish site info, list/add/remove published notes, publish change set,
  open published page, sync pause/resume, sync status and usage, and
  recovery of sync-deleted files. Use when the user mentions Obsidian
  Publish, publishing notes, Obsidian Sync, sync status, or recovering
  sync-deleted files.
user-invocable: false
allowed-tools: Bash(obsidian *), Read, Grep, Glob
---

# Obsidian Publish & Sync

## When to Use This Skill

| Use this skill when... | Use the alternative instead when... |
|---|---|
| Listing, adding, removing, or auditing the change set on Obsidian Publish | Creating or moving the underlying notes themselves — use `vault-files` |
| Pausing/resuming Obsidian Sync or checking sync status & usage | Restoring a previous sync version of a file — use `file-history` |
| Recovering a file that sync deleted | Recovering a file from local File Recovery — use `file-history` |
| Auditing which notes are currently public vs private | Discovering orphaned or unresolved-link notes — use `search-discovery` |

Manage Obsidian Publish and Obsidian Sync services from the CLI.
**Sync version history** (per-file diff and restore) lives in `file-history`.

## Prerequisites

- Obsidian desktop v1.12.4+ with CLI enabled
- Obsidian must be running
- Active Obsidian Publish and/or Sync subscription for the respective commands

## Obsidian Publish

### Site Info

```bash
# Slug, URL, status of the connected Publish site
obsidian publish:site
```

### List & Compare

```bash
# All currently published files
obsidian publish:list
obsidian publish:list total

# What would change on next publish (new / changed / deleted)
obsidian publish:status
obsidian publish:status new
obsidian publish:status changed
obsidian publish:status deleted
obsidian publish:status total
```

### Publish & Unpublish

```bash
# Publish the active file
obsidian publish:add

# Publish a specific file
obsidian publish:add file="Public Note"
obsidian publish:add path="blog/post.md"

# Publish *all* changed files in one shot
obsidian publish:add changed

# Unpublish
obsidian publish:remove file="Draft Post"

# Open the file's published page in the browser
obsidian publish:open file="Public Note"
```

## Obsidian Sync

### Status & Pause/Resume

```bash
# Sync state, last sync time, usage
obsidian sync:status

# Pause / resume sync
obsidian sync off
obsidian sync on
```

### Files Deleted via Sync

```bash
# Files removed via sync (recoverable)
obsidian sync:deleted
obsidian sync:deleted total
```

To restore one of those files, use `file-history`:
`obsidian sync:restore file=X version=N`.

### Per-file Sync Versions

For listing, reading, or restoring a specific sync version of a file, use
the **`file-history`** skill (`sync:history`, `sync:read`, `sync:restore`,
`sync:open`).

## Common Patterns

### "Publish every note tagged #publish"

```bash
# Find candidates
obsidian search query="tag:#publish" format=json

# Or rely on the change set after the user tags them
obsidian publish:status new
obsidian publish:add changed
```

### "Pre-publish dry run"

```bash
obsidian publish:status            # all changes
obsidian publish:status new        # adds only
obsidian publish:status deleted    # removes only
```

### "Snapshot the public surface"

```bash
obsidian publish:list > published-$(date +%F).txt
obsidian publish:site
```

### "Recover a synced file the agent deleted"

```bash
obsidian sync:deleted
# Identify the file, then restore via file-history:
obsidian sync:restore file="Notes/Important" version=1
```

## Agentic Optimizations

| Context | Command |
|---------|---------|
| Site info | `obsidian publish:site` |
| List published | `obsidian publish:list` |
| What's changed since last publish | `obsidian publish:status` |
| New files only | `obsidian publish:status new` |
| Publish all changes | `obsidian publish:add changed` |
| Publish one file | `obsidian publish:add file=X` |
| Unpublish | `obsidian publish:remove file=X` |
| Sync status | `obsidian sync:status` |
| Pause sync | `obsidian sync off` |
| Resume sync | `obsidian sync on` |
| Sync-deleted files | `obsidian sync:deleted` |

## Related Skills

- **vault-files** — Create or modify notes before publishing
- **properties** — Set publish-related frontmatter on notes
- **search-discovery** — Find notes tagged for publishing
- **file-history** — Per-file sync history (`sync:history`, `sync:read`, `sync:restore`)
