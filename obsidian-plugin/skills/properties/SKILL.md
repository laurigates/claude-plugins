---
created: 2026-03-04
modified: 2026-09-22
reviewed: 2026-09-22
name: properties
description: "Obsidian YAML frontmatter properties and aliases: read, set, remove on notes. Use when user mentions frontmatter, metadata, aliases, status, or dates."
user-invocable: false
allowed-tools: Bash, Read, Grep, Glob
---

# Obsidian Properties Management

## When to Use This Skill

| Use this skill when... | Use the alternative instead when... |
|---|---|
| Reading, setting, or removing a single YAML property on a live note via the running CLI | Doing offline bulk frontmatter rewrites across many files — use `vault-frontmatter` |
| Updating `status:`, `aliases:`, or a date property on a note Obsidian currently has open | Editing note body content rather than frontmatter — use `vault-files` |
| Auditing which property names exist across the vault, and how often | Listing or counting **tags** — use `search-discovery` (`tags`, `tag`) |
| Confirming a property change is reflected in Obsidian's metadata cache | Repairing broken wikilinks after a rename — use `vault-wikilinks` |

Read, set, and remove YAML frontmatter properties on Obsidian notes using the official CLI.

## Prerequisites

- Obsidian desktop 1.12.7+ installer with CLI enabled
- Obsidian must be running

## Command Shape

Property commands are **singular** (`property:set`, `property:remove`,
`property:read`) and address the property by `name=`, not by a
`key=value` pair. The plural `properties` command is the vault-wide
listing/inspection view.

| Command | Purpose |
|---------|---------|
| `properties` | List property names across the vault, or on one file |
| `property:read` | Read one property's value |
| `property:set` | Set one property (optionally typed) |
| `property:remove` | Remove one property |
| `aliases` | List aliases across the vault, or on one file |

All four file-scoped commands default to the **active file** when neither
`file=` nor `path=` is given.

## List / Inspect Properties

```bash
# Every property name used in the vault (default format: yaml)
obsidian properties

# With occurrence counts, sorted by frequency
obsidian properties counts sort=count

# Count of distinct property names
obsidian properties total

# Occurrence count for one property name
obsidian properties name=status

# Properties on a specific file, or the active file
obsidian properties file="Project Spec"
obsidian properties path="Projects/Spec.md"
obsidian properties active

# Structured output
obsidian properties file="Project Spec" format=json
obsidian properties format=tsv
```

## Read a Property

```bash
obsidian property:read name=status
obsidian property:read name=status file="Project Spec"
obsidian property:read name=due path="Projects/Spec.md"
```

## Set a Property

`name=` and `value=` are both required; `type=` is optional and tells
Obsidian how to store the value.

```bash
# Text (default type) on the active file
obsidian property:set name=status value=active

# On a specific file
obsidian property:set name=status value=draft file="Post"

# Typed values
obsidian property:set name=due value=2026-03-15 type=date
obsidian property:set name=reviewed value="2026-03-15T09:00" type=datetime
obsidian property:set name=priority value=1 type=number
obsidian property:set name=published value=true type=checkbox
obsidian property:set name=aliases value="JS,ECMAScript" type=list
```

Setting multiple properties is one invocation per property — there is no
multi-property form.

## Remove a Property

```bash
obsidian property:remove name=draft
obsidian property:remove name=old_field file="Note"
```

## Aliases

```bash
# All aliases in the vault
obsidian aliases

# Count, or with the owning file paths
obsidian aliases total
obsidian aliases verbose

# Aliases on the active file, or a specific one
obsidian aliases active
obsidian aliases file="JavaScript"
```

To *add* an alias, set the `aliases` property as a list:

```bash
obsidian property:set name=aliases value="JS,js,ECMAScript" type=list file="JavaScript"
```

## Property Types

| `type=` | Example value | Notes |
|---------|---------------|-------|
| `text` | `active` | Default when `type=` is omitted |
| `list` | `"a,b,c"` | Comma-separated; use for `aliases`, `tags` |
| `number` | `1` | Numeric |
| `checkbox` | `true` | Boolean |
| `date` | `2026-03-15` | ISO 8601 date |
| `datetime` | `2026-03-15T09:00` | ISO 8601 date + time |

## Common Patterns

### Status workflow

```bash
obsidian property:set name=status value=draft file="Post"
obsidian property:set name=status value=review file="Post"
obsidian property:set name=status value=published file="Post"
obsidian property:set name=published value=true type=checkbox file="Post"
```

### Audit property usage before a schema change

```bash
# Which property names exist, and how heavily used
obsidian properties counts sort=count

# How many notes carry the one you're about to rename
obsidian properties name=status
```

### Confirm a write landed

```bash
obsidian property:set name=status value=active file="Note"
obsidian property:read name=status file="Note"
```

## Agentic Optimizations

| Context | Command |
|---------|---------|
| Property names + counts | `obsidian properties counts sort=count` |
| Properties on one file (structured) | `obsidian properties file=X format=json` |
| Read one property | `obsidian property:read name=K file=X` |
| Set a property | `obsidian property:set name=K value=V file=X` |
| Set a typed property | `obsidian property:set name=K value=V type=date` |
| Remove a property | `obsidian property:remove name=K file=X` |
| Usage count for a name | `obsidian properties name=K` |
| List aliases with paths | `obsidian aliases verbose` |

## Related Skills

- **vault-files** — Read and create notes
- **search-discovery** — Search by property values with `[key:value]` syntax; tag listing (`tags`, `tag`)
- **bases** — Base views filter on the properties set here
