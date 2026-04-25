---
created: 2026-03-04
modified: 2026-04-25
reviewed: 2026-04-25
name: properties
description: |
  Obsidian YAML frontmatter property management via the official CLI.
  Covers reading, setting, and removing properties/metadata on notes.
  Use when user mentions frontmatter, properties, metadata, YAML,
  or note attributes like status, tags, dates, aliases.
user-invocable: false
allowed-tools: Bash, Read, Grep, Glob
---

# Obsidian Properties Management

## When to Use This Skill

| Use this skill when... | Use the alternative instead when... |
|---|---|
| Reading, setting, or removing a single YAML property on a live note via the running CLI | Doing offline bulk frontmatter rewrites across many files — use `vault-frontmatter` |
| Updating `status:`, `tags:`, or `aliases:` on a note Obsidian currently has open | Editing note body content rather than frontmatter — use `vault-files` |
| Confirming a property change is reflected in Obsidian's metadata cache | Repairing broken wikilinks after a rename — use `vault-wikilinks` |

Read, set, and remove YAML frontmatter properties on Obsidian notes using the official CLI.

## Prerequisites

- Obsidian desktop v1.12.4+ with CLI enabled
- Obsidian must be running

## When to Use

Use this skill automatically when:
- User wants to read or inspect note metadata/frontmatter
- User needs to set, update, or add properties to notes
- User wants to remove properties from notes
- User asks about note status, tags, dates, or custom fields
- User needs to manage aliases on notes

## Core Operations

### Read Properties

```bash
# Read all properties from a note
obsidian properties file="Project Spec"

# JSON output for parsing
obsidian properties file="Project Spec" format=json
```

### Set Properties

```bash
# Set a text property
obsidian properties:set file="Note" status=active

# Set a date property
obsidian properties:set file="Note" due=2026-03-15 type=date

# Set multiple properties
obsidian properties:set file="Note" status=draft priority=high

# Set tags property
obsidian properties:set file="Note" tags="blog,publish" type=tags
```

### Remove Properties

```bash
# Remove a single property
obsidian properties:remove file="Note" key=draft

# Remove multiple properties
obsidian properties:remove file="Note" key=old_field
```

## Property Types

| Type | Example | Notes |
|------|---------|-------|
| Text | `status=active` | Default type |
| Date | `due=2026-03-15 type=date` | ISO 8601 format |
| Tags | `tags="a,b" type=tags` | Comma-separated |
| Number | `priority=1` | Numeric values |
| Boolean | `published=true` | true/false |
| List | `aliases="Name1,Name2" type=tags` | Comma-separated |

## Common Patterns

### Status Workflow

```bash
# Set draft status
obsidian properties:set file="Post" status=draft

# Move to review
obsidian properties:set file="Post" status=review

# Mark published
obsidian properties:set file="Post" status=published published=true
```

### Alias Management

```bash
# Add aliases for wikilink resolution
obsidian properties:set file="JavaScript" aliases="JS,js,ECMAScript" type=tags
```

## Agentic Optimizations

| Context | Command |
|---------|---------|
| Read properties (structured) | `obsidian properties file="X" format=json` |
| Set property | `obsidian properties:set file="X" key=value` |
| Remove property | `obsidian properties:remove file="X" key=field` |
| Typed property | `obsidian properties:set file="X" field=val type=date` |

## Related Skills

- **vault-files** — Read and create notes
- **search-discovery** — Search by property values with `[key:value]` syntax
