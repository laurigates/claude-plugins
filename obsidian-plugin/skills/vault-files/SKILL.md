---
created: 2026-03-04
modified: 2026-04-30
reviewed: 2026-04-30
name: vault-files
description: |
  Obsidian vault file and folder operations via the official CLI — reading,
  creating, appending, prepending, moving, renaming, deleting notes, file
  info and word counts, listing files/folders, daily notes, random and
  unique notes, and the web viewer. Use when the user mentions Obsidian
  notes, vault files, daily notes, creating/editing/renaming notes, or
  managing vault content.
user-invocable: false
allowed-tools: Bash(obsidian *), Read, Grep, Glob
---

# Obsidian Vault File Operations

## When to Use This Skill

| Use this skill when... | Use the alternative instead when... |
|---|---|
| Reading, creating, appending, moving, renaming, or deleting notes through the running CLI | Doing offline bulk edits across many `.md` files — use `vault-frontmatter` or `vault-templates` |
| Opening or creating today's daily note | Curating MOC hub notes that organise existing content — use `vault-mocs` |
| Managing folder layout while Obsidian is running | Renaming a note and rewriting all links to it — use `vault-wikilinks` |
| Recovering a previous version after a bad edit | — use `file-history` |
| Querying notes structured by a Base view | — use `bases` |

Comprehensive guidance for managing files, folders, and daily notes in Obsidian vaults using the official Obsidian CLI.

## Prerequisites

- Obsidian desktop v1.12.4+ installed
- CLI enabled in **Settings → General → Command line interface**
- Obsidian must be running (CLI communicates with the running instance)

## Path & Flag Conventions

- All paths are **vault-relative** — use `folder/note.md`, not absolute filesystem paths
- `file=<name>` resolves like a wikilink (no extension needed); `path=<full/path.md>` is exact
- Most commands default to the **active file** when neither `file=` nor `path=` is supplied
- `create` omits `.md` from `name=` (added automatically); `move` requires `.md` in `to=`
- Quote values containing spaces: `file="My Note Title"`
- Newlines: `\n`, tabs: `\t`
- **Flags are bare words** — `overwrite`, `open`, `newtab`, `permanent`, `inline`, `total`. The single exception is `--copy` (a universal output flag).
- **Multi-vault**: prefix `vault=<name>` before the command — see `vault-management`

## Core File Operations

### List Files & Folders

```bash
# All files in vault
obsidian files

# Files in specific folder
obsidian files folder=Projects/Active

# Filter by extension
obsidian files ext=canvas

# Total note count
obsidian files total

# All folders, or a tree view
obsidian folders
obsidian folders format=tree
```

### File Info

```bash
# Info on the active file (path/name/extension/size/created/modified)
obsidian file

# Info on a specific file
obsidian file file=Recipe
obsidian file path="Notes/Recipe.md"

# Folder info
obsidian folder path="Projects"
obsidian folder path="Projects" info=files
obsidian folder path="Projects" info=size

# Word and character counts
obsidian wordcount file=Recipe
obsidian wordcount file=Recipe words
obsidian wordcount file=Recipe characters
```

### Read a Note

```bash
# Read by name (wikilink resolution)
obsidian read file="Note Name"

# Read by exact path
obsidian read path="Projects/spec.md"

# Read the active file (no args)
obsidian read

# Copy result to clipboard
obsidian read file="Note Name" --copy
```

### Create a Note

```bash
# Basic create (no .md needed)
obsidian create name="New Note"

# Create in folder with content
obsidian create name="Projects/Feature Spec" content="# Feature Spec\n\nDescription here."

# Create from a template (see also: templates skill)
obsidian create name="Meeting Notes" template="Meeting"

# Overwrite existing, then open it
obsidian create name="Draft" content="Fresh start" overwrite open
```

### Append / Prepend

```bash
# Add to end of note
obsidian append file="Daily Log" content="\n## New Section\nContent here."

# Append without an extra newline
obsidian append file="Daily Log" content="more text" inline

# Add after frontmatter (prepend skips YAML)
obsidian prepend file="Inbox" content="- [ ] New task\n"
```

