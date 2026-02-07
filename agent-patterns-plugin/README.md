# Agent Patterns Plugin

Agent configuration utilities for Claude Code — project assimilation, config auditing, teammate definitions, MCP management, and hooks configuration.

## Overview

This plugin provides utilities for configuring and managing Claude Code agents, MCP servers, and hooks. Orchestration features previously in this plugin have been replaced by Claude Code's native [agent teams](https://code.claude.com/docs/en/agent-teams) feature.

## Features

### Hooks

#### `pre-compact-primer.sh`
PreCompact hook that preserves context during long single-session work. Fires before context compaction to inject a continuation primer with current state, active files, and remaining tasks.

### Skills

#### `/meta:assimilate`
Analyze and assimilate project-specific Claude configurations into user-scoped configs.

**Usage:**
```bash
/meta:assimilate <project-path>
```

**Features:**
- Examines project `.claude/` directories
- Identifies reusable patterns
- Suggests generalizations for user-scoped usage

#### `/meta:audit`
Audit Claude agent and teammate configurations for completeness, security, and best practices.

**Usage:**
```bash
/meta:audit [--verbose]
```

**Features:**
- Validates frontmatter fields
- Analyzes tool assignments for security
- Checks privilege levels
- Generates comprehensive audit reports

#### `custom-agent-definitions`
Define and configure custom agents and teammate templates with context forking and tool restrictions.

**When to use:**
- Creating custom agent or teammate definitions
- Configuring isolated agent contexts with `context: fork`
- Restricting agent capabilities with `disallowedTools`
- Setting up specialized teammates for team workflows

#### `mcp-management`
Intelligent MCP server installation and management.

**When to use:**
- Configuring MCP servers for a project
- Analyzing project context for MCP recommendations
- Setting up environment variables for MCP servers

**Features:**
- Project context analysis
- Intelligent server suggestions
- Project-scoped `.mcp.json` management
- Environment variable validation

#### `claude-hooks-configuration`
Configure Claude Code lifecycle hooks with proper timeout settings.

**When to use:**
- Fixing "Hook cancelled" errors during session management
- Configuring SessionStart, SessionEnd, or Stop hooks
- Optimizing hook scripts for faster execution
- Setting custom timeout values for hooks

## Migration from Orchestration Patterns

The following skills have been removed in favor of native agent teams:

| Removed Skill | Native Replacement |
|---------------|-------------------|
| `delegate` | Native delegate mode |
| `delegation-first` | Native delegate mode |
| `agent-coordination-patterns` | Shared task list + messaging |
| `agent-file-coordination` | Native file-locking |
| `agent-handoff-markers` | Native inter-agent messaging |
| `workflow-primer` | Per-teammate context windows |
| `multi-agent-workflows` | Agent teams configuration |
| `agentic-patterns-source` | Agent teams docs |
| `command-context-patterns` | Agent teams context handling |
| `check-negative-examples` | Plan approval gates |
| `wip-todo` | Shared task list |
| `orchestrator-enforcement` hook | Native delegate mode |

See [ADR-0015](docs/adrs/0015-agent-teams-adoption.md) for the decision rationale.

## Installation

### Via Plugin System

1. Clone or copy this plugin to your Claude plugins directory:
```bash
cp -r agent-patterns-plugin ~/.claude/plugins/
```

2. The plugin will be automatically loaded by Claude Code.

## License

MIT License - See LICENSE file for details.
