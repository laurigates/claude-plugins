---
model: haiku
created: 2026-02-04
modified: 2026-02-04
reviewed: 2026-02-04
description: Run a comprehensive diagnostic scan of Claude Code configuration including plugins, settings, hooks, and MCP servers
allowed-tools: Bash(test *), Bash(cat *), Bash(ls *), Bash(jq *), Bash(head *), Read, Glob, Grep, TodoWrite
argument-hint: "[--fix] [--verbose]"
---

# /health:check

Run a comprehensive diagnostic scan of your Claude Code environment. Identifies issues with plugin registry, settings files, hooks configuration, and MCP servers.

## Context

- User home: !`echo $HOME`
- Current project: !`pwd`
- Plugin registry exists: !`test -f ~/.claude/plugins/installed_plugins.json && echo "yes"`
- User settings exists: !`test -f ~/.claude/settings.json && echo "yes"`
- Project settings exists: !`test -f .claude/settings.json && echo "yes"`
- Local settings exists: !`test -f .claude/settings.local.json && echo "yes"`

## Parameters

| Parameter | Description |
|-----------|-------------|
| `--fix` | Attempt to automatically fix identified issues |
| `--verbose` | Show detailed diagnostic information |

## Workflow

### Phase 1: Plugin Registry Check

1. Read `~/.claude/plugins/installed_plugins.json` if it exists
2. For each installed plugin, check:
   - If `projectPath` is set, verify the directory exists
   - Flag orphaned entries (projectPath points to deleted directory)
   - Flag potential scope conflicts (same plugin installed globally and per-project)
3. Check if current project has plugins that show as "installed" but aren't active here

### Phase 2: Settings Files Check

1. Validate JSON syntax in all settings files:
   - `~/.claude/settings.json` (user-level)
   - `.claude/settings.json` (project-level)
   - `.claude/settings.local.json` (local overrides)
2. Check for common issues:
   - Invalid permission patterns
   - Conflicting allow/deny rules
   - Deprecated settings

### Phase 3: Hooks Configuration Check

1. Check for hooks in settings files
2. Validate hook command paths exist
3. Check for timeout configurations
4. Identify potential hook conflicts

### Phase 4: MCP Server Check

1. Look for MCP configuration in:
   - `.claude/settings.json`
   - `.mcp.json`
   - Plugin-provided MCP configs
2. Validate server command paths
3. Check for missing environment variables

### Phase 5: Generate Report

Output a diagnostic report:

```
Claude Code Health Check
========================
Project: <current-directory>
Date: <timestamp>

Plugin Registry
---------------
Status: [OK|WARN|ERROR]
- Installed plugins: N
- Project-scoped: N
- Orphaned entries: N
- Issues: <details if any>

Settings Files
--------------
Status: [OK|WARN|ERROR]
- User settings: [OK|MISSING|INVALID]
- Project settings: [OK|MISSING|INVALID]
- Local settings: [OK|MISSING|N/A]
- Permission patterns: N configured
- Issues: <details if any>

Hooks
-----
Status: [OK|WARN|ERROR|N/A]
- Configured hooks: N
- Issues: <details if any>

MCP Servers
-----------
Status: [OK|WARN|ERROR|N/A]
- Configured servers: N
- Issues: <details if any>

Summary
-------
[All checks passed | N issues found]

Recommended Actions:
1. <action if needed>
2. <action if needed>

Run `/health:plugins --fix` to fix plugin registry issues.
Run `/health:settings --fix` to fix settings issues.
```

## Known Issues Database

Reference these known Claude Code issues when diagnosing:

| Issue | Symptoms | Solution |
|-------|----------|----------|
| #14202 | Plugin shows "installed" but not active in project | Run `/health:plugins --fix` |
| Orphaned projectPath | Plugin was installed for deleted project | Run `/health:plugins --fix` |
| Invalid JSON | Settings file won't load | Validate and fix JSON syntax |
| Hook timeout | Commands hang or fail silently | Check hook timeout settings |

## Flags

| Flag | Description |
|------|-------------|
| `--fix` | Attempt automatic fixes for identified issues |
| `--verbose` | Include detailed diagnostic output |

## See Also

- `/health:plugins` - Detailed plugin registry diagnostics
- `/health:settings` - Settings file validation
- `/health:hooks` - Hooks configuration check
- `/health:mcp` - MCP server diagnostics
