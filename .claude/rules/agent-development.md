---
paths:
  - "**/agents/**"
---

# Agent Development (Claude Code 2.1.71+)

Patterns and standards for creating and configuring custom agents in Claude Code plugins.

> **Note (2.1.63)**: The `Task` tool was renamed to `Agent` tool. Existing `Task(...)` references in settings and agent definitions still work as aliases, but new code should use `Agent`.

## Agent vs Skill

| Use Agent When... | Use Skill When... |
|-------------------|-------------------|
| Task requires autonomous multi-step work | Task is a guided workflow with human oversight |
| Context isolation is needed | Context sharing is fine |
| Parallel execution with other agents | Sequential single-session work |
| Task produces self-contained output | Task collaborates with the main session |
| You want to protect the main context window | Main context can absorb the work |

## Agent File Structure

Agents live in `<plugin-name>/agents/<agent-name>.md`.

### Required Frontmatter

```yaml
---
name: agent-name
description: What this agent does and when to use it.
model: opus
tools: Glob, Grep, LS, Read, Edit, Write, Bash(npm *), TodoWrite
created: YYYY-MM-DD
modified: YYYY-MM-DD
reviewed: YYYY-MM-DD
---
```

### Optional Frontmatter Fields

```yaml
---
# ... required fields above ...
color: "#E53E3E"       # Hex color for UI display
context: fork          # Context isolation: 'fork' creates independent context copy
isolation: worktree    # Filesystem isolation: give agent its own git worktree
permissionMode: default  # Permission mode: default, acceptEdits, dontAsk, bypassPermissions, plan
maxTurns: 20           # Maximum agentic turns before agent stops
background: false      # Set true to always run as a background task
memory: user           # Persistent memory scope: user, project, or local
skills:                # Preload skill content into agent context at startup
  - api-conventions
  - error-handling-patterns
mcpServers:            # MCP servers available to this agent
  - slack
hooks:                 # Agent-scoped hooks (active only when agent is running)
  Stop:
    - matcher: ""
      hooks:
        - type: command
          command: "bash ${CLAUDE_PLUGIN_ROOT}/hooks/verify.sh"
          timeout: 30
---
```

> **Note**: Agent hooks defined with `Stop` are automatically converted to `SubagentStop` when the agent runs as a subagent, since subagents fire `SubagentStop` instead of `Stop`.

### Complete Field Reference

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `name` | string | Yes | Agent identifier (kebab-case) |
| `description` | string | Yes | Purpose and use cases for agent selection |
| `model` | string | Yes | `opus`, `sonnet`, `haiku`, or `inherit` |
| `tools` | comma-list | Yes | Tools the agent can use; use `Agent(name)` to restrict spawnable subagents |
| `context` | string | No | `fork` for isolated context (default: shared) |
| `isolation` | string | No | `worktree` to run agent in an isolated git worktree |
| `color` | string | No | Hex color for UI display |
| `permissionMode` | string | No | `default`, `acceptEdits`, `dontAsk`, `bypassPermissions`, or `plan` |
| `maxTurns` | number | No | Maximum agentic turns before agent stops |
| `background` | bool | No | Set `true` to always run as a background task |
| `memory` | string | No | Persistent memory scope: `user`, `project`, or `local` |
| `skills` | list | No | Skill names to preload into agent context at startup |
| `mcpServers` | list | No | MCP server names or inline configs available to this agent |
| `hooks` | object | No | Agent-scoped hooks (same schema as settings.json hooks) |
| `disallowedTools` | comma-list | No | Tools to deny even if in the inherited list |
| `created` | date | Recommended | Initial creation date |
| `modified` | date | Recommended | Last substantive change |
| `reviewed` | date | Recommended | Last verified against current docs |

### `tools` vs `allowed-tools`

| Field | Used In | Supports |
|-------|---------|----------|
| `tools` | Agent `.md` files in `agents/` | Tool names, `Bash(command *)` patterns, `Agent(name)` to restrict subagent spawning |
| `allowed-tools` | Skill `SKILL.md` files | Tool names, `Bash(command *)` patterns |

Both support granular Bash permission patterns like `Bash(git status *)`.

To restrict which subagents an agent can spawn (when running as main thread with `claude --agent`):

```yaml
tools: Agent(worker, researcher), Read, Bash
```

This is an allowlist — only `worker` and `researcher` can be spawned. To allow any subagent without restriction, use `Agent` without parentheses. If `Agent` is omitted, the agent cannot spawn any subagents.

## Model Selection for Agents

| Model | Use For |
|-------|---------|
| `opus` | Deep reasoning, security analysis, code review, debugging, complex refactoring |
| `sonnet` | Development workflows, moderate reasoning, multi-step implementation |
| `haiku` | Structured/mechanical tasks, documentation generation, CI configuration |

## Context Isolation

### `context: fork`

Creates an independent context copy. The agent sees parent history but its changes don't affect the parent session.

```yaml
---
name: research-agent
description: Research without polluting main context
model: sonnet
context: fork
tools: Glob, Grep, LS, Read, WebFetch, WebSearch, TodoWrite
---
```

