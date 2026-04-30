---
created: 2026-04-30
modified: 2026-04-30
reviewed: 2026-04-30
name: templates
description: |
  List, read, and insert Obsidian templates from the core Templates plugin.
  Covers template variable resolution ({{date}}, {{time}}, {{title}}) and the
  difference between inserting into the active file vs creating a new file
  from a template. Use when the user mentions Obsidian templates, the
  Templates plugin, or template variable resolution.
user-invocable: false
allowed-tools: Bash(obsidian *), Read, Grep, Glob
---

# Obsidian Templates

## When to Use This Skill

| Use this skill when... | Use the alternative instead when... |
|---|---|
| Listing or previewing the templates configured in the vault | Editing template content as a plain note — use `vault-files` |
| Inserting a template into the currently open note | Creating a new note **from** a template — use `vault-files` `create … template=…` |
| Reading the resolved (`{{date}}` → real date) form of a template | Working with Templater plugin scripts — use `command-palette` for `templater-obsidian:*` |

This skill covers the **core Templates plugin**. The community Templater
plugin uses a different command surface — invoke it via `command-palette`
(`templater-obsidian:*`) instead.

## Prerequisites

- Obsidian desktop v1.12.4+ with CLI enabled
- Obsidian must be running
- Core **Templates** plugin enabled, with a templates folder configured

## List Templates

```bash
# All templates
obsidian templates

# Just the count
obsidian templates total
```

## Read a Template

```bash
# Raw template content (variables unresolved)
obsidian template:read name="Meeting"

# Resolve variables ({{date}}, {{time}}, {{title}})
obsidian template:read name="Meeting" resolve

# Provide a title for {{title}} resolution
obsidian template:read name="Meeting" title="Standup 2026-04-30" resolve
```

## Insert a Template

```bash
# Insert into the active file at the cursor
obsidian template:insert name="Meeting"
```

`template:insert` only works on the active editor. To create a new note
from a template instead, reach for `vault-files`:

```bash
obsidian create name="Meeting 2026-04-30" template="Meeting"
```

## Common Patterns

### "Preview what a template will produce before inserting"

```bash
obsidian template:read name="Daily" resolve
```

### "Bulk-create a week of daily notes from a template"

```bash
for offset in 0 1 2 3 4; do
  date=$(date -v+${offset}d +%F)   # macOS; use date -d "+$offset days" +%F on Linux
  obsidian create path="Daily/$date.md" template="Daily"
done
```

### "Open today's daily template raw vs resolved (debugging)"

```bash
obsidian template:read name="Daily"           # raw, with {{date}}
obsidian template:read name="Daily" resolve   # with today's date filled in
```

## Template Variables

The core Templates plugin understands:

| Variable | Resolves to |
|----------|-------------|
| `{{date}}` | Current date (format from Templates settings) |
| `{{time}}` | Current time (format from Templates settings) |
| `{{title}}` | The new note's title (or `title=` parameter) |

Use the `resolve` flag to apply these — without it, `template:read` returns
the raw source, which is what you want for editing the template itself.

## Agentic Optimizations

| Context | Command |
|---------|---------|
| List templates | `obsidian templates` |
| Template count | `obsidian templates total` |
| Raw template body | `obsidian template:read name=X` |
| Resolved template body | `obsidian template:read name=X resolve` |
| Insert into active file | `obsidian template:insert name=X` |
| Create new note from template | `obsidian create name=X template=Y` (see `vault-files`) |

## Related Skills

- **vault-files** — Create new notes from templates (`create … template=…`)
- **command-palette** — Invoke Templater (`templater-obsidian:*`) commands
- **plugins-themes** — Enable / configure the Templates core plugin
