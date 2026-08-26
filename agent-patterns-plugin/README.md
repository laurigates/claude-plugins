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

#### `meta-local-notes`
Audit a machine-local notes file (`CLAUDE.local.md`) — verify every claim against the live environment, correct drifted facts, and delete findings that duplicate versioned docs.

**When to use:**
- Local notes have grown stale, bloated, or contradict the ADRs/roadmap
- Before appending a session finding to a machine-local file

**Features:**
- The keep test: environment facts (host, paths, toolkit versions, local gotchas) stay; project findings (measurements, root causes, blocker status) move to the versioned docs
- Live-probe checklist per claim shape — including the perf-commit check that catches a still-plausible claim the project already fixed
- holds / drifted / superseded / gone verdicts, with correct-don't-delete for drifted environment facts
- Reports the verdict table, supplying the review a git-ignored file never gets
- Complements `meta-context-diet`: that skill audits a file's load cost, this one audits its truth

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
Producer-side patterns for **building** a Python MCP server with FastMCP — an ordered, reasoned build path (scaffold → tools → resources → tests → release) for any server you own.

**When to use:**
- Building or scaffolding a new MCP server
- Adding a tool, resource, or prompt to an existing server
- Wiring a server's tests (TDD), lint, and release-please
- Choosing transport (stdio vs HTTP) for a server you own

**Features:**
- FastMCP server skeleton (SDK-bundled and standalone `fastmcp`)
- Tool / resource / prompt decorators with type-hint-driven schemas
- Toolchain wiring (uv, ruff, pytest, release-please) with the reasoning at each step
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
- Mapping the Return Contract onto workflow primitives (a JSON Schema on the `agent()` call; `parallel()` as the barrier) before reaching for a harness

#### `multi-model-delegation`
Protocol for consulting *other* models (kimi, glm, gemini, gpt via the PAL MCP gateway) on design and judgment work — the complement of `parallel-agent-dispatch`, which delegates *work* to Claude subagents.

**When to use:**
- Brainstorming an open design decision with foreign models (PAL `chat`/`consensus`)
- Reconciling two models' conflicting design proposals
- Deciding whether a multi-model consult is worth the tokens

**Features:**
- The disagreement-is-the-signal protocol: identical briefs, independent round one, diff for the split
- Adjudicate splits against the codebase (which usually already decided), never model confidence
- Graft-never-adopt-wholesale synthesis guidance
- PAL mechanics that bite: `listmodels` first, the kimi `temperature` 400, per-model `absolute_file_paths` budgets, the `PAL_WORKSPACE_ROOT` restriction, and `model_used` scrambling under concurrency
- The curated excerpt bundle: one §-numbered verbatim-excerpt file, sized under the smallest model's budget, attached unchanged to every model

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

#### `tool-result-traps`
Tool results that mean something other than they look — an empty result, a green exit, and a well-formed line of output are each claims about mechanics, not content. Complements `verify-before-plan`: that one verifies a premise before a wave, this one distrusts the tool output a verdict is built on.

**When to use:**
- A zero-match or empty result is about to be reported as "clean", "complete", or "none found"
- Deduping before filing an issue, or concluding nobody reported something
- Declaring a bulk rename, migration, or sweep finished
- A verification loop's input set is built from a relative path in a long-running session
- An `rg` / `git grep` result contradicts something read directly
- Concluding a skill, command, recipe, or binary "does not exist"
- A `-g` / `--glob` filter is narrowing the search and the name you want is a directory

**Features:**
- The silent-rewrite and never-compiled-pattern cases: `rg -r` as `--replace`, `git grep -E` dropping `\b`
- Why `-g '*name*'` cannot match a *directory* — a no-slash glob tests the basename, and it returns plausible sibling files rather than zero
- One search tier is not the search universe: user-global, plugin, and project (`<repo>/.claude/`) resolve independently
- A rejected flag reading as "no results" — and its worse variants on a *write*, and on an accepted flag that takes a stdin marker literally
- The persistent-cwd pair: the shell wedge `cd` cannot undo, and the vacuous path-scoped verification that shares its cause
- `Workflow` `args` arriving JSON-encoded, so agents run against `undefined`
- Control-testing every negative that gates an action; parallel-batch rule for siblings that can exit non-zero

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

#### `execution-grounded-review`
Verify an implementation meets its acceptance criteria by running the suite first, then tracing each criterion to execution evidence — the execution-grounded sibling of `adversarial-review`.

**When to use:**
- Verifying an implementation meets explicit acceptance criteria, proven by running it
- Gating a loop/phase `done` on an independent check of behaviour
- Confirming a fix actually fixes the reported failure (not just compiles)
- Closing the loop on "is every requirement actually covered by a test?"

**Features:**
- Execute-first: runs suite + typecheck + lint before any verdict
- `LEDGER` schema binding the verifier's output: one row per criterion, `verdict` enum (PASS/FAIL/PARTIAL/UNVERIFIED) grounded in execution evidence
- Required `sequenceMatchesProduction` enum on every row — makes "I did not check the production call sequence" unrepresentable
- Intent-starved isolated opus verifier — grades behaviour, not the author's rationale
- Over-correction triage guarding both "pass broken code" and "fail correct code"

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

#### `expose-tunable-knob`
Expose a live-adjustable control instead of guessing a magic constant for a parameter the agent cannot itself perceive (visual, audio, UX output).

**When to use:**
- Tuning a value judged by a sense the agent lacks — color, size, position, timing, gain
- The user has already pushed back once on a guessed default ("that's better, but...")
- The runtime already has (or can cheaply gain) a live control surface — a UI slider, hot-reloadable config, a `--watch` flag

**Features:**
- Four-step pattern: parameterize the mechanism, pick a reasoned starting default, expose a live control at the human's layer, stop guessing past that point
- Anti-pattern catalog: silent precision theater, unreachable knobs, knob sprawl
- Worked example from a live face-swap app's mouth-mask tuning

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