**When to use `context: fork`:**
- Exploratory research that shouldn't affect the main session
- Parallel investigations with potentially conflicting approaches
- Isolated experiments or background tasks
- Agents that generate verbose output that would fill the main context

### Worktree Isolation

For filesystem-level isolation, give agents their own git worktree so they work on an isolated copy of the repository. The worktree is automatically cleaned up if the agent makes no changes; if changes are made, the worktree path and branch are returned.

**Two ways to enable worktree isolation:**

1. **Agent frontmatter** — baked into the agent definition:
   ```yaml
   ---
   name: implementer
   isolation: worktree
   ---
   ```

2. **Task tool parameter** — set per invocation:
   ```
   Task tool with isolation: "worktree"
   ```

**Use worktree isolation when:**
- Agent will make commits on a separate branch
- Multiple agents need to work on independent changes simultaneously
- You want changes isolated until explicitly merged

**Comparison:**

| Isolation Type | Mechanism | Isolates | Use Case |
|----------------|-----------|----------|----------|
| `context: fork` | Context fork | Context window | Research, exploration |
| `isolation: worktree` | Git worktree | Filesystem + Git | Implementation, commits |
| Manual worktree | `git worktree add` | Filesystem + Git | Complex multi-issue parallel work |

## Preloading Skills into Agents

Use the `skills` field to inject full skill content into an agent's context at startup. Unlike the main session where skill descriptions are loaded and full content loads on invocation, preloaded skills are fully injected immediately.

```yaml
---
name: api-developer
description: Implement API endpoints following team conventions
skills:
  - api-conventions
  - error-handling-patterns
---
Implement API endpoints. Follow the conventions and patterns from the preloaded skills.
```

Agents do **not** inherit skills from the parent session — they must be listed explicitly.

---

## Background Execution

Agents can run in the background using the Agent tool's `run_in_background` parameter (previously `Task tool`):

```
Agent tool with run_in_background: true
```

**Background execution behavior:**
- Returns immediately without waiting for the agent to finish
- The main session receives a notification when the agent completes
- Use `TaskOutput` tool to check on background agent status
- Use `TaskStop` tool to stop a background agent

**When to use background execution:**
- Independent work that doesn't need to block the main session
- Long-running tasks where you want to continue other work
- Parallel agent pipelines where results are collected later

**When NOT to use background execution:**
- When you need the agent's output before proceeding
- When the agent's work must complete before the next step
- Research agents whose findings inform your next steps

## Persistent Agent Memory

The `memory` field enables per-agent persistent memory that survives across conversations:

```yaml
---
name: code-reviewer
memory: user
---
Update your agent memory with patterns, conventions, and recurring issues you discover.
```

| Scope | Location | Use When |
|-------|----------|----------|
| `user` | `~/.claude/agent-memory/<name>/` | Learning should apply across all projects |
| `project` | `.claude/agent-memory/<name>/` | Knowledge is project-specific and shareable via git |
| `local` | `.claude/agent-memory-local/<name>/` | Project-specific but not committed to git |

When `memory` is set, Read/Write/Edit are auto-enabled for the memory directory, and the first 200 lines of `MEMORY.md` are injected into the agent's system prompt.

---

## Agent Memory (Session Hierarchy)

Agents participate in Claude Code's memory hierarchy. Memory is loaded from multiple scopes in order of specificity:

| Scope | Location | Loaded When |
|-------|----------|-------------|
| User | `~/.claude/CLAUDE.md` | All sessions for this user |
| User rules | `~/.claude/rules/*.md` | All sessions for this user |
| Project | `CLAUDE.md` (project root) | All sessions in this project |
| Project rules | `.claude/rules/*.md` | All sessions in this project |
| Local | `CLAUDE.local.md` | Sessions on this machine only (gitignored) |
| Auto memory | `~/.claude/projects/<project>/memory/` | Persists across sessions automatically |

**For agents:**
- Agents inherit the full memory hierarchy of their parent session
- `context: fork` agents see parent memory but don't write back to it
- Auto memory in `~/.claude/projects/<project>/memory/` persists across all sessions

### Auto Memory Pattern

The auto memory directory (`~/.claude/projects/<project>/memory/`) is loaded into every conversation. Use it to persist cross-session knowledge:

```
~/.claude/projects/<project>/memory/
├── MEMORY.md          # Primary memory file (always loaded, max 200 lines shown)
├── patterns.md        # Architectural patterns discovered
└── debugging.md       # Project-specific debugging notes
```

Agents can read and write to auto memory files to build on knowledge across sessions.

## Agent Teams (Multi-Agent Collaboration)

> **Experimental**: Agent teams are disabled by default. Enable with the `--enable-teams` flag or via settings. The API and behavior may change between versions.

Agent teams enable multiple agents to collaborate on complex tasks with a shared task list and messaging.

### Team Architecture

