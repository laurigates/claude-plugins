# agents-plugin

Task-focused agents following 12-factor agent principles. Each agent completes a bounded task (3-20 steps) and can operate as a teammate (parallel, communicating) or subagent (focused, isolated).

## Flow

See [`docs/flow.md`](docs/flow.md) for a diagram of how `attribute-router` delegates to the domain agents.

## Agents

Every agent except `lean-reader` runs on **opus**; `lean-reader` runs on haiku — see [Model Selection](#model-selection).

| Agent | Model | Purpose | Team Role |
|-------|-------|---------|-----------|
| `attribute-router` | opus | Route to domain agents by codebase-health attributes | Subagent — delegates to specialists by severity |
| `test` | opus | Write and run tests | Either — parallel test suites as teammate, focused testing as subagent |
| `review` | opus | Code review, commit review, PR review | Teammate preferred — parallel security/performance/correctness review |
| `debug` | opus | Diagnose and fix bugs | Either — parallel investigation as teammate, single fix as subagent |
| `docs` | opus | Generate documentation | Teammate preferred — parallel doc generation across modules |
| `ci` | opus | Full CI/CD scaffold (multi-workflow buildout) | Subagent — delegate a from-scratch pipeline; edit single workflows inline |
| `security-audit` | opus | Vulnerability scanning, OWASP analysis | Teammate preferred — continuous audit alongside development |
| `refactor` | opus | Code restructuring, SOLID improvements | Either — parallel refactoring with file-locking as teammate |
| `dependency-audit` | opus | CVE scanning, outdated packages, licenses | Subagent preferred — quick focused audit |
| `research` | opus | API docs, framework evaluation, best practices | Teammate preferred — parallel research alongside implementation |
| `performance` | opus | Profiling, bottleneck identification, benchmarks | Subagent preferred — verbose profiling isolated |
| `search-replace` | opus | Cross-platform search and replace | Subagent preferred — focused bounded replacement task |
| `lean-reader` | haiku | Context-free read-only extraction and classification against a self-contained brief | Subagent — workflow `agentType` for mechanical fan-out stages |

## Team Roles

Each agent includes a `## Team Configuration` section documenting when to use it as a teammate vs subagent:

| Role | When to Use |
|------|-------------|
| **Teammate** | Task benefits from parallel execution and inter-agent communication via shared task list |
| **Subagent** | Task is focused, short, and produces a single isolated result |

### Recommended Roles

| Best as Teammate | Best as Subagent | Either |
|------------------|------------------|--------|
| review, security-audit, research, docs | dependency-audit, performance, search-replace, ci, lean-reader | test, debug, refactor |

## Design Principles

- **Task-oriented**: Each agent maps to a real user request
- **Complete the job**: Agents finish what they start
- **Small scope**: 3-20 steps per task
- **Report before the limit**: Each agent sets `maxTurns` and carries a `## Turn Budget` section: at about 80% of the budget it stops investigating and delivers its report, marking unfinished areas as not verified. A run cut off at the limit returns nothing (#3152), so size briefs to the agent's limit and split large ones (`scripts/check-agent-turn-budget.sh` enforces the section)
- **Generic + Skills**: Expertise lives in skills, agents are task runners
- **Context isolation**: Verbose output stays in agent, only summaries return
- **Team-aware**: Each agent documents its optimal team role

## Model Selection

Every agent except `lean-reader` runs on **opus**. The repo picks models by task shape: opus for judgement work, sonnet with an explicit effort for bounded and checkable work, haiku for a lean reader checked downstream. A subagent's output re-enters the main loop as a tool result, so a weaker model's output needs a check. Moving an agent here off opus waits on a measurement (#3116); until then `effort:` is the cost lever. The lint `scripts/check-agent-model.sh` enforces the tier shapes. See `.claude/rules/agent-development.md` § "Model Selection for Agents".

`lean-reader` is the exception, and the guard admits it only in this shape: Haiku 5.5, `omitClaudeMd: true`, tools limited to Read/Grep/Glob, and an explicit effort. Its first request is about 3k tokens. A default subagent starts at about 124k, carrying the CLAUDE.md + rules chain and every tool schema including the skill listing. The lean reader is meant for stages whose brief carries the whole job and whose output a schema or an Opus stage checks. It is not for edits, commands, or anything the main loop acts on unchecked. See `.claude/rules/agent-development.md` § "Lean subagents".

## Usage

Agents are invoked automatically based on task context or explicitly via agent routing.

### Examples

```
"Write tests for the auth module" → test agent
"Review this PR" → review agent
"This endpoint is returning 500" → debug agent
"Document the API" → docs agent
"Scaffold a full CI/CD pipeline from scratch" → ci agent
"Check for security vulnerabilities" → security-audit agent
"Clean up this class, it's too complex" → refactor agent
"Check for vulnerable dependencies" → dependency-audit agent
"How does the Stripe API handle pagination?" → research agent
"The API endpoint is slow, find the bottleneck" → performance agent
"Replace oldFunction with newFunction across the codebase" → search-replace agent
```

In a workflow script, use the lean reader as a stage's `agentType`:

```js
const parsed = await agent(BRIEF_WITH_RUBRIC_AND_FILES, {
  label: 'parse', agentType: 'agents-plugin:lean-reader',
  model: 'haiku', effort: 'medium', schema: SCHEMA,
})
```
