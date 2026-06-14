# Custom Agent Definitions — Reference

Supporting material for [`custom-agent-definitions`](SKILL.md). Loaded on demand.
The decision tables, schema overview, field reference, and best practices live in
`SKILL.md`; this file carries the full worked YAML examples and configuration
snippets.

## Isolated research agent (`context: fork`)

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

**When to use `context: fork`:** exploratory research that shouldn't pollute main
context, parallel investigations with conflicting approaches, isolated
experiments, background tasks that run independently.

## Read-only explorer (`disallowedTools`)

```yaml
---
name: read-only-explorer
description: Explore codebase without modifications
model: sonnet
allowed-tools: Bash, Read, Grep, Glob
disallowedTools: Write, Edit, NotebookEdit
---

# Read-Only Explorer

Explore and analyze code. Do not make any modifications.
```

**When to use `disallowedTools`:** read-only agents that explore but don't modify,
restricting dangerous capabilities (Bash execution), sandboxing agents for
specific tasks, security-sensitive contexts.

## Complete example: security auditor

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

## Defining agents in plugins

Plugins define custom agents in their `agents/` directory; each file follows the
same YAML frontmatter + markdown body structure:

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

## Using custom agents

### Via Task tool

```
Agent tool with subagent_type="security-auditor" for security analysis.
```

### Via delegation

```bash
/delegate Audit auth module for security issues
```

The delegation system matches tasks to appropriate custom agents.

## Common patterns

### Read-only research agent

```yaml
context: fork
allowed-tools: Read, Grep, Glob, WebSearch, WebFetch
disallowedTools: Bash, Write, Edit
```

### Safe code executor

```yaml
allowed-tools: Bash, Read
disallowedTools: Write, Edit
```

### Documentation writer

```yaml
allowed-tools: Read, Write, Edit, Grep, Glob
disallowedTools: Bash
```

### Full-power developer

```yaml
allowed-tools: Bash, Read, Write, Edit, Grep, Glob, TodoWrite
```

## Best-practice snippets

Principle of least privilege — grant only the tools the agent needs:

```yaml
# Good: Minimal tools for the task
allowed-tools: Read, Grep, Glob

# Avoid: Overly permissive
allowed-tools: Bash, Read, Write, Edit, Grep, Glob, WebSearch, WebFetch
```

Combine an explicit whitelist with a safety blacklist:

```yaml
allowed-tools: Bash, Read, Grep
disallowedTools: Write, Edit
```

Clear, multi-line description:

```yaml
description: |
  Security auditor for identifying vulnerabilities in authentication
  and authorization code. Reports findings without modifying code.
```
