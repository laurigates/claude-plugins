---
created: 2026-04-30
modified: 2026-04-30
reviewed: 2026-04-30
name: bookmarks
description: |
  List and add Obsidian bookmarks — files, folders, headings/blocks, saved
  searches, and external URLs. Use when the user mentions Obsidian bookmarks,
  starring/saving notes for quick access, or scripted bookmark creation.
user-invocable: false
allowed-tools: Bash(obsidian *), Read, Grep, Glob
---

# Obsidian Bookmarks

## When to Use This Skill

| Use this skill when... | Use the alternative instead when... |
|---|---|
| Adding a file, folder, search query, or URL to the Bookmarks panel | Adding a generic frontmatter property — use `properties` |
| Listing the user's existing bookmarks | Listing every file in the vault — use `vault-files` |
| Bookmarking a heading or block within a file | Opening a file in a tab — use `workspaces` |

The Bookmarks core plugin must be enabled. Bookmarks support five target
types: files, folders, headings/blocks (via `subpath=`), saved searches, and
external URLs.

## Prerequisites

- Obsidian desktop v1.12.4+ with CLI enabled
- Obsidian must be running
- Core **Bookmarks** plugin enabled

## List Bookmarks

```bash
# All bookmarks (default tsv)
obsidian bookmarks

# Include bookmark types
obsidian bookmarks verbose

# Structured output
obsidian bookmarks format=json

# Just the count
obsidian bookmarks total
```

## Add a Bookmark

```bash
# Bookmark a file
obsidian bookmark file="Notes/Recipe.md"

# Bookmark a folder
obsidian bookmark folder="Projects/Active"

# Bookmark a heading or block within a file
obsidian bookmark file="Notes/Recipe.md" subpath="#Ingredients"
obsidian bookmark file="Notes/Recipe.md" subpath="^block-id"

# Bookmark a saved search query
obsidian bookmark search="tag:#followup status::open"

# Bookmark an external URL
obsidian bookmark url="https://obsidian.md/help/cli" title="Obsidian CLI docs"

# Custom title for any bookmark type
obsidian bookmark file="Notes/Recipe.md" title="Tonight's recipe"
```

## Common Patterns

### "Bookmark every file from a base view"

```bash
obsidian base:query file=Reading view="To read" format=paths \
  | while read -r path; do
      obsidian bookmark file="$path"
    done
```

### "Promote a frequent search to a bookmark"

```bash
obsidian bookmark search="path:Daily tag:#followup" title="Outstanding follow-ups"
```

### "Snapshot the current bookmark set"

```bash
obsidian bookmarks format=json > bookmarks-$(date +%F).json
```

## Agentic Optimizations

| Context | Command |
|---------|---------|
| List bookmarks (structured) | `obsidian bookmarks format=json` |
| List bookmarks with types | `obsidian bookmarks verbose` |
| Bookmark count | `obsidian bookmarks total` |
| Bookmark a file | `obsidian bookmark file=X` |
| Bookmark a heading | `obsidian bookmark file=X subpath="#H"` |
| Bookmark a block | `obsidian bookmark file=X subpath="^id"` |
| Bookmark a search | `obsidian bookmark search="QUERY"` |
| Bookmark a URL | `obsidian bookmark url=https://… title=…` |

## Related Skills

- **vault-files** — Source files referenced by file/folder/subpath bookmarks
- **search-discovery** — Construct the query strings used in search bookmarks
- **bases** — `base:query format=paths` feeds nicely into bulk-bookmark loops
