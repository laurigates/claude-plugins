---
model: opus
created: 2026-02-04
modified: 2026-02-05
reviewed: 2026-02-05
description: Diagnose and fix plugin registry issues including orphaned entries and project-scope conflicts (addresses Claude Code issue #14202)
allowed-tools: Bash(test *), Bash(jq *), Bash(cp *), Bash(mkdir *), Read, Write, Edit, Glob, Grep, TodoWrite, AskUserQuestion
argument-hint: "[--fix] [--dry-run] [--plugin <name>]"
name: health-plugins
---

# /health:plugins

Diagnose and fix issues with the Claude Code plugin registry. This command specifically addresses issue #14202 where project-scoped plugins incorrectly appear as globally installed.

## Context

- Current project: !`pwd`
- Plugin registry: !`jq -c '.plugins | keys' ~/.claude/plugins/installed_plugins.json 2>/dev/null`
- Project settings: !`jq -c '.enabledPlugins // empty' .claude/settings.json 2>/dev/null`
- Project plugins dir: !`find .claude-plugin -maxdepth 1 -name '*.json' 2>/dev/null`

## Background: Issue #14202

When a plugin is installed with `--scope project` in one project, other projects incorrectly show the plugin as "(installed)" in the Marketplaces view. This happens because:

1. The plugin registry at `~/.claude/plugins/installed_plugins.json` stores `projectPath` for project-scoped installs
2. The Marketplaces view only checks if a plugin key exists, not whether it's installed for the *current* project
3. The install command refuses to install because it thinks the plugin already exists

**Impact**: Users cannot install the same plugin across multiple projects with project-scope isolation.

## Parameters

| Parameter | Description |
|-----------|-------------|
| `--fix` | Apply fixes to the plugin registry |
| `--dry-run` | Show what would be fixed without making changes |
| `--plugin <name>` | Check/fix a specific plugin only |

## Workflow

### Phase 1: Read Plugin Registry

1. Read `~/.claude/plugins/installed_plugins.json`
2. Parse each plugin entry to understand:
   - Plugin name and source
   - Whether it has a `projectPath` (project-scoped)
   - The installation timestamp and version

### Phase 2: Identify Issues

Check for these issue types:

| Issue Type | Detection | Severity |
|------------|-----------|----------|
| Orphaned projectPath | `projectPath` directory doesn't exist | WARN |
| Missing from current project | Plugin has different `projectPath` than current directory | INFO |
| Duplicate scopes | Same plugin installed both globally and per-project | WARN |
| Invalid entry | Missing required fields or malformed data | ERROR |

### Phase 3: Report Findings

```
Plugin Registry Diagnostics
===========================
Registry: ~/.claude/plugins/installed_plugins.json
Current Project: /path/to/current/project

Installed Plugins (N total)
---------------------------
Plugin                    | Scope    | Status
--------------------------|----------|--------
my-plugin@marketplace     | project  | OK (this project)
other-plugin@marketplace  | project  | NOT_HERE (different project)
global-plugin@marketplace | global   | OK

Issues Found (N)
----------------
1. [WARN] other-plugin@marketplace
   - Installed for: /path/to/other/project
   - This causes it to show as "installed" in Marketplaces view
   - Fix: Add entry for current project

2. [WARN] orphaned-plugin@marketplace
   - projectPath: /deleted/project (does not exist)
   - Fix: Remove orphaned entry

Recommendations
---------------
Run `/health:plugins --fix` to:
- Add missing project entries for plugins you want in this project
- Remove orphaned entries for deleted projects
```

### Phase 4: Fix (if --fix flag)

For each issue, apply the appropriate fix:

**Orphaned projectPath:**
```json
// Remove the orphaned entry from installed_plugins.json
```

**Plugin needed in current project:**
1. Ask user which plugins they want to install for current project
2. Add new entry to `installed_plugins.json` with current `projectPath`
3. Update `.claude/settings.json` with `enabledPlugins` if needed

**Before making changes:**
1. Create backup: `~/.claude/plugins/installed_plugins.json.backup`
2. Validate JSON after modifications
3. Report what was changed

### Phase 5: Verify Fix

After applying fixes:
1. Re-read the registry
2. Confirm issues are resolved
3. Remind user to restart Claude Code for changes to take effect

## Registry Structure Reference

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

**Scope types:**
- `"scope": "project"` — has `projectPath`, only active in that project
- `"scope": "user"` — no `projectPath`, active globally

## Manual Workaround

If automatic fix fails, users can manually edit `~/.claude/plugins/installed_plugins.json`:

1. Open the file in an editor
2. Find the plugin entry
3. Either:
   - Remove `projectPath` to make it global
   - Change `projectPath` to current project path
   - Add a new entry with different key for current project
4. Save and restart Claude Code

## Flags

| Flag | Description |
|------|-------------|
| `--fix` | Apply fixes (with confirmation prompts) |
| `--dry-run` | Show what would be fixed without changes |
| `--plugin <name>` | Target a specific plugin |

## See Also

- `/health:check` - Full diagnostic scan
- `/health:settings` - Settings file validation
- [Issue #14202](https://github.com/anthropics/claude-code/issues/14202) - Upstream bug report
