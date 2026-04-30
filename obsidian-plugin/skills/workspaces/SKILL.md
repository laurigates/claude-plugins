---
created: 2026-04-30
modified: 2026-04-30
reviewed: 2026-04-30
name: workspaces
description: |
  Inspect and manage the Obsidian editor workspace — open tabs, recent files,
  saved Workspaces (the core plugin), and individual tab management. Use when
  the user asks what's open in Obsidian, wants to switch to a saved layout,
  save the current layout, or open files into specific tabs/groups.
user-invocable: false
allowed-tools: Bash(obsidian *), Read, Grep, Glob
---

# Obsidian Workspaces, Tabs & Recents

## When to Use This Skill

| Use this skill when... | Use the alternative instead when... |
|---|---|
| Inspecting the current workspace tree, tabs, or recently opened files | Reading or writing note content — use `vault-files` |
| Saving / loading layouts via the Workspaces core plugin | Switching between vaults — use `vault-management` |
| Opening a file into a specific tab group | Triggering a generic UI command — use `command-palette` |

The Workspaces core plugin must be enabled for `workspace:save` / `:load` /
`:delete` and the `workspaces` list to return data. `tabs`, `tab:open`,
`recents`, and the bare `workspace` tree command work without it.

## Prerequisites

- Obsidian desktop v1.12.4+ with CLI enabled
- Obsidian must be running
- For saved-layout commands: enable the **Workspaces** core plugin

## Inspect the Current Workspace

```bash
# Tree of the active workspace (groups, splits, leaves)
obsidian workspace

# Include item IDs (needed for tab:open group=)
obsidian workspace ids
```

## Tabs

```bash
# Open tabs in the active window
obsidian tabs

# Include tab IDs
obsidian tabs ids

# Open a file into a new tab (defaults to active group)
obsidian tab:open file="Notes/Recipe"

# Open into a specific group (use ids from `obsidian workspace ids` or `obsidian tabs ids`)
obsidian tab:open group=<group-id> file="Notes/Recipe"

# Open a non-file view (graph, file explorer, etc.)
obsidian tab:open view=graph
obsidian tab:open view=file-explorer
```

## Recent Files

```bash
# Recently opened files (tab history)
obsidian recents

# Just the count
obsidian recents total
```

## Saved Workspaces (core plugin)

```bash
# All saved layouts
obsidian workspaces
obsidian workspaces total

# Save the current layout
obsidian workspace:save name="Writing"

# Switch to a saved layout
obsidian workspace:load name="Writing"

# Delete a saved layout
obsidian workspace:delete name="Writing"
```

## Common Patterns

### "What is the user looking at right now?"

```bash
obsidian workspace
obsidian tabs
obsidian recents
```

### "Open these three notes side-by-side, then save the layout"

```bash
obsidian open file="Brief"
obsidian command id=workspace:split-vertical
obsidian tab:open file="Spec"
obsidian command id=workspace:split-vertical
obsidian tab:open file="Notes"
obsidian workspace:save name="Triage"
```

### "Restore the writing layout for a focused session"

```bash
obsidian workspace:load name="Writing"
```

### "Open the graph view in a new tab"

```bash
obsidian tab:open view=graph
```

## Agentic Optimizations

| Context | Command |
|---------|---------|
| Workspace tree | `obsidian workspace` |
| Workspace with IDs | `obsidian workspace ids` |
| Open tabs | `obsidian tabs` |
| Recently opened | `obsidian recents` |
| Open file in new tab | `obsidian tab:open file=X` |
| Open view (graph, etc.) | `obsidian tab:open view=Y` |
| List saved layouts | `obsidian workspaces` |
| Switch layout | `obsidian workspace:load name=X` |
| Save layout | `obsidian workspace:save name=X` |

## Related Skills

- **vault-files** — Read or write the file you just opened
- **command-palette** — `workspace:split-vertical`, `workspace:split-horizontal`, etc.
- **vault-management** — Switch vaults before inspecting their workspace
