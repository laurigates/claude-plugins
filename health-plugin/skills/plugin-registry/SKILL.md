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
modified: 2026-02-04
reviewed: 2026-02-04
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

## Registry Structure

```json
{
  "plugin-name@marketplace-name": {
    "name": "plugin-name",
    "source": "https://github.com/user/marketplace.git",
    "marketplaceName": "marketplace-name",
    "version": "1.0.0",
    "installedAt": "2024-01-15T10:30:00Z",
    "projectPath": "/path/to/project"
  }
}
```

### Field Reference

| Field | Required | Description |
|-------|----------|-------------|
| `name` | Yes | Plugin name without marketplace suffix |
| `source` | Yes | Git URL of the marketplace |
| `marketplaceName` | Yes | Name of the marketplace |
| `version` | Yes | Installed version |
| `installedAt` | Yes | ISO timestamp of installation |
| `projectPath` | No | If set, plugin is project-scoped |

## Installation Scopes

### Global Scope (default)

```bash
/plugin install my-plugin@marketplace
```

- No `projectPath` in registry entry
- Available in all projects
- Shows in "Installed" tab everywhere

### Project Scope

```bash
/plugin install my-plugin@marketplace --scope project
```

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
cat ~/.claude/plugins/installed_plugins.json | jq .
```

### List All Plugins

```bash
cat ~/.claude/plugins/installed_plugins.json | jq 'keys[]'
```

### Find Project-Scoped Plugins

```bash
cat ~/.claude/plugins/installed_plugins.json | jq 'to_entries[] | select(.value.projectPath) | {key, projectPath: .value.projectPath}'
```

### Find Orphaned Entries

```bash
cat ~/.claude/plugins/installed_plugins.json | jq -r 'to_entries[] | select(.value.projectPath) | .value.projectPath' | while read path; do
  [ ! -d "$path" ] && echo "Orphaned: $path"
done
```

### Backup Registry

```bash
cp ~/.claude/plugins/installed_plugins.json ~/.claude/plugins/installed_plugins.json.backup
```

## Fixing Registry Issues

### Remove Orphaned Entry

```bash
# Backup first
cp ~/.claude/plugins/installed_plugins.json ~/.claude/plugins/installed_plugins.json.backup

# Remove specific plugin
cat ~/.claude/plugins/installed_plugins.json | jq 'del(."plugin-name@marketplace")' > /tmp/plugins.json
mv /tmp/plugins.json ~/.claude/plugins/installed_plugins.json
```

### Add Entry for Current Project

```bash
# Get current project path
PROJECT_PATH=$(pwd)

# Add new entry (requires existing entry as template)
cat ~/.claude/plugins/installed_plugins.json | jq \
  --arg path "$PROJECT_PATH" \
  '."plugin-name@marketplace".projectPath = $path' > /tmp/plugins.json
mv /tmp/plugins.json ~/.claude/plugins/installed_plugins.json
```

### Convert Project-Scoped to Global

```bash
cat ~/.claude/plugins/installed_plugins.json | jq \
  'del(."plugin-name@marketplace".projectPath)' > /tmp/plugins.json
mv /tmp/plugins.json ~/.claude/plugins/installed_plugins.json
```

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
| View registry | `cat ~/.claude/plugins/installed_plugins.json \| jq -c .` |
| List plugins | `cat ~/.claude/plugins/installed_plugins.json \| jq -r 'keys[]'` |
| Check specific | `cat ~/.claude/plugins/installed_plugins.json \| jq '."name@market"'` |
| Find by project | `cat ~/.claude/plugins/installed_plugins.json \| jq 'to_entries[] \| select(.value.projectPath=="/path")'` |

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
- Has `projectPath` → Project-scoped
- No `projectPath` → Global

### After Editing
Always restart Claude Code for registry changes to take effect.
