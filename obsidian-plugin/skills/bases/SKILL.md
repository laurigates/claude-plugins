---
created: 2026-04-30
modified: 2026-04-30
reviewed: 2026-04-30
name: bases
description: |
  Query and create entries in Obsidian Bases — the database-over-notes feature.
  Covers listing base files, listing views, creating items in a base, and
  running view queries with structured output (json/csv/tsv/md/paths).
  Use when the user mentions Obsidian Bases, .base files, querying notes as
  a database, base views, or structured note queries.
user-invocable: false
allowed-tools: Bash(obsidian *), Read, Grep, Glob
---

# Obsidian Bases

## When to Use This Skill

| Use this skill when... | Use the alternative instead when... |
|---|---|
| Querying notes that share a Base view (status board, reading list, project tracker) | Doing a free-text search across the vault — use `search-discovery` |
| Creating a new entry that should land in a specific Base view | Creating an arbitrary note — use `vault-files` |
| Listing what `.base` files and views exist in the vault | Reading frontmatter on a single note — use `properties` |

[Bases](https://help.obsidian.md/bases) turn note collections into queryable views with frontmatter-driven filters and columns. The CLI exposes those views as structured data — JSON for the agent, CSV/TSV for piping, markdown for rendering.

## Prerequisites

- Obsidian desktop v1.12.4+ with CLI enabled
- Obsidian must be running
- At least one `.base` file in the vault

## List Bases and Views

```bash
# List all .base files in the vault
obsidian bases

# List the views defined in a base (default: active base)
obsidian base:views file=Reading
obsidian base:views path="Bases/Reading.base"
```

## Query a View

`base:query` runs a view and returns rows. Default format is JSON, which is
the right choice for agentic consumption.

```bash
# Query the active view of the active base
obsidian base:query

# Specific base + view, JSON for parsing
obsidian base:query file=Reading view="To read" format=json

# Markdown table for human consumption
obsidian base:query file=Reading view="To read" format=md

# Just the matching note paths (one per line, useful with xargs)
obsidian base:query file=Projects view=Active format=paths

# CSV for spreadsheet workflows
obsidian base:query file=Tasks view=Open format=csv
```

The `format=paths` mode is the agentic-friendly equivalent of a vault search
that already understands base filters — pipe the output into `obsidian read`
or any file-level skill.

## Create an Entry in a Base

Create a new note that automatically lands in a base view (the base's filter
must match the new note's frontmatter for it to actually appear):

```bash
# Add to the active base view
obsidian base:create name="Untitled Book"

# Specific base + view, with starting content
obsidian base:create file=Reading view="To read" name="The Mythical Man-Month" content="# The Mythical Man-Month\n\n"

# Open the new note in a new tab after creating
obsidian base:create file=Reading view="To read" name="New entry" newtab open
```

## Common Patterns

### "Find every active project and append a status update"

```bash
obsidian base:query file=Projects view=Active format=paths \
  | while read -r path; do
      obsidian append path="$path" content="\n## $(date +%F) update\n- "
    done
```

### "Show me a markdown table of incomplete reading"

```bash
obsidian base:query file=Reading view="To read" format=md
```

### "Bulk-create entries from a CSV"

Read each row, then call `base:create` per row with the desired `name=` and
`content=`. Avoid embedding shell operators inside the CLI invocation —
build values in shell variables first, then pass them.

## Agentic Optimizations

| Context | Command |
|---------|---------|
| List `.base` files | `obsidian bases` |
| List views in a base | `obsidian base:views file=X` |
| Query a view as JSON | `obsidian base:query file=X view=Y format=json` |
| Get matching paths only | `obsidian base:query file=X view=Y format=paths` |
| Markdown table for humans | `obsidian base:query file=X view=Y format=md` |
| Create entry in a view | `obsidian base:create file=X view=Y name="…"` |

## Related Skills

- **vault-files** — Read/write notes returned by a base query
- **properties** — Edit frontmatter that drives base filters
- **search-discovery** — Free-text and tag search when no base exists
