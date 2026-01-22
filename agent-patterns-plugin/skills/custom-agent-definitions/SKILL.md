---
model: opus
name: custom-agent-definitions
description: |
  Define and configure custom agents in Claude Code. Covers context forking,
  agent field specifications, and disallowedTools restrictions. Use when
  creating custom agent types, configuring agent isolation, or restricting
  agent capabilities.
allowed-tools: Bash, Read, Write, Edit, Glob, Grep, TodoWrite
created: 2026-01-20
modified: 2026-01-20
reviewed: 2026-01-20
---

# Custom Agent Definitions

Expert knowledge for defining and configuring custom agents in Claude Code.

## Core Concepts

**Custom Agents** allow you to define specialized agent types beyond the built-in ones (Explore, Plan, Bash, etc.). Each custom agent can have its own model, tools, and context configuration.

## Agent Definition Schema

Custom agents are defined in `.claude/agents/` or via plugin agent directories.

### Basic Structure

```yaml
---
name: my-custom-agent
description: What this agent does
model: sonnet
allowed-tools: Bash, Read, Grep, Glob
---

# Agent System Prompt

Instructions and context for the agent...
```

### Context Forking

The `context` field controls how the agent's context relates to the parent conversation:

| Value | Behavior |
|-------|----------|
| `fork` | Creates an independent context copy - agent sees parent history but changes don't affect parent |
| (default) | Agent shares context with parent and can see/modify conversation state |

**Example: Isolated Research Agent**

```yaml
---
name: research-agent
description: Research questions without modifying main context
model: sonnet
context: fork
allowed-tools: WebSearch, WebFetch, Read
---

# Research Agent

You are a research specialist. Search for information and provide findings.
Your research doesn't affect the main conversation context.
```

**When to use `context: fork`:**
- Exploratory research that shouldn't pollute main context
- Parallel investigations with potentially conflicting approaches
- Isolated experiments or testing
- Background tasks that run independently

### Agent Field for Delegation

The `agent` field specifies which agent type to use when delegating via the Task tool:

```yaml
---
name: code-review-workflow
description: Comprehensive code review
agent: security-auditor
allowed-tools: Read, Grep, Glob, TodoWrite
---
```

This allows commands and skills to specify a preferred agent type for delegation.

### Disallowed Tools (Restrictions)

The `disallowedTools` field explicitly prevents an agent from using certain tools:

```yaml
---
name: read-only-explorer
description: Explore codebase without modifications
model: haiku
allowed-tools: Bash, Read, Grep, Glob
disallowedTools: Write, Edit, NotebookEdit
---

# Read-Only Explorer

Explore and analyze code. Do not make any modifications.
```

**Disallowed Tools vs Allowed Tools:**

| Field | Purpose | Behavior |
|-------|---------|----------|
| `allowed-tools` | Whitelist of permitted tools | Agent can ONLY use these tools |
| `disallowedTools` | Blacklist of forbidden tools | Agent can use all tools EXCEPT these |

**When to use `disallowedTools`:**
- Creating read-only agents that can explore but not modify
- Restricting dangerous capabilities (Bash execution)
- Sandboxing agents for specific tasks
- Security-sensitive contexts

### Complete Example

```yaml
---
name: security-auditor
description: Security-focused code review agent
model: sonnet
context: fork
allowed-tools: Read, Grep, Glob, WebSearch, TodoWrite
disallowedTools: Bash, Write, Edit
created: 2026-01-20
modified: 2026-01-20
reviewed: 2026-01-20
---

# Security Auditor Agent

You are a security auditor. Analyze code for vulnerabilities.

## Capabilities
- Read and analyze source code
- Search for security patterns
- Research known vulnerabilities
- Track findings in todo list

## Restrictions
- Cannot execute code (no Bash)
- Cannot modify files (no Write/Edit)
- Work in isolated context

## Focus Areas
1. SQL injection vulnerabilities
2. XSS vulnerabilities
3. Authentication/authorization flaws
4. Secrets/credentials in code
5. Insecure dependencies
```

## Defining Agents in Plugins

Plugins can define custom agents in their `agents/` directory:

```
my-plugin/
├── .claude-plugin/
│   └── plugin.json
├── agents/
│   ├── security-auditor.md
│   ├── performance-analyzer.md
│   └── accessibility-checker.md
└── skills/
    └── ...
```

Each agent file follows the same YAML frontmatter + markdown body structure.

## Using Custom Agents

### Via Task Tool

```
Task tool with subagent_type="security-auditor" for security analysis.
```

### Via Delegation

```bash
/delegate Audit auth module for security issues
```

The delegation system matches tasks to appropriate custom agents.

## Best Practices

### 1. Principle of Least Privilege
Only grant tools the agent actually needs:
```yaml
# Good: Minimal tools for the task
allowed-tools: Read, Grep, Glob

# Avoid: Overly permissive
allowed-tools: Bash, Read, Write, Edit, Grep, Glob, WebSearch, WebFetch
```

### 2. Use Context Forking for Isolation
```yaml
# Good: Isolated exploratory work
context: fork
```

### 3. Combine Allowed and Disallowed
```yaml
# Explicit whitelist with safety blacklist
allowed-tools: Bash, Read, Grep
disallowedTools: Write, Edit
```

### 4. Clear Agent Descriptions
```yaml
description: |
  Security auditor for identifying vulnerabilities in authentication
  and authorization code. Reports findings without modifying code.
```

### 5. Model Selection
| Use Case | Model |
|----------|-------|
| Quick analysis | haiku |
| Standard work | sonnet |
| Complex reasoning | opus |

## Agent Configuration Fields Reference

| Field | Type | Description |
|-------|------|-------------|
| `name` | string | Agent identifier |
| `description` | string | What the agent does |
| `model` | string | Model to use (haiku, sonnet, opus) |
| `context` | string | Context mode: `fork` or default |
| `allowed-tools` | list | Tools the agent can use |
| `disallowedTools` | list | Tools the agent cannot use |
| `created` | date | Creation date |
| `modified` | date | Last modification date |
| `reviewed` | date | Last review date |

## Common Patterns

### Read-Only Research Agent
```yaml
context: fork
allowed-tools: Read, Grep, Glob, WebSearch, WebFetch
disallowedTools: Bash, Write, Edit
```

### Safe Code Executor
```yaml
allowed-tools: Bash, Read
disallowedTools: Write, Edit
```

### Documentation Writer
```yaml
allowed-tools: Read, Write, Edit, Grep, Glob
disallowedTools: Bash
```

### Full-Power Developer
```yaml
allowed-tools: Bash, Read, Write, Edit, Grep, Glob, TodoWrite
```

## Agentic Optimizations

| Context | Configuration |
|---------|---------------|
| Exploratory research | `context: fork`, `model: haiku` |
| Security analysis | `context: fork`, `disallowedTools: Bash, Write, Edit` |
| Quick lookups | `model: haiku`, minimal tools |
| Complex implementation | `model: sonnet`, full tools |

## Quick Reference

### Context Modes
| Mode | Isolation | Use Case |
|------|-----------|----------|
| (default) | Shared | Normal workflows |
| `fork` | Isolated | Research, experiments |

### Tool Restriction Patterns
| Pattern | Fields |
|---------|--------|
| Whitelist only | `allowed-tools: Tool1, Tool2` |
| Blacklist only | `disallowedTools: Tool1, Tool2` |
| Combined | Both fields specified |
