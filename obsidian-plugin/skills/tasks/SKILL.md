---
created: 2026-03-04
modified: 2026-04-25
reviewed: 2026-04-25
name: tasks
description: |
  Obsidian task management via the official CLI.
  Covers listing open tasks, creating tasks, and marking tasks complete.
  Use when user mentions Obsidian tasks, todos, checklists,
  or completing/creating tasks in their vault.
user-invocable: false
allowed-tools: Bash, Read, Grep, Glob
---

# Obsidian Task Management

## When to Use This Skill

| Use this skill when... | Use the alternative instead when... |
|---|---|
| Listing open `- [ ]` tasks across the vault, creating tasks, or marking tasks complete | Editing arbitrary note content rather than checklist lines — use `vault-files` |
| Filing a task on a daily note via the running Obsidian CLI | Tracking work in `taskwarrior` outside Obsidian — use a `taskwarrior-plugin` skill |
| Verifying which tasks Obsidian itself indexes as open | Searching for arbitrary text patterns including non-task content — use `search-discovery` |

List, create, and complete tasks across the Obsidian vault using the official CLI.

## Prerequisites

- Obsidian desktop v1.12.4+ with CLI enabled
- Obsidian must be running

## When to Use

Use this skill automatically when:
- User wants to list open tasks from their vault
- User needs to create new tasks in notes
- User wants to mark tasks as complete
- User asks about todos or checklists in Obsidian

## Core Operations

### List Tasks

```bash
# All open tasks across vault
obsidian tasks

# JSON output for parsing
obsidian tasks format=json
```

### Create a Task

```bash
# Create a new task
obsidian task:create content="Review PR #42"

# Create task in specific note
obsidian task:create content="Update documentation" file="Sprint Tasks"
```

### Complete a Task

```bash
# Mark task as done by ID
obsidian task:complete task=task-id
```

## Workflow Patterns

### Daily Task Capture

```bash
# Add task to today's daily note
obsidian daily:append content="- [ ] New task from CLI"

# Or use task:create
obsidian task:create content="Follow up on meeting action items"
```

### Task Review

```bash
# List all open tasks, pipe to grep for filtering
obsidian tasks format=json
```

## Agentic Optimizations

| Context | Command |
|---------|---------|
| List tasks (structured) | `obsidian tasks format=json` |
| Create task | `obsidian task:create content="text"` |
| Complete task | `obsidian task:complete task=ID` |
| Quick capture to daily | `obsidian daily:append content="- [ ] task"` |

## Related Skills

- **vault-files** — Append tasks to specific notes
- **search-discovery** — Find notes containing tasks
