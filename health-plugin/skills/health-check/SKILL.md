---
model: haiku
created: 2026-02-04
modified: 2026-02-10
reviewed: 2026-02-04
description: Run a comprehensive diagnostic scan of Claude Code configuration including plugins, settings, hooks, and MCP servers
allowed-tools: Bash(test *), Bash(jq *), Bash(head *), Bash(find *), Read, Glob, Grep, TodoWrite
argument-hint: "[--fix] [--verbose]"
name: health-check
---

# /health:check

Run a comprehensive diagnostic scan of your Claude Code environment. Identifies issues with plugin registry, settings files, hooks configuration, and MCP servers.

## When to Use This Skill

| Use this skill when... | Use another approach when... |
|------------------------|------------------------------|
| Running comprehensive Claude Code diagnostics | Checking specific component only (use `/health:plugins`, `/health:settings`) |
| Troubleshooting general Claude Code issues | Plugin registry issues only (use `/health:plugins --fix`) |
| Validating environment configuration | Auditing plugins for project fit (use `/health:audit`) |
| Identifying misconfigured settings or hooks | Just viewing settings (use Read tool on settings.json) |
| Quick health check before starting work | Need agentic optimization audit (use `/health:agentic-audit`) |

## Context

- User home: !`echo $HOME`
- Current project: !`pwd`
- Plugin registry exists: !`find ~/.claude/plugins -maxdepth 1 -name 'installed_plugins.json' 2>/dev/null`
- User settings exists: !`find ~/.claude -maxdepth 1 -name 'settings.json' 2>/dev/null`
- Project settings exists: !`find .claude -maxdepth 1 -name 'settings.json' 2>/dev/null`
- Local settings exists: !`find .claude -maxdepth 1 -name 'settings.local.json' 2>/dev/null`

## Parameters

| Parameter | Description |
|-----------|-------------|
| `--fix` | Attempt to automatically fix identified issues |
| `--verbose` | Show detailed diagnostic information |

## Execution

Execute this comprehensive health check:

### Step 1: Check the plugin registry

1. Read `~/.claude/plugins/installed_plugins.json` if it exists
2. For each installed plugin, verify:
   - If `projectPath` is set, confirm the directory exists
   - Flag orphaned entries (projectPath points to deleted directory)
   - Flag potential scope conflicts (same plugin installed globally and per-project)
3. Check if current project has plugins that show as "installed" but are not active here

### Step 2: Validate settings files

1. Validate JSON syntax in all settings files:
   - `~/.claude/settings.json` (user-level)
   - `.claude/settings.json` (project-level)
   - `.claude/settings.local.json` (local overrides)
2. Check for common issues: invalid permission patterns, conflicting allow/deny rules, deprecated settings

### Step 3: Check hooks configuration

1. Read hooks from settings files
2. Validate that hook command paths exist
3. Check timeout configurations
4. Identify potential hook conflicts

### Step 4: Check MCP server configuration

1. Look for MCP configuration in `.claude/settings.json`, `.mcp.json`, and plugin-provided MCP configs
2. Validate server command paths
3. Check for missing environment variables

### Step 5: Generate the diagnostic report

Print a structured report covering each check area (Plugin Registry, Settings Files, Hooks, MCP Servers) with status indicators (OK/WARN/ERROR), issue counts, and recommended actions. Use the report template from [REFERENCE.md](REFERENCE.md).

## Agentic Optimizations

| Context | Command |
|---------|---------|
| Quick health check | `/health:check` |
| Health check with auto-fix | `/health:check --fix` |
| Detailed diagnostics | `/health:check --verbose` |
| Check plugin registry exists | `test -f ~/.claude/plugins/installed_plugins.json && echo "exists" \|\| echo "missing"` |
| Validate settings JSON | `jq empty .claude/settings.json 2>&1` |
| List MCP servers | `jq -r '.mcpServers \| keys[]' .mcp.json 2>/dev/null` |

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
