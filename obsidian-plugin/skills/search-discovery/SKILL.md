---
created: 2026-03-04
modified: 2026-03-04
reviewed: 2026-03-04
name: search-discovery
description: |
  Obsidian vault search and discovery via the official CLI.
  Covers full-text search, tag management, link traversal, backlinks,
  orphan detection, and unresolved link discovery.
  Use when user mentions searching notes, finding tags, exploring links,
  backlinks, orphaned notes, or broken wikilinks.
user-invocable: false
allowed-tools: Bash, Read, Grep, Glob
---

# Obsidian Search & Discovery

Full-text search, tag operations, and link graph traversal using the official Obsidian CLI.

## Prerequisites

- Obsidian desktop v1.12.4+ with CLI enabled
- Obsidian must be running

## When to Use

Use this skill automatically when:
- User wants to search vault content or metadata
- User asks about tags, tag counts, or tag management
- User wants to explore note links or backlinks
- User needs to find orphaned or unlinked notes
- User asks about broken/unresolved wikilinks

## Search

### Full-Text Search

```bash
# Basic search
obsidian search query="project roadmap"

# JSON output for parsing
obsidian search query="architecture" format=json

# Limit results
obsidian search query="meeting" limit=10

# Open results in Obsidian
obsidian search:open query="review needed"
```

### Property-Based Search

```bash
# Search by property value
obsidian search query="[status:active]"

# Search by tag
obsidian search query="[tag:publish]"

# Combined
obsidian search query="[status:draft] [tag:blog]"
```

## Tags

### List Tags

```bash
# All tags in vault
obsidian tags

# Tags sorted by frequency
obsidian tags sort=count

# Tags sorted by name
obsidian tags sort=name
```

### Find Notes by Tag

```bash
# Notes with a specific tag
obsidian tag tagname=pkm

# Notes with nested tag
obsidian tag tagname=project/active
```

### Rename Tags

```bash
# Bulk rename across vault (updates all notes)
obsidian tags:rename old=meeting new=meetings
```

## Links

### Outgoing Links

```bash
# Links from a note
obsidian links file="Architecture Overview"
```

### Backlinks (Incoming Links)

```bash
# Notes that link to this note
obsidian backlinks file="API Design"
```

### Unresolved Links

```bash
# Broken wikilinks (targets don't exist)
obsidian unresolved
```

### Orphaned Notes

```bash
# Notes with no incoming or outgoing links
obsidian orphans
```

## Common Flags

| Flag | Description |
|------|-------------|
| `format=json` | JSON output for machine parsing |
| `format=csv` | CSV output |
| `limit=N` | Limit result count |
| `sort=count\|name\|date` | Sort order |
| `--copy` | Copy result to clipboard |

## Agentic Optimizations

| Context | Command |
|---------|---------|
| Search (structured) | `obsidian search query="term" format=json` |
| Tag frequency analysis | `obsidian tags sort=count` |
| Find tagged notes | `obsidian tag tagname=X` |
| Broken link audit | `obsidian unresolved` |
| Orphan detection | `obsidian orphans` |
| Link graph for note | `obsidian links file="X"` then `obsidian backlinks file="X"` |

## Related Skills

- **vault-files** — Read, create, and manage notes
- **properties** — Search and filter by frontmatter properties
