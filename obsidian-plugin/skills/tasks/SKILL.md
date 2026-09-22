---
created: 2026-03-04
modified: 2026-09-22
reviewed: 2026-09-22
name: tasks
description: "Obsidian tasks via CLI: list open tasks, filter by file/status, toggle or complete checklist items. Use when user mentions Obsidian tasks, todos, or checklists."
user-invocable: false
allowed-tools: Bash, Read, Grep, Glob
---

# Obsidian Task Management

## When to Use This Skill

| Use this skill when... | Use the alternative instead when... |
|---|---|
| Listing open `- [ ]` tasks across the vault, or toggling/completing them | Editing arbitrary note content rather than checklist lines — use `vault-files` |
| Filing a task on a daily note via the running Obsidian CLI | Tracking work in `taskwarrior` outside Obsidian — use a `taskwarrior-plugin` skill |
| Verifying which tasks Obsidian itself indexes as open | Searching for arbitrary text patterns including non-task content — use `search-discovery` |

List, filter, and update tasks across the Obsidian vault using the official CLI.

## Prerequisites

- Obsidian desktop 1.12.7+ installer with CLI enabled
- Obsidian must be running

## The Two Commands

The CLI exposes exactly two task commands. There is no create command —
tasks are **content**, so you add one by appending a `- [ ]` line with
`append` / `daily:append` (see `vault-files`).

| Command | Purpose |
|---------|---------|
| `tasks` | List / filter / count tasks |
| `task` | Show or update **one** task, addressed by location |

## List Tasks

```bash
# All tasks in the vault
obsidian tasks

# Incomplete only / completed only
obsidian tasks todo
obsidian tasks done

# Scope to a file
obsidian tasks file=Recipe
obsidian tasks path="Projects/Sprint.md"

# Scope to the active file or today's daily note
obsidian tasks active
obsidian tasks daily

# Counts instead of rows
obsidian tasks total
obsidian tasks daily total

# Group by file with line numbers (the agentic default —
# gives you the path:line that `task` needs to update)
obsidian tasks verbose

# Structured output (default format is plain text)
obsidian tasks format=json
obsidian tasks format=tsv
obsidian tasks format=csv

# Filter by a custom status character; quote shell-special ones
obsidian tasks 'status=?'
obsidian tasks status=-
```

Filters combine: `obsidian tasks file=Recipe todo verbose`.

## Show or Update a Task

`task` addresses a single checklist line by location — either a combined
`ref=path:line`, or `file=`/`path=`/`daily` plus `line=`.

```bash
# Show task info
obsidian task file=Recipe line=8
obsidian task ref="Recipe.md:8"

# Toggle completion
obsidian task ref="Recipe.md:8" toggle
obsidian task daily line=3 toggle

# Set an explicit state
obsidian task file=Recipe line=8 done      # → [x]
obsidian task file=Recipe line=8 todo      # → [ ]
obsidian task file=Recipe line=8 status=-  # → [-]
obsidian task daily line=3 done
```

`done`/`todo`/`status=` set a state outright; `toggle` flips whatever is
there. Use `status=` for custom markers your theme or plugin renders
(`-` cancelled, `/` in progress, `?` question, etc.).

## Workflow Patterns

### Capture a task to today's daily note

```bash
obsidian daily:append content="- [ ] Review PR #42"
```

### Find an open task, then complete it

```bash
# 1. Locate it — verbose gives path and line number
obsidian tasks todo verbose

# 2. Update by that location
obsidian task ref="Projects/Sprint.md:14" done
```

### Close out every task in today's daily note

```bash
obsidian tasks daily todo verbose
# then, per reported line:
obsidian task daily line=<n> done
```

### Count outstanding work

```bash
obsidian tasks todo total
obsidian tasks daily todo total
```

## Agentic Optimizations

| Context | Command |
|---------|---------|
| List tasks (structured) | `obsidian tasks format=json` |
| Open tasks only | `obsidian tasks todo` |
| Locate tasks (path + line) | `obsidian tasks verbose` |
| Tasks in one file | `obsidian tasks file=X` |
| Today's tasks | `obsidian tasks daily` |
| Outstanding count | `obsidian tasks todo total` |
| Complete a task | `obsidian task ref="path.md:N" done` |
| Toggle a task | `obsidian task ref="path.md:N" toggle` |
| Custom status | `obsidian task file=X line=N status=-` |
| Quick capture to daily | `obsidian daily:append content="- [ ] task"` |

## Related Skills

- **vault-files** — Append task lines to notes and daily notes (there is no `task` create command)
- **search-discovery** — Find notes containing tasks, or search task text
- **properties** — Track task metadata in frontmatter instead of checklist lines
