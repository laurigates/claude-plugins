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

### Skills

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

## References

- [Anthropic Prompt Engineering](https://docs.anthropic.com/claude/docs/prompt-engineering)
- [Claude Code Documentation](https://docs.claude.com/claude-code)
- [Multi-Agent Systems Patterns](https://en.wikipedia.org/wiki/Multi-agent_system)

## Version

1.0.0 - Initial release