```
Lead Agent (orchestrator)
    ├── TeamCreate — creates team and task list
    ├── Agent tool — spawns teammate agents (previously Task tool)
    ├── SendMessage — communicates with teammates
    ├── TaskUpdate — assigns tasks to teammates
    └── Teammate Agents
            ├── Read team config from ~/.claude/teams/<team-name>/config.json
            ├── Use TaskList/TaskUpdate — claim and complete tasks
            └── Use SendMessage — report back to lead
```

### Native Team Tools

| Tool | Purpose |
|------|---------|
| `TeamCreate` | Create a team with shared task list |
| `TeamDelete` | Clean up team when work is complete |
| `SendMessage` | Send messages between agents (DM, broadcast, shutdown) |
| `TaskOutput` | Get output from background agent |
| `TaskStop` | Stop a running background agent |

### When to Use Teams

| Scenario | Use Teams | Use Subagents |
|----------|-----------|---------------|
| Parallel reviews (security + performance + correctness) | Yes | No |
| Sequential steps where each needs full context | No | Yes |
| Background tasks with ongoing communication | Yes | No |
| Single focused task | No | Yes |
| Multiple independent changes to the same codebase | Yes (with worktrees) | No |

### Team Configuration

Each agent's `## Team Configuration` section should document its optimal team role:

```markdown
## Team Configuration

**Recommended role**: Teammate (preferred) or Subagent

| Mode | When to Use |
|------|-------------|
| Teammate | Multi-aspect tasks: spawn parallel specialists |
| Subagent | Single focused task producing one result |
```

### Team Roles

| Role | Behavior | Advantages |
|------|----------|------------|
| **Lead** | Orchestrates team, assigns tasks, receives results | Coordinates complex workflows |
| **Teammate** | Works in parallel, communicates via messaging | Full context window, can message peers |
| **Subagent** | Focused isolated execution, returns single result | Simple, bounded tasks |

## Tool Restrictions

### `disallowedTools` Field

Explicitly block specific tools while allowing everything else:

```yaml
---
name: read-only-explorer
description: Explore codebase without modifications
model: haiku
tools: Bash, Read, Grep, Glob
disallowedTools: Write, Edit, NotebookEdit
---
```

### Restriction Patterns

| Pattern | Configuration | Use Case |
|---------|---------------|----------|
| Read-only research | `tools: Read, Grep, Glob, WebSearch` | Analysis without side effects |
| Safe code executor | `tools: Bash, Read` + `disallowedTools: Write, Edit` | Run but not modify |
| Documentation writer | `tools: Read, Write, Edit, Grep, Glob` + `disallowedTools: Bash` | Write docs safely |
| Full-power developer | `tools: Bash, Read, Write, Edit, Grep, Glob, TodoWrite` | Complete implementation |

## Agent Directory Layout

```
my-plugin/
├── .claude-plugin/
│   └── plugin.json
├── agents/
│   ├── specialist-agent.md    # Custom agent definition
│   └── another-agent.md
├── skills/
│   └── ...
└── README.md
```

Plugin agents are auto-discovered by Claude Code from the `agents/` directory.

User-level custom agents can be placed in `~/.claude/agents/`.

### Scope Priority

When multiple agents share the same name, higher-priority location wins:

| Location | Scope | Priority |
|----------|-------|----------|
| `--agents` CLI flag (JSON) | Current session only | 1 (highest) |
| `.claude/agents/` | Current project | 2 |
| `~/.claude/agents/` | All projects | 3 |
| Plugin `agents/` directory | Where plugin is enabled | 4 (lowest) |

CLI-defined agents use `--agents` flag with JSON (same frontmatter fields, use `prompt` for body):
```bash
claude --agents '{"my-agent": {"description": "...", "prompt": "...", "tools": ["Read"]}}'
```

## Checklist for New Agents

- [ ] Agent name is kebab-case
- [ ] `description` matches real user intents (not just tool jargon)
- [ ] `model` is appropriate (`haiku` for mechanical, `sonnet` for development, `opus` for deep reasoning)
- [ ] `tools` uses principle of least privilege
- [ ] Granular `Bash(command *)` patterns used instead of bare `Bash`
- [ ] `context: fork` added if agent needs isolated context window
- [ ] `isolation: worktree` added if agent needs filesystem-level git isolation
- [ ] `permissionMode` set if non-default permission behavior is needed
- [ ] `maxTurns` set if agent should be bounded
- [ ] `memory` scope set if agent needs cross-session persistence
- [ ] `skills` list populated if agent needs specific domain knowledge preloaded
- [ ] `## Team Configuration` section documents teammate vs subagent recommendation
- [ ] `## Scope` section defines input/output/step count
- [ ] Date fields set (`created`, `modified`, `reviewed`)
- [ ] Agent added to plugin `README.md` agents table
- [ ] If relevant, `color` field set for UI display

## Related Rules

- `.claude/rules/agentic-permissions.md` — Granular tool permission patterns
- `.claude/rules/skill-development.md` — Skill creation (use when agent is not needed)
- `.claude/rules/agentic-optimization.md` — CLI output optimization for agent consumption
