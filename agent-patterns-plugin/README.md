# Agent Patterns Plugin

Multi-agent coordination and orchestration patterns for Claude Code.

## Overview

This plugin provides comprehensive patterns, commands, and skills for coordinating multiple AI agents in complex workflows. It enables efficient parallel execution, proper dependency management, and transparent file-based coordination.

## Features

### Commands

#### `/delegate`
Intelligently delegate tasks to specialized agents with automatic task-agent matching and parallel execution.

**Usage:**
```bash
/delegate Review the auth module for security issues, update the API documentation, and run the test suite
```

**Features:**
- Automatic task parsing (comma-separated, numbered lists, natural language)
- Intelligent agent matching based on task patterns
- Parallel execution for independent tasks
- Sequential execution for dependent tasks
- Consolidated result reporting

#### `/check-negative-examples`
Scan skills, commands, and agent prompts for negative framing and suggest positive alternatives.

**Usage:**
```bash
/check-negative-examples
```

**Features:**
- Detects negative instructions ("don't", "never", "avoid")
- Suggests positive reframings
- Follows Anthropic's prompt engineering best practices
- Prevents the "pink elephant problem"

#### `/meta:audit`
Audit Claude subagent configurations for completeness, security, and best practices.

**Usage:**
```bash
/meta:audit [--verbose]
```

**Features:**
- Validates frontmatter fields
- Analyzes tool assignments for security
- Checks privilege levels
- Generates comprehensive audit reports

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

#### `/workflow:primer`
Generate a continuation primer for agent handoff with todo list and context.

**Usage:**
```bash
/workflow:primer
```

**Features:**
- Current state summary of accomplished work
- Remaining todo list in priority order
- Key context for continuation
- Active files being worked on
- Known blockers and issues

### Hooks

#### `orchestrator-enforcement.sh`
PreToolUse hook that enforces the orchestrator pattern - orchestrators investigate and delegate, subagents implement.

**Tool Access:**

| Category | Orchestrator | Subagent |
|----------|--------------|----------|
| Delegation (Task) | Allowed | Allowed |
| Investigation (Read, Grep, Glob) | Allowed | Allowed |
| Implementation (Edit, Write) | Blocked | Allowed |
| Git read (status, log, diff) | Allowed | Allowed |
| Git write (add, commit, push) | Blocked | Allowed |

**Environment variables:**
- `ORCHESTRATOR_BYPASS=1` - Disable enforcement
- `CLAUDE_IS_SUBAGENT=1` - Grant full access to subagents

### Skills

#### `delegation-first`
Default behavior pattern that automatically delegates implementation tasks to specialized sub-agents.

**When to use:**
- Any implementation request (writing code, fixing bugs, running tests)
- Investigation and debugging tasks
- Code review and security audits
- Documentation generation

**Core Philosophy:**
- **Main Claude = Architect** - focuses on design, strategy, user interaction
- **Sub-Agents = Implementers** - handle code, tests, debugging with fresh context

**Benefits:**
- Preserves main conversation for high-level design
- Sub-agents have dedicated context windows (no noise accumulation)
- Parallel execution for independent tasks
- Better results through specialized expertise

#### `agent-coordination-patterns`
Coordination patterns for sequential, parallel, and iterative agent workflows.

**When to use:**
- Designing multi-agent workflows
- Coordinating agent handoffs
- Planning agent dependencies
- Building complex agent pipelines

**Patterns:**
- **Sequential Coordination**: Linear agent chains with handoffs
- **Parallel Coordination**: Simultaneous independent work streams
- **Iterative Coordination**: Feedback loops and refinement cycles
- **Hybrid Coordination**: Combined patterns for complex workflows

#### `agent-file-coordination`
File-based context sharing for multi-agent workflows.

**When to use:**
- Setting up multi-agent workflows
- Reading/writing agent context files
- Monitoring agent progress
- Debugging agent coordination

**File Structures:**
- `current-workflow.md` - Active workflow status
- `agent-queue.md` - Agent scheduling and dependencies
- `inter-agent-context.json` - Structured cross-agent data
- `{agent}-output.md` - Standardized agent results
- `{agent}-progress.md` - Real-time progress updates

#### `multi-agent-workflows`
Proven workflow templates for complex multi-agent coordination.

**When to use:**
- Planning complex projects requiring multiple specialties
- Designing API development workflows
- Setting up infrastructure workflows
- Coordinating code quality reviews

**Workflow Templates:**
- API Development Workflow
- Infrastructure Setup Workflow
- Code Quality Review Workflow
- Research & Documentation Workflow
- UX Implementation Workflow

#### `command-context-patterns`
Best practices for writing safe context expressions in slash command files.

**When to use:**
- Creating slash command files
- Writing context sections with backtick expressions
- Debugging command execution failures

**Key Patterns:**
- Use `find` instead of `ls` for file checks
- Avoid chained operations (`&&`, `||`)
- No conditionals in context expressions
- Commands that always exit 0

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

#### `agent-handoff-markers`
Standardized inline markers for inter-agent communication.

