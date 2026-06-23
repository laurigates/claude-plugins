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

#### `/meta:promote`
Evaluate whether rules, skills, commands, or agents at one `.claude/` scope should be promoted to a higher scope (parent or user-global), and execute approved promotions safely.

**Usage:**
```bash
/meta:promote [scope-path]
```

**Features:**
- Walks target / sources / upstream layers to find overlap candidates
- Per-candidate checklist for owner-specific signals vs generic kernel
- Four-action menu: promote as-is, extract kernel, keep scoped, no action
- Per-candidate `AskUserQuestion` confirmation — no bundled approvals
- Read-broad / write-narrow: only approved files are touched, no auto-commit

#### `/meta:context-diet`
Audit always-loaded context (`CLAUDE.md` and `.claude/rules/`) for material that should become an on-demand skill, and migrate approved candidates one at a time.

**Usage:**
```bash
/meta:context-diet [scope-path]
```

**Features:**
- Inventories the every-turn surface and estimates each unit's token cost
- Classifies each rule/section: keep invariant, lean, path-scope, promote-to-skill, consolidate, drop
- Drafts an auto-triggering description before promoting (the gate that prevents lossy moves)
- Per-candidate `AskUserQuestion` confirmation, largest-impact first — no bundled approvals
- Inverse of `session-distill` (creates rules), orthogonal to `meta-promote` (moves between scopes)

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

#### `mcp-code-execution`
Design and scaffold the MCP code execution pattern for agent systems.

**When to use:**
- Building agents that interact with many MCP tools (50+)
- Intermediate data is too large for model context
- Workflows need loops, conditionals, or retries across tool calls
- PII must stay out of the model context
- Tasks benefit from state persistence across agent runs

**Features:**
- Decision framework: code execution vs direct tool calls
- Typed wrapper scaffolding for MCP servers
- Key patterns: progressive discovery, data filtering, PII tokenization, skill accumulation
- Security checklist for sandboxed execution environments

#### `mcp-server-authoring`
Producer-side patterns for **building** a Python MCP server with FastMCP — the shared conventions behind `kicad-mcp`, `silverbucket-mcp`, and `pal-mcp-server`.

**When to use:**
- Building or scaffolding a new MCP server
- Adding a tool, resource, or prompt to an existing server
- Wiring a server's tests (TDD), lint, and release-please
- Choosing transport (stdio vs HTTP) for a server you own

**Features:**
- FastMCP server skeleton (SDK-bundled and standalone `fastmcp`)
- Tool / resource / prompt decorators with type-hint-driven schemas
- Portfolio toolchain conventions (uv, ruff, pytest, release-please)
- TDD pattern testing the underlying function, not the decorator

#### `agent-teams`
Configure and orchestrate Claude Code agent teams (implicit team, SendMessage, shared task list workflows).

**When to use:**
- Setting up multi-agent parallel workflows
- Coordinating lead/teammate architectures
- Managing task assignment and inter-agent communication
- Implementing graceful team shutdown procedures

#### `parallel-agent-dispatch`
Dispatch contract for any workflow that spawns more than one agent in parallel — applies to both native agent teams and plain parallel `Agent` tool fan-out.

**When to use:**
- Before spawning any parallel agents (worktree preflight)
- Authoring agent prompts that need file/read/output budgets
- Defining the mandatory Return Contract every parallel agent must emit on exit
- Recovering from silent agent exits or worktree collisions

#### `verify-before-plan`
Verify orchestrator premises (file counts, build state, artefact presence) before dispatching parallel subagents. Sits before `parallel-agent-dispatch` in the dispatch sequence — bad premises propagate to every brief in the wave.

**When to use:**
- Planning a wave whose agent briefs cite a number, path, or "does X" claim not checked this session
- Inheriting a premise from a prior agent's return contract or an earlier session
- Patching from a user's symptom report ("the bug is X") before reading the failing repro
- Allocating from a shared counter (ADR / WO / migration sequence) that other agents may have bumped

**Features:**
- Verifier return-contract: Premise / Evidence / Verdict / Implicit assumptions
- Cheapest-verifier table mapping premise shape to the right tool (`Glob`, `Grep`, read-only agent)
- Anti-patterns catalog: name-equals-behaviour, stale-counter, symptom-not-cause

#### `adversarial-review`
Adversarial second-pass review that tries to break code, designs, plans, or ADRs — a thin posture (isolation, inverted objective, triage gate, bounded loop) layered on top of the existing domain review skills.

**When to use:**
- Stakes are high **and** a normal review already ran, but residual risk remains
- Red-teaming an architecture decision, ADR, or migration plan before commit
- Stress-testing a design's failure modes and invariants

**Features:**
- Precondition gate — refuses low-stakes/first-pass use (the common waste case)
- Lens table delegating domain checklists to `code-review`, security-audit, `verify-before-plan`, `cold-read-gate`
- Isolated opus reviewer with an inverted "find the fault" objective
- Triage gate separating genuine faults from manufactured objections before acting

#### `plugin-settings`
Configure per-project plugin settings using `.claude/plugin-name.local.md` files.

**When to use:**
- Building plugins that need user-configurable behavior
- Storing agent state between sessions
- Controlling hook activation per-project without editing `hooks.json`

**Features:**
- YAML frontmatter for structured settings
- Markdown body for prompts and additional context
- Standard `extract_field` parsing pattern
- Toggle-based hook activation, agent state management

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
