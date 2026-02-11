---
model: opus
created: 2026-02-04
modified: 2026-02-10
reviewed: 2026-02-05
description: Diagnose and fix plugin registry issues including orphaned entries and project-scope conflicts (addresses Claude Code issue #14202)
allowed-tools: Bash(test *), Bash(jq *), Bash(cp *), Bash(mkdir *), Read, Write, Edit, Glob, Grep, TodoWrite, AskUserQuestion
argument-hint: "[--fix] [--dry-run] [--plugin <name>]"
name: health-plugins
---

# /health:plugins

Diagnose and fix issues with the Claude Code plugin registry. This command specifically addresses issue #14202 where project-scoped plugins incorrectly appear as globally installed.

## When to Use This Skill

| Use this skill when... | Use another approach when... |
|------------------------|------------------------------|
| Fixing plugin registry corruption (issue #14202) | Comprehensive health check (use `/health:check`) |
| Diagnosing project-scope vs global plugin issues | Auditing plugins for relevance (use `/health:audit`) |
| Cleaning up orphaned plugin entries | Settings validation only needed |
| Resolving "plugin already installed" errors | Agentic optimization audit (use `/health:agentic-audit`) |
| Manually inspecting registry JSON | Just viewing installed plugins (read registry file) |

## Context

- Current project: !`pwd`
- Plugin registry exists: !`test -f ~/.claude/plugins/installed_plugins.json && echo "yes" || echo "no"`
- Project settings exists: !`test -f .claude/settings.json && echo "yes" || echo "no"`
- Project plugins dir: !`test -d .claude-plugin && echo "yes" || echo "no"`

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

## Execution

Execute this plugin registry diagnostic:

### Step 1: Read the plugin registry

1. Read `~/.claude/plugins/installed_plugins.json`
2. Parse each plugin entry to extract: plugin name and source, whether it has a `projectPath` (project-scoped), and the installation timestamp and version

### Step 2: Identify issues in the registry

Check for these issue types:

| Issue Type | Detection | Severity |
|------------|-----------|----------|
| Orphaned projectPath | `projectPath` directory doesn't exist | WARN |
| Missing from current project | Plugin has different `projectPath` than current directory | INFO |
| Duplicate scopes | Same plugin installed both globally and per-project | WARN |
| Invalid entry | Missing required fields or malformed data | ERROR |

### Step 3: Report findings

Print a structured diagnostic report listing all installed plugins with scope and status, followed by issues found with severity, details, and suggested fixes.

### Step 4: Apply fixes (if --fix flag)

For each issue, apply the appropriate fix:

1. **Orphaned projectPath** -- remove the orphaned entry from installed_plugins.json
2. **Plugin needed in current project** -- ask user which plugins to install, add new entry with current `projectPath`, update `.claude/settings.json` with `enabledPlugins` if needed

Before making changes:
1. Create backup: `~/.claude/plugins/installed_plugins.json.backup`
2. Validate JSON after modifications
3. Report what was changed

### Step 5: Verify the fix

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

## Agentic Optimizations

| Context | Command |
|---------|---------|
| Plugin registry diagnostics | `/health:plugins` |
| Fix registry issues | `/health:plugins --fix` |
| Dry-run mode | `/health:plugins --dry-run` |
| Inspect registry | `jq '.' ~/.claude/plugins/installed_plugins.json 2>/dev/null` |
| Check specific plugin | `jq '.["plugin-name"]' ~/.claude/plugins/installed_plugins.json 2>/dev/null` |
| List orphaned paths | `jq -r 'to_entries[] \| select(.value.projectPath? and (.value.projectPath \| test("."))) \| .value.projectPath' ~/.claude/plugins/installed_plugins.json 2>/dev/null` |

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
