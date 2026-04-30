---
created: 2026-03-04
modified: 2026-04-30
reviewed: 2026-04-30
name: plugins-themes
description: |
  Lifecycle management for Obsidian community plugins, themes, and CSS
  snippets via the official CLI — install, enable, disable, uninstall,
  reload, switch theme, and toggle restricted (formerly "safe") mode.
  Use when the user mentions installing/enabling/disabling Obsidian
  plugins or themes, switching themes, or toggling CSS snippets. For
  developer commands (eval, devtools, dev:*, screenshot) use `dev-tools`.
user-invocable: false
allowed-tools: Bash(obsidian *), Read, Grep, Glob
---

# Obsidian Plugins, Themes & Snippets

## When to Use This Skill

| Use this skill when... | Use the alternative instead when... |
|---|---|
| Installing, enabling, disabling, or reloading community plugins | Running JavaScript in the app or capturing screenshots — use `dev-tools` |
| Switching the active theme or installing a new one | Triggering a plugin-registered command — use `command-palette` |
| Toggling CSS snippets on/off | Editing snippet CSS source on disk — use `vault-files` |
| Toggling Obsidian's restricted mode | Inspecting CSS rules with source location — use `dev-tools` |

Lifecycle management for community plugins, themes, and CSS snippets. The
**developer commands** (`eval`, `devtools`, `dev:*`, screenshots) live in
the dedicated `dev-tools` skill.

## Prerequisites

- Obsidian desktop v1.12.4+ with CLI enabled
- Obsidian must be running
- Restricted mode **off** (community plugins disabled while restricted mode is on)

## Plugins

### List

```bash
# All installed plugins
obsidian plugins

# Just community or just core
obsidian plugins filter=community
obsidian plugins filter=core

# Include version numbers
obsidian plugins versions

# Structured output
obsidian plugins format=json

# Currently enabled
obsidian plugins:enabled
obsidian plugins:enabled filter=community versions
```

### Plugin Info

```bash
obsidian plugin id=dataview
```

### Install / Uninstall (community only)

```bash
# Install from the community catalogue
obsidian plugin:install id=dataview

# Install and enable in one shot
obsidian plugin:install id=dataview enable

# Remove
obsidian plugin:uninstall id=dataview
```

### Enable / Disable

```bash
# Enable a plugin by ID
obsidian plugin:enable id=dataview

# Disable a plugin
obsidian plugin:disable id=dataview

# Specify type if the same id exists in both core and community
obsidian plugin:enable id=daily-notes filter=core
```

### Reload (developer hot-reload)

```bash
obsidian plugin:reload id=my-plugin
```

### Restricted Mode

Restricted mode disables all community plugins (formerly "Safe Mode"):

```bash
# Check / toggle
obsidian plugins:restrict
obsidian plugins:restrict on
obsidian plugins:restrict off
```

## Themes

```bash
# All installed themes
obsidian themes

# Include version numbers
obsidian themes versions

# Active theme info, or details for a specific theme
obsidian theme
obsidian theme name="Minimal"

# Switch active theme (empty string = built-in default)
obsidian theme:set name="Minimal"
obsidian theme:set name=""

# Install / uninstall community themes
obsidian theme:install name="Things"
obsidian theme:install name="Things" enable
obsidian theme:uninstall name="Things"
```

## CSS Snippets

```bash
# All snippets in the vault
obsidian snippets

# Currently enabled
obsidian snippets:enabled

# Toggle individual snippets by filename (without .css)
obsidian snippet:enable name=callout-tweaks
obsidian snippet:disable name=callout-tweaks
```

## Common Patterns

### "Install Dataview, enable it, and verify it loaded"

```bash
obsidian plugin:install id=dataview enable
obsidian plugins:enabled filter=community | grep -q '^dataview$' && echo OK || echo FAIL
```

### "Snapshot the current plugin/theme state"

```bash
obsidian plugins format=json     > plugins-$(date +%F).json
obsidian themes versions          > themes-$(date +%F).txt
obsidian snippets:enabled         > snippets-enabled-$(date +%F).txt
```

### "Disable every community plugin temporarily"

```bash
obsidian plugins:restrict on
# … work in restricted mode …
obsidian plugins:restrict off
```

## Agentic Optimizations

| Context | Command |
|---------|---------|
| List plugins (structured) | `obsidian plugins format=json` |
| Enabled plugins only | `obsidian plugins:enabled` |
| Enable plugin | `obsidian plugin:enable id=X` |
| Disable plugin | `obsidian plugin:disable id=X` |
| Install + enable | `obsidian plugin:install id=X enable` |
| Reload during dev | `obsidian plugin:reload id=X` |
| Toggle restricted mode | `obsidian plugins:restrict on\|off` |
| Switch theme | `obsidian theme:set name="X"` |
| Install theme + activate | `obsidian theme:install name="X" enable` |
| Toggle CSS snippet | `obsidian snippet:enable\|disable name=X` |

## Related Skills

- **dev-tools** — `eval`, `devtools`, `dev:*`, screenshots (developer surface)
- **command-palette** — Trigger plugin-registered commands once enabled
- **vault-files** — Read or edit snippet `.css` source under `.obsidian/snippets/`
