---
model: haiku
created: 2026-03-04
modified: 2026-03-04
reviewed: 2026-03-04
name: vault-files
description: |
  Obsidian vault file and folder operations via the official CLI.
  Covers reading, creating, appending, prepending, moving, deleting notes,
  listing files/folders, and daily note management.
  Use when user mentions Obsidian notes, vault files, daily notes,
  creating/editing notes, or managing vault content.
user-invocable: false
allowed-tools: Bash, Read, Grep, Glob
---

# Obsidian Vault File Operations

Comprehensive guidance for managing files, folders, and daily notes in Obsidian vaults using the official Obsidian CLI.

## Prerequisites

- Obsidian desktop v1.12.4+ installed
- CLI enabled in **Settings → General → Command line interface**
- Obsidian must be running (CLI communicates with the running instance)

## When to Use

Use this skill automatically when:
- User requests reading, creating, or editing Obsidian notes
- User mentions listing files or folders in a vault
- User wants to move or delete notes
- User needs daily note operations (open, read, append, prepend)
- User wants vault statistics or file counts

## Path Conventions

- All paths are **vault-relative** — use `folder/note.md`, not absolute filesystem paths
- `create` omits `.md` extension (added automatically)
- `move` requires full target path including `.md` extension
- Quote values containing spaces: `file="My Note Title"`
- Newlines: `\n`, tabs: `\t`

## Core File Operations

### List Files

```bash
# All files in vault
obsidian files

# Files in specific folder
obsidian files folder=Projects/Active

# Total note count
obsidian files total

# JSON output for parsing
obsidian files format=json
```

### List Folders

```bash
# All directories
obsidian folders

# Tree view
obsidian folders format=tree
```

### Read a Note

```bash
# Read by name (wikilink resolution)
obsidian read file="Note Name"

# Read by path
obsidian read path="Projects/spec.md"
```

### Create a Note

```bash
# Basic create (no .md needed)
obsidian create name="New Note"

# Create in folder with content
obsidian create name="Projects/Feature Spec" content="# Feature Spec\n\nDescription here."

# Create from template
obsidian create name="Meeting Notes" template="Templates/Meeting"

# Overwrite existing
obsidian create name="Draft" content="Fresh start" --overwrite
```

### Append / Prepend

```bash
# Add to end of note
obsidian append file="Daily Log" content="\n## New Section\nContent here."

# Add to beginning of note
obsidian prepend file="Inbox" content="- [ ] New task\n"
```

### Move a Note

```bash
# Move to folder (requires .md extension on target)
obsidian move file="Draft" to=Archive/Draft.md

# Rename in place
obsidian move file="Old Name" to="New Name.md"
```

### Delete a Note

```bash
# Move to Obsidian trash
obsidian delete file="Old Note"

# Permanent deletion (irreversible)
obsidian delete file="Old Note" --permanent
```

## Daily Notes

```bash
# Open today's daily note (creates if needed)
obsidian daily

# Read today's content
obsidian daily:read

# Append to today's note
obsidian daily:append content="- Met with team about roadmap"

# Prepend to today's note
obsidian daily:prepend content="## Morning Goals\n- Review PRs"

# Open specific date
obsidian daily:open date=2026-02-15
```

## Common Flags

| Flag | Description |
|------|-------------|
| `format=json` | JSON output for machine parsing |
| `format=csv` | CSV output |
| `format=tree` | Tree view for folders |
| `--silent` | Suppress output |
| `--overwrite` | Replace existing note on create |
| `--permanent` | Irreversible delete (skip trash) |
| `--copy` | Copy result to clipboard |
| `limit=N` | Limit result count |
| `sort=name\|date` | Sort order |

## Agentic Optimizations

| Context | Command |
|---------|---------|
| List files (structured) | `obsidian files format=json` |
| File count | `obsidian files total` |
| Folder listing (structured) | `obsidian folders format=json` |
| Read note content | `obsidian read file="Name"` |
| Quick capture to daily | `obsidian daily:append content="text"` |
| Batch file listing | `obsidian files folder=X format=json` |

## Related Skills

- **search-discovery** — Find notes by content, tags, or links
- **properties** — Manage YAML frontmatter on notes
- **tasks** — Task management across the vault
