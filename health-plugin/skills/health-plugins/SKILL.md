---
created: 2026-02-04
modified: 2026-04-15
reviewed: 2026-04-15
user-invocable: false
description: Diagnose and fix plugin registry issues including orphaned entries and project-scope conflicts (addresses Claude Code issue #14202)
allowed-tools: Bash(bash *), Read, Write, Edit, Glob, Grep, TodoWrite, AskUserQuestion
args: "[--fix] [--dry-run] [--plugin <name>]"
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
- Current project has plugins: !`find . -maxdepth 2 -path '*/.claude-plugin/plugin.json' -type f`
- Project settings exists: !`find . -maxdepth 1 -name '.claude/settings.json'`
- Project plugins dir: !`find . -maxdepth 1 -type d -name '.claude-plugin'`

## Background: Issue #14202

When a plugin is installed with `--scope project` in one project, other projects incorrectly show the plugin as "(installed)" in the Marketplaces view. This happens because:

1. The plugin registry at `~/.claude/plugins/installed_plugins.json` stores `projectPath` for project-scoped installs
2. The Marketplaces view only checks if a plugin key exists, not whether it's installed for the *current* project
3. The install command refuses to install because it thinks the plugin already exists

**Impact**: Users cannot install the same plugin across multiple projects with project-scope isolation.

## Parameters

Parse these from `$ARGUMENTS`:

| Parameter | Description |
|-----------|-------------|
| `--fix` | Apply fixes to the plugin registry |
| `--dry-run` | Show what would be fixed without making changes |
| `--plugin <name>` | Check/fix a specific plugin only |

## Execution

Execute this plugin registry diagnostic by running the scripts below. Pass `--plugin <name>` through from `$ARGUMENTS` when specified.

### Step 1: Diagnose the registry

```bash
bash "${CLAUDE_SKILL_DIR}/scripts/check-registry.sh" --home-dir "$HOME" --project-dir "$(pwd)" [--plugin <name>] [--verbose]
```

Parse the `STATUS=`, `PLUGIN_COUNT=`, `ORPHANED_ENTRIES=`, and `ISSUES:` lines from output. The `=== PLUGINS ===` section lists each installed plugin with scope, version, source, and projectPath.

### Step 2: Report findings

Print a structured diagnostic report summarising:

1. Registry location, validity, and plugin counts (total / global / project-scoped)
2. Orphaned entries (projectPath directory missing) with severity and suggested fix
3. Plugins enabled in settings but not in the registry
4. Plugins from other projects (INFO only, shown with `--verbose`)

Use the `ISSUES:` lines as the authoritative list of problems.

### Step 3: Apply fixes (if --fix)

If `$ARGUMENTS` contains `--fix`:

1. Confirm with the user (via `AskUserQuestion`) which orphaned plugins to remove, unless `--dry-run` is also set.
2. Run the fix script:

   ```bash
   bash "${CLAUDE_SKILL_DIR}/scripts/fix-registry.sh" --home-dir "$HOME" --project-dir "$(pwd)" [--plugin <name>] [--dry-run]
   ```

   The script creates a timestamped backup at `~/.claude/plugins/installed_plugins.json.backup.<UTC-timestamp>` before modifying the registry, validates the resulting JSON, and aborts safely on any error.
3. Parse `STATUS=`, `REMOVED=`, `REMOVED_COUNT=`, and `BACKUP_PATH=` lines to report what changed.

### Step 4: Handle "plugin needed in current project"

When a plugin exists in the registry under a different `projectPath` and the user wants it available in the current project, use `AskUserQuestion` to confirm, then:

1. Add a new entry to `.claude/settings.json` under `enabledPlugins` using the `Edit` tool.
2. Remind the user to run `/plugin install` via the Claude Code UI for proper registry registration.

### Step 5: Verify the fix

After applying fixes, re-run Step 1 and confirm the issue count has dropped. Remind the user to restart Claude Code for changes to take effect.

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
| Diagnose only (script) | `bash "${CLAUDE_SKILL_DIR}/scripts/check-registry.sh" --home-dir "$HOME" --project-dir "$(pwd)"` |
| Fix only (script) | `bash "${CLAUDE_SKILL_DIR}/scripts/fix-registry.sh" --home-dir "$HOME" --project-dir "$(pwd)"` |

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