### Open a Note

```bash
obsidian open file="Recipe"
obsidian open path="Notes/Recipe.md" newtab
```

### Move / Rename

```bash
# Move to a folder (requires .md extension on target)
obsidian move file="Draft" to=Archive/Draft.md

# Move + rename in one shot
obsidian move file="Old Name" to="Archive/New Name.md"

# Rename in place — preserves extension automatically
obsidian rename file="Old Name" name="New Name"
```

`move` and `rename` automatically update internal links if **Settings →
Files & Links → Automatically update internal links** is enabled.

### Delete

```bash
# Move to system / Obsidian trash
obsidian delete file="Old Note"

# Permanent deletion (skips trash, irreversible)
obsidian delete file="Old Note" permanent
```

For undoing accidental deletes, see `file-history` (`history:restore`,
`sync:restore`, `sync:deleted`).

## Daily Notes

```bash
# Open today's daily note (creates if needed)
obsidian daily

# Get the expected daily note path (without creating)
obsidian daily:path

# Read today's content
obsidian daily:read

# Append / prepend
obsidian daily:append content="- Met with team about roadmap"
obsidian daily:prepend content="## Morning Goals\n- Review PRs"

# Open in a split or new window
obsidian daily paneType=split
obsidian daily paneType=window
```

The CLI does not expose a `date=` parameter on `daily` itself; for past
dates use `obsidian open path="Daily/2026-02-15.md"` (with the actual
folder/format from your Daily Notes settings).

## Random & Unique Notes

```bash
# Open a random note
obsidian random

# Limit randomness to a folder
obsidian random folder=Inbox newtab

# Read a random note (returns content + path)
obsidian random:read folder=Inbox

# Unique note creator (Zettelkasten-style)
obsidian unique name="Idea" content="# Spark\n\n" open
```

## Web Viewer

```bash
# Open a URL in Obsidian's built-in web viewer
obsidian web url="https://obsidian.md/help/cli"

# In a new tab
obsidian web url="https://obsidian.md/help/cli" newtab
```

Useful for keeping reference docs side-by-side with notes without leaving
Obsidian.

## App Maintenance

```bash
# Obsidian app version
obsidian version

# Reload the active window (cheap; preserves vault)
obsidian reload

# Full app restart (heavier; for plugin reloads, prefer plugin:reload)
obsidian restart
```

## Common Flags

| Flag / Parameter | Description |
|------------------|-------------|
| `format=json` | JSON output for machine parsing |
| `format=csv`, `format=tsv` | Spreadsheet-friendly outputs |
| `format=tree` | Tree view (folders, outline) |
| `--copy` | **Universal**: copy command output to clipboard |
| `overwrite` | Replace existing file on `create` |
| `permanent` | Irreversible delete (skip trash) |
| `inline` | Append/prepend without an added newline |
| `open` | Open file after creating |
| `newtab` | Open in a new tab instead of replacing the active leaf |
| `total` | Return only the count for list commands |
| `paneType=tab\|split\|window` | Choose where to open |

## Agentic Optimizations

| Context | Command |
|---------|---------|
| List files (structured) | `obsidian files format=json` |
| Filter by extension | `obsidian files ext=md` |
| File count | `obsidian files total` |
| Folder tree | `obsidian folders format=tree` |
| Read note content | `obsidian read file="Name"` |
| Read & copy to clipboard | `obsidian read file="Name" --copy` |
| Quick capture to daily | `obsidian daily:append content="text"` |
| Append without newline | `obsidian append file=X content=Y inline` |
| Rename in place | `obsidian rename file=X name=Y` |
| Word count only | `obsidian wordcount file=X words` |
| Random note (read) | `obsidian random:read folder=X` |

## Related Skills

- **search-discovery** — Find notes by content, tags, links, or grep-style context
- **properties** — Manage YAML frontmatter on notes
- **tasks** — Task management across the vault
- **bases** — Query notes via Base views
- **templates** — List, preview, and insert templates
- **file-history** — Restore previous versions or recover deletes
- **vault-management** — Multi-vault `vault=` prefix and vault info
