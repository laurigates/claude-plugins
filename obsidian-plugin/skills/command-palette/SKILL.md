---
created: 2026-04-30
modified: 2026-04-30
reviewed: 2026-04-30
name: command-palette
description: |
  Run any Obsidian command (built-in or plugin-registered) from the CLI, list
  available commands, and inspect or look up hotkeys. Use when the user wants
  to trigger a command they would normally invoke from the command palette,
  enumerate plugin-registered commands, or check which hotkey is bound to an
  action.
user-invocable: false
allowed-tools: Bash(obsidian *), Read, Grep, Glob
---

# Obsidian Command Palette

## When to Use This Skill

| Use this skill when... | Use the alternative instead when... |
|---|---|
| Triggering a command the user would normally pick from the command palette (`Ctrl/Cmd+P`) | Running JavaScript via the developer API — use `dev-tools` |
| Discovering what commands a plugin registers | Enabling/disabling a plugin entirely — use `plugins-themes` |
| Looking up which hotkey is bound to a command | Setting up a workspace — use `workspaces` |

The command palette is Obsidian's universal action surface — every built-in
operation and every command registered by a plugin appears here. The CLI
exposes the same surface, which is the leverage point for automation: any
plugin command becomes scriptable without writing JavaScript.

## Prerequisites

- Obsidian desktop v1.12.4+ with CLI enabled
- Obsidian must be running

## List Commands

```bash
# All available command IDs
obsidian commands

# Filter by ID prefix (e.g. only Templater commands)
obsidian commands filter=templater

# Filter to a built-in family
obsidian commands filter=editor
obsidian commands filter=workspace
```

Command IDs follow the `pluginid:action` convention — e.g.
`editor:toggle-bold`, `workspace:split-vertical`, `dataview:dataview-rebuild-current-view`.

## Execute a Command

```bash
# Run a built-in command
obsidian command id=editor:toggle-bold

# Run a plugin-registered command
obsidian command id=templater-obsidian:insert-templater
obsidian command id=dataview:dataview-rebuild-current-view

# Open the command palette itself
obsidian command id=command-palette:open
```

`command` always operates against the active editor / active file — there
is no `file=` parameter. To run a command against a specific note, open
the note first (`obsidian open file=Foo`), then run `command`.

## Hotkeys

```bash
# All bound hotkeys
obsidian hotkeys

# Mark which entries are user-customised vs default
obsidian hotkeys verbose

# Count of bound hotkeys
obsidian hotkeys total

# Lookup the hotkey for one command
obsidian hotkey id=editor:toggle-bold
obsidian hotkey id=editor:toggle-bold verbose
```

## Common Patterns

### "Run a Templater template against the current note"

```bash
obsidian open file="Notes/Today"
obsidian command id=templater-obsidian:replace-in-file-templater
```

### "Find every Dataview command"

```bash
obsidian commands filter=dataview
```

### "Discover what hotkeys conflict with a new binding"

```bash
obsidian hotkeys format=json | jq '[.[] | select(.hotkey == "Ctrl+Shift+P")]'
```

(Requires the user's installed `jq`; the CLI itself does not pipe.)

## Agentic Optimizations

| Context | Command |
|---------|---------|
| List all commands | `obsidian commands` |
| Filter commands by prefix | `obsidian commands filter=PREFIX` |
| Run a command | `obsidian command id=PLUGIN:ACTION` |
| List hotkeys (structured) | `obsidian hotkeys format=json` |
| Lookup one hotkey | `obsidian hotkey id=PLUGIN:ACTION` |
| Show user-customised hotkeys | `obsidian hotkeys verbose` |

## Related Skills

- **plugins-themes** — Enable the plugin before its commands become available
- **workspaces** — Set up an editor state, then run a command against it
- **dev-tools** — When a command doesn't exist for what you need
