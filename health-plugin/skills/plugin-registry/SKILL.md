---
model: haiku
name: Plugin Registry
description: |
  Understanding Claude Code's plugin registry structure, installation scopes,
  and common issues. Use when troubleshooting plugin installation problems,
  understanding why plugins show as installed incorrectly, or manually fixing
  registry entries.
allowed-tools: Bash, Read, Write, Edit, Glob, Grep, TodoWrite
created: 2026-02-04
modified: 2026-02-05
reviewed: 2026-02-05
---

# Claude Code Plugin Registry

Expert knowledge for understanding and troubleshooting the Claude Code plugin registry.

## When to Use This Skill

| Use this skill when... | Use something else when... |
|------------------------|---------------------------|
| Plugin shows "installed" but isn't working | Setting up new plugins (use `/configure:claude-plugins`) |
| Need to understand plugin scopes | Configuring plugin permissions (use settings-configuration skill) |
| Fixing orphaned registry entries | Creating workflows with plugins (use github-actions-plugin) |
| Debugging installation failures | |

## Registry Location

The plugin registry is stored at:

```
~/.claude/plugins/installed_plugins.json
```

This file tracks all installed plugins across all projects.

## Registry Structure (v2)

```json
{
  "version": 2,
  "plugins": {
    "plugin-name@marketplace-name": [
      {
        "scope": "project",
        "projectPath": "/path/to/project",
        "installPath": "~/.claude/plugins/cache/marketplace/plugin-name/1.0.0",
        "version": "1.0.0",
        "installedAt": "2024-01-15T10:30:00Z",
        "lastUpdated": "2024-01-15T10:30:00Z",
        "gitCommitSha": "abc123"
      }
    ]
  }
}
```

Each plugin key maps to an **array** of installations (supporting multiple scopes).

### Field Reference

| Field | Required | Description |
|-------|----------|-------------|
| `scope` | Yes | `"project"` or `"user"` (global) |
| `projectPath` | project only | Directory where plugin is active |
| `installPath` | Yes | Cache path for installed plugin files |
| `version` | Yes | Installed version |
| `installedAt` | Yes | ISO timestamp of installation |
| `lastUpdated` | Yes | ISO timestamp of last update |
| `gitCommitSha` | Yes | Git commit of installed version |

## Installation Scopes

### User Scope (global, default)

```bash
/plugin install my-plugin@marketplace
```

- `"scope": "user"` in registry entry
- No `projectPath` field
- Available in all projects

### Project Scope

```bash
/plugin install my-plugin@marketplace --scope project
```

- `"scope": "project"` in registry entry
- Has `projectPath` set to installation directory
- Should only be active in that project
- **Bug #14202**: Still shows as "installed" in other projects

## Known Issue: #14202

**Problem**: Project-scoped plugins incorrectly appear as globally installed.

**Root Cause**: Inconsistent `projectPath` checking:

| Operation | Checks projectPath? | Result |
|-----------|---------------------|--------|
| Marketplaces "(installed)" | No | Shows installed everywhere |
| `/plugin install` | No | Refuses to install |
| Installed tab listing | Yes | Correctly filtered |

**Symptoms**:
1. Plugin shows "(installed)" checkmark in Marketplaces view
2. `/plugin install` says "already installed"
3. Plugin doesn't appear in Installed tab for current project
4. Plugin doesn't actually work in current project

**Workaround**: Manually edit the registry to add an entry for the current project.

## Manual Registry Operations

### View Registry

```bash
jq . ~/.claude/plugins/installed_plugins.json
```

### List All Plugins

```bash
jq -r '.plugins | keys[]' ~/.claude/plugins/installed_plugins.json
```

### Find Project-Scoped Plugins

```bash
jq '.plugins | to_entries[] | .value[] | select(.scope == "project") | {projectPath, version}' ~/.claude/plugins/installed_plugins.json
```

### Find Orphaned Entries

Use the Read tool to read `~/.claude/plugins/installed_plugins.json`, then check each `projectPath` with `test -d`.

### Backup Registry

```bash
cp ~/.claude/plugins/installed_plugins.json ~/.claude/plugins/installed_plugins.json.backup
```

## Fixing Registry Issues

### Remove Orphaned Entry

1. Read `~/.claude/plugins/installed_plugins.json` with the Read tool
2. Back up with `cp ~/.claude/plugins/installed_plugins.json ~/.claude/plugins/installed_plugins.json.backup`
3. Remove the orphaned entry from the `plugins` object
4. Write the updated JSON with the Write tool

### Add Entry for Current Project

1. Read the registry with Read tool
2. Add a new entry to the plugin's array with `scope: "project"` and current `projectPath`
3. Write the updated JSON with Write tool

### Convert Project-Scoped to User (Global)

1. Read the registry with Read tool
2. Change `"scope": "project"` to `"scope": "user"` and remove `projectPath`
3. Write the updated JSON with Write tool

## Project Settings Integration

Project-scoped plugins also need entries in `.claude/settings.json`:

```json
{
  "enabledPlugins": [
    "plugin-name@marketplace"
  ]
}
```

Without this, even a correctly registered project-scoped plugin won't load.

## Troubleshooting Checklist

1. **Plugin shows installed but doesn't work**
   - Check if `projectPath` matches current directory
   - Check `.claude/settings.json` for `enabledPlugins`
   - Run `/health:plugins` for diagnosis

2. **Can't install plugin (already installed)**
   - Check registry for existing entry
   - Check if entry has different `projectPath`
   - Use `/health:plugins --fix` or manual edit

3. **Plugin works in one project but not another**
   - Likely a project-scoped plugin
   - Need separate registry entry per project
   - Or convert to global scope

4. **Registry file is corrupted**
   - Restore from backup if available
   - Or delete and reinstall plugins
   - Location: `~/.claude/plugins/installed_plugins.json`

## Agentic Optimizations

| Context | Command |
|---------|---------|
| View registry | `jq -c . ~/.claude/plugins/installed_plugins.json` |
| List plugins | `jq -r '.plugins \| keys[]' ~/.claude/plugins/installed_plugins.json` |
| Check specific | `jq '.plugins."name@market"' ~/.claude/plugins/installed_plugins.json` |
| Project plugins | `jq '.plugins \| to_entries[] \| .value[] \| select(.scope=="project")' ~/.claude/plugins/installed_plugins.json` |

## Quick Reference

### Registry Path
```
~/.claude/plugins/installed_plugins.json
```

### Key Format
```
{plugin-name}@{marketplace-name}
```

### Scope Indicator
- `"scope": "project"` + `projectPath` → Project-scoped
- `"scope": "user"` → Global (user-wide)

### After Editing
Always restart Claude Code for registry changes to take effect.
