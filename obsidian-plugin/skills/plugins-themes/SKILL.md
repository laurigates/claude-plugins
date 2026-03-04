---
model: haiku
created: 2026-03-04
modified: 2026-03-04
reviewed: 2026-03-04
name: plugins-themes
description: |
  Obsidian plugin and theme management via the official CLI.
  Covers listing, enabling, disabling, and reloading plugins,
  theme switching, and developer tools (eval, screenshot).
  Use when user mentions Obsidian plugins, themes, plugin development,
  enabling/disabling plugins, or running JavaScript in Obsidian.
user-invocable: false
allowed-tools: Bash, Read, Grep, Glob
---

# Obsidian Plugin & Theme Management

Manage community plugins, themes, and developer tools using the official Obsidian CLI.

## Prerequisites

- Obsidian desktop v1.12.4+ with CLI enabled
- Obsidian must be running

## When to Use

Use this skill automatically when:
- User wants to list, enable, or disable Obsidian plugins
- User needs to reload a plugin during development
- User wants to switch or list themes
- User needs to run JavaScript in the Obsidian runtime
- User wants to take screenshots of the Obsidian app

## Plugin Management

### List Plugins

```bash
# All installed plugins
obsidian plugins

# JSON output
obsidian plugins format=json
```

### Enable / Disable

```bash
# Enable a plugin by ID
obsidian plugin:enable id=dataview

# Disable a plugin
obsidian plugin:disable id=dataview
```

### Reload (Development)

```bash
# Hot-reload a plugin during development
obsidian plugin:reload id=my-plugin
```

## Theme Management

### List Themes

```bash
# Available themes
obsidian themes
```

### Switch Theme

```bash
# Set active theme
obsidian theme:set name="Minimal"
```

## Developer Tools

### Eval (JavaScript Execution)

```bash
# Execute JavaScript in Obsidian's runtime context
obsidian eval code="app.vault.getFiles().length"

# Access the full Obsidian API
obsidian eval code="app.workspace.getActiveFile()?.path"
```

### Screenshot

```bash
# Capture Obsidian window
obsidian dev:screenshot path=~/screenshot.png
```

## Agentic Optimizations

| Context | Command |
|---------|---------|
| List plugins (structured) | `obsidian plugins format=json` |
| Enable plugin | `obsidian plugin:enable id=X` |
| Disable plugin | `obsidian plugin:disable id=X` |
| Reload during dev | `obsidian plugin:reload id=X` |
| List themes | `obsidian themes` |
| Switch theme | `obsidian theme:set name="X"` |
| Run JS in Obsidian | `obsidian eval code="expression"` |

## Related Skills

- **vault-files** — Core file operations the plugins operate on
- **publish-sync** — Publish and sync workflows
