---
created: 2026-03-04
modified: 2026-04-30
reviewed: 2026-04-30
name: search-discovery
description: |
  Obsidian vault search and discovery via the official CLI — full-text and
  grep-style context search, tag listing and lookup, outgoing/incoming link
  traversal, outline navigation, orphan and dead-end detection, and broken
  wikilink audits. Use when the user mentions searching notes, finding tags,
  exploring links/backlinks, headings/outline, orphaned or dead-end notes,
  or broken wikilinks.
user-invocable: false
allowed-tools: Bash(obsidian *), Read, Grep, Glob
---

# Obsidian Search & Discovery

## When to Use This Skill

| Use this skill when... | Use the alternative instead when... |
|---|---|
| Running full-text or grep-style search, tag queries, or backlink traversal against the running vault | Triaging orphaned notes for archival or MOC linking — use `vault-orphans` |
| Listing unresolved wikilinks Obsidian currently flags as broken | Repairing the broken wikilinks once located — use `vault-wikilinks` |
| Inspecting the heading outline of a single note | Reading the full note content — use `vault-files` |
| Querying notes already organised by a Base view | — use `bases` |

Search, navigate, and audit the vault link graph using the official Obsidian CLI.

## Prerequisites

- Obsidian desktop v1.12.4+ with CLI enabled
- Obsidian must be running

## Search

### Path-Only Search

`search` returns matching file paths only.

```bash
# Basic search
obsidian search query="project roadmap"

# Limit and JSON output
obsidian search query="meeting" limit=10 format=json

# Restrict to a folder
obsidian search query="status::active" path=Projects

# Match count only
obsidian search query="TODO" total

# Case-sensitive
obsidian search query="API" case
```

### Grep-Style Context Search

`search:context` returns `path:line: text` lines — the agentic-friendly mode.

```bash
# Show matching lines with file/line context
obsidian search:context query="TODO"

# JSON-structured context
obsidian search:context query="TODO" format=json

# Restricted to a folder, case-sensitive
obsidian search:context query="API" path=Projects case

# Limit files searched
obsidian search:context query="TODO" limit=20
```

`search:context` is the right default for agents — line numbers feed straight
into `obsidian read` + line offsets, or into edit workflows.

### Open Search View

```bash
# Pop the search panel pre-filled
obsidian search:open query="review needed"
```

### Obsidian Query Operators

The `query=` value uses Obsidian's standard search syntax — `tag:`, `path:`,
`file:`, `line:`, `[property:value]`, and so on:

```bash
obsidian search query="tag:#publish"
obsidian search query="[status:active] tag:#blog"
obsidian search:context query="path:Daily TODO"
```

## Tags

```bash
# All tags
obsidian tags

# Tags with counts (default sort=name)
obsidian tags counts

# Sorted by frequency
obsidian tags sort=count counts

# JSON output
obsidian tags format=json

# Tags for the active file (or for file=/path=)
obsidian tags active
obsidian tags file=Recipe

# Tag info (occurrence count + which files)
obsidian tag name=pkm
obsidian tag name=project/active total
obsidian tag name=pkm verbose
```

## Outline (Headings)

```bash
# Heading tree of the active file
obsidian outline

# Specific file
obsidian outline file=Recipe

# JSON for navigation
obsidian outline file=Recipe format=json

# Markdown render
obsidian outline file=Recipe format=md

# Just the heading count
obsidian outline file=Recipe total
```

## Links

```bash
# Outgoing links from a note (default: active file)
obsidian links file="Architecture Overview"
obsidian links file="Architecture Overview" total

# Backlinks
obsidian backlinks file="API Design"
obsidian backlinks file="API Design" counts
obsidian backlinks file="API Design" format=json

# Unresolved (broken) wikilinks across the vault
obsidian unresolved
obsidian unresolved counts          # with link counts
obsidian unresolved verbose         # include source files
obsidian unresolved format=json

# Notes with no incoming links
obsidian orphans

# Notes with no outgoing links
obsidian deadends

# Counts only
obsidian orphans total
obsidian deadends total
```

`orphans` (no incoming) and `deadends` (no outgoing) target different
problems — combine them to find truly disconnected notes.

## Common Flags

| Flag | Description |
|------|-------------|
| `format=json` | JSON output for machine parsing |
| `format=tsv`, `format=csv` | Spreadsheet-friendly output |
| `format=md` | Markdown rendering (outline, base:query) |
| `limit=N` | Cap result count |
| `path=<folder>` | Restrict search to a folder |
| `case` | Case-sensitive search |
| `total` | Return only the count |
| `counts` | Include per-result counts |
| `verbose` | Include source files / details |
| `--copy` | Copy result to clipboard |

## Agentic Optimizations

| Context | Command |
|---------|---------|
| Grep-style search (default) | `obsidian search:context query="term"` |
| Path-only search (structured) | `obsidian search query="term" format=json` |
| Match count | `obsidian search query="term" total` |
| Tag frequency analysis | `obsidian tags counts sort=count` |
| Find tagged notes | `obsidian tag name=X verbose` |
| Heading outline (json) | `obsidian outline file=X format=json` |
| Broken link audit | `obsidian unresolved counts verbose` |
| Orphan detection | `obsidian orphans` |
| Dead-end detection | `obsidian deadends` |
| Link graph for note | `obsidian links file=X` + `obsidian backlinks file=X` |

## Related Skills

- **vault-files** — Read content at a `path:line` returned by `search:context`
- **properties** — Search and filter by frontmatter properties
- **bases** — Pre-built queries via Base views
- **bookmarks** — Promote a frequent search to a saved bookmark
