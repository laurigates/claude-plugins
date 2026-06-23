---
name: custom-agent-definitions
description: Write and configure custom agent definitions in Claude Code agents/ directory. Use when creating an agent .md file, defining a specialized agent, or configuring agent tools.
user-invocable: false
allowed-tools: Bash(cat *), Read, Write, Edit, Glob, Grep, TodoWrite
created: 2026-01-20
modified: 2026-06-14
reviewed: 2026-06-14
---

# Custom Agent Definitions

Expert knowledge for defining and configuring custom agents in Claude Code.

For full worked YAML examples (isolated research agent, read-only explorer,
complete security auditor, plugin layout, common patterns), see
[REFERENCE.md](REFERENCE.md).

## When to Use This Skill

| Use this skill when... | Use agent-teams instead when... |
|---|---|
| Authoring a new `.md` agent definition file in `.claude/agents/` | Spawning multiple already-defined agents that coordinate as a team |
| Configuring a single agent's `model`, `allowed-tools`, or `context: fork` | Setting up a lead/teammate architecture with a shared task list |
| Constraining tool access for a specialised read-only or write-restricted agent | Sequencing parallel work across worktrees (see parallel-agent-dispatch) |
| Writing the system prompt that defines what one agent does | Auditing existing agent definitions for security (see meta-audit) |

## Core Concepts

**Custom agents** let you define specialized agent types beyond the built-in
ones (Explore, Plan, Bash, etc.). Each can have its own model, tools, and
context configuration. They are defined in `.claude/agents/` or via plugin
`agents/` directories, with YAML frontmatter + a markdown system prompt:

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

## Key Fields

### Context Forking

| Value | Behavior |
|-------|----------|
| `fork` | Independent context copy — agent sees parent history but changes don't affect parent |
| (default) | Agent shares context with parent and can see/modify conversation state |

Use `fork` for exploratory research, parallel investigations, and isolated
experiments. See [REFERENCE.md → Isolated research agent](REFERENCE.md#isolated-research-agent-context-fork).

### Tool Access (allowed vs disallowed)

| Field | Purpose | Behavior |
|-------|---------|----------|
| `allowed-tools` | Whitelist of permitted tools | Agent can ONLY use these tools |
| `disallowedTools` | Blacklist of forbidden tools | Agent can use all tools EXCEPT these |

Use `disallowedTools` for read-only agents, restricting dangerous capabilities,
and sandboxing. The two combine — an explicit whitelist plus a safety blacklist.
See [REFERENCE.md → Read-only explorer](REFERENCE.md#read-only-explorer-disallowedtools).

### Agent Field for Delegation

The `agent` field specifies which agent type to use when delegating via the Agent
tool, letting commands and skills name a preferred agent type:

```yaml
agent: security-auditor
```

## Agent Configuration Fields Reference

| Field | Type | Description |
|-------|------|-------------|
| `name` | string | Agent identifier |
| `description` | string | What the agent does |
| `model` | string | Model to use (sonnet, opus) |
| `context` | string | Context mode: `fork` or default |
| `permissionMode` | string | `default`, `acceptEdits`, `dontAsk`, `bypassPermissions`, or `plan` |
| `maxTurns` | number | Maximum agentic turns before agent stops |
| `background` | bool | Set `true` to always run as a background task |
| `memory` | string | Persistent memory scope: `user`, `project`, or `local` |
| `skills` | list | Skill names to preload into agent context at startup |
| `mcpServers` | list | MCP server names available to this agent |
| `tools` | list | Tools the agent can use (in agents/ dir; use `allowed-tools` in skills) |
| `disallowedTools` | list | Tools the agent cannot use |
| `created` / `modified` / `reviewed` | date | Lifecycle dates |

## Best Practices

1. **Principle of least privilege** — grant only the tools the agent needs.
2. **Use `context: fork` for isolation** — exploratory work shouldn't pollute main context.
3. **Combine allowed + disallowed** — explicit whitelist with a safety blacklist.
4. **Clear descriptions** — describe what the agent does and its boundaries.
5. **Model selection** — `sonnet` for development workflows, `opus` for deep
   reasoning/analysis. (See `.claude/rules/agent-and-tool-selection.md` for the
   repo's Opus-for-subagents guidance.)
6. **Report failures loudly** — a dispatched agent that hits a wall must say so
   in its final message, never a one-word summary like `Terminal.` / `Done.` /
   `Stopped.` On a blocker it should commit and push its in-progress work, open a
   draft PR, and state exactly what stopped it and which tools were denied. A
   one-word surrender is indistinguishable from success to the orchestrator, so
   the work is silently cleaned up and lost (issue
   [#1422](https://github.com/laurigates/claude-plugins/issues/1422)). See
   `parallel-agent-dispatch` → "Loud-failure contract" for the dispatch-prompt
   form every brief should carry.

7. **Prefer a Skill-less agentType for read-only fan-out** — an agent that
   only reads files and emits structured output should NOT carry the `Skill`
   tool. Every `Skill`-bearing agent pays a ~25k-token `skill_listing` +
   `deferred_tools_delta` context tax before its first tool call, which can push
   read-heavy fan-out subagents over their context window. Use a lean read-only
   agent (e.g. `agents-plugin:review`) instead. See
   `parallel-agent-dispatch` → "Skill-less agentType for Read-Only Fan-Out"
   (issues
   [#1549](https://github.com/laurigates/claude-plugins/issues/1549) /
   [#1550](https://github.com/laurigates/claude-plugins/issues/1550)).

Worked YAML for each practice is in [REFERENCE.md → Best-practice snippets](REFERENCE.md#best-practice-snippets).

## Agentic Optimizations

| Context | Configuration |
|---------|---------------|
| Exploratory research | `context: fork`, minimal read-only tools |
| Security analysis | `context: fork`, `disallowedTools: Bash, Write, Edit` |
| Quick lookups | minimal tools |
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

## Related

- [REFERENCE.md](REFERENCE.md) — full worked YAML examples and snippets
- `agent-teams` — multi-agent coordination via the implicit team
- `parallel-agent-dispatch` — worktree preflight, scope budgets, loud-failure contract
- `meta-audit` — auditing existing agent definitions for security/completeness
- `.claude/rules/agent-development.md` — agent lifecycle and field semantics