**When to use:**
- Creating handoff annotations for other agents
- Scanning for pending work from upstream agents
- Coordinating asynchronous agent workflows
- User mentions @AGENT-HANDOFF-MARKER or agent coordination

**Marker Format:**
```typescript
// @AGENT-HANDOFF-MARKER(target-agent) {
//   type: "category",
//   context: "what this code does",
//   needs: ["requirement 1", "requirement 2"],
//   priority: "blocking|enhancement"
// }
```

**Benefits:**
- Asynchronous agent coordination
- Traceability of inter-agent requests
- Inline documentation of intent
- CI/CD integration potential

#### `claude-hooks-configuration`
Configure Claude Code lifecycle hooks with proper timeout settings.

**When to use:**
- Fixing "Hook cancelled" errors during session management
- Configuring SessionStart, SessionEnd, or Stop hooks
- Optimizing hook scripts for faster execution
- Setting custom timeout values for hooks

**Features:**
- Hook timeout configuration patterns
- Script optimization guidance
- Starship timeout fixes (related issue)
- Best practices for hook development

**Common Fix:**
```json
{
  "hooks": {
    "SessionEnd": [{
      "matcher": "",
      "hooks": [{
        "type": "command",
        "command": "~/.claude/session-logger.sh",
        "timeout": 120
      }]
    }]
  }
}
```

#### `custom-agent-definitions`
Define and configure custom agents with context forking and tool restrictions.

**When to use:**
- Creating custom agent types beyond built-in agents
- Configuring isolated agent contexts with `context: fork`
- Restricting agent capabilities with `disallowedTools`
- Setting up specialized agents for specific workflows

**Key Fields:**
```yaml
---
name: security-auditor
description: Security-focused code review
model: sonnet
context: fork
allowed-tools: Read, Grep, Glob
disallowedTools: Bash, Write, Edit
---
```

**Features:**
- Context forking for isolated agent execution
- Tool whitelisting (`allowed-tools`)
- Tool blacklisting (`disallowedTools`)
- Custom agent definitions in plugins

## Installation

### Via Plugin System

1. Clone or copy this plugin to your Claude plugins directory:
```bash
cp -r agent-patterns-plugin ~/.claude/plugins/
```

2. The plugin will be automatically loaded by Claude Code

### Manual Installation

Copy individual files to your `.claude/` directory:

```bash
# Commands
cp commands/delegate.md ~/.claude/commands/
cp commands/check-negative-examples.md ~/.claude/commands/
cp commands/meta/*.md ~/.claude/commands/meta/

# Skills
cp -r skills/* ~/.claude/skills/
```

## Usage Examples

### Delegating Multiple Tasks
```bash
/delegate Review security in auth.py, update API docs, and run tests
```

This will:
1. Launch `security-audit` agent for security review
2. Launch `documentation` agent for API docs
3. Launch `test-runner` agent for tests
4. All three run in parallel
5. Results consolidated in a single report

### Checking for Negative Framing
```bash
/check-negative-examples
```

Scans all skills and commands, finds patterns like "don't do X", suggests positive alternatives like "prefer Y".

### Auditing Agent Configurations
```bash
/meta:audit --verbose
```

Generates comprehensive audit report with security assessment and recommendations.

## Design Principles

### Parallel-First Execution
The plugin prioritizes parallel execution whenever possible:
- Independent tasks launch simultaneously
- Sequential execution only when dependencies exist
- Maximizes throughput and efficiency

### File-Based Transparency
Agent coordination uses human-readable files:
- Easy to inspect and debug
- Clear progress visibility
- Version control friendly

### Positive Framing
Follows Anthropic's guidance to avoid negative instructions:
- Tell agents what TO do
- Describe desired behavior explicitly
- Avoid "pink elephant problem"

### Convention Over Configuration
Uses established patterns and best practices:
- Standard file structures
- Consistent naming conventions
- Proven workflow templates

## Integration

This plugin integrates with:
- **Task Tool**: For agent delegation
- **TodoWrite**: For task tracking
- **Glob/Grep**: For pattern searching
- **Read/Write/Edit**: For file operations

## License

MIT License - See LICENSE file for details

## Contributing

Contributions welcome! Please follow existing patterns and conventions.

## Claude Agent SDK Migration

As of Claude Code 2.1.7, the legacy SDK entrypoint has been removed. If you're building custom Claude applications programmatically, migrate to the official package:

```bash
# Install the official SDK
npm install @anthropic-ai/claude-agent-sdk
```

**Migration notes:**
- Legacy entrypoints have been removed
- Use `@anthropic-ai/claude-agent-sdk` for all new agent development
- Existing integrations should update their imports

See the [Claude Agent SDK documentation](https://docs.anthropic.com/claude/docs/claude-agent-sdk) for migration guidance.

## References

- [Anthropic Prompt Engineering](https://docs.anthropic.com/claude/docs/prompt-engineering)
- [Claude Code Documentation](https://docs.claude.com/claude-code)
- [Claude Agent SDK](https://docs.anthropic.com/claude/docs/claude-agent-sdk)
- [Multi-Agent Systems Patterns](https://en.wikipedia.org/wiki/Multi-agent_system)

## Version

1.0.0 - Initial release
