# agents-plugin

Task-focused agents following 12-factor agent principles. Each agent completes a bounded task (3-20 steps) and can operate as a teammate (parallel, communicating) or subagent (focused, isolated).

## Flow

See [`docs/flow.md`](docs/flow.md) for a diagram of how `attribute-router` delegates to the domain agents.

## Agents

All agents run on **opus** — see [Model Selection](#model-selection).

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

## Team Roles

Each agent includes a `## Team Configuration` section documenting when to use it as a teammate vs subagent:

| Role | When to Use |
|------|-------------|
| **Teammate** | Task benefits from parallel execution and inter-agent communication via shared task list |
| **Subagent** | Task is focused, short, and produces a single isolated result |

### Recommended Roles

| Best as Teammate | Best as Subagent | Either |
|------------------|------------------|--------|
| review, security-audit, research, docs | dependency-audit, performance, search-replace, ci | test, debug, refactor |

## Design Principles

- **Task-oriented**: Each agent maps to a real user request
- **Complete the job**: Agents finish what they start
- **Small scope**: 3-20 steps per task
- **Generic + Skills**: Expertise lives in skills, agents are task runners
- **Context isolation**: Verbose output stays in agent, only summaries return
- **Team-aware**: Each agent documents its optimal team role

## Model Selection

Every agent runs on **opus**. A subagent's output re-enters the main loop as a tool result, so a weaker delegate quietly degrades everything downstream — and Opus-low beats Sonnet-high on both quality and tokens. So **`effort` (a session setting), not `model`, is the cost lever**: dial effort down for mechanical agents instead of downgrading the model. The lint `scripts/check-agent-model.sh` enforces this. The sole sanctioned non-Opus subagent is the `agent-patterns-plugin:cold-read-gate` haiku reader, which is a skill-inline dispatch rather than an agent file. See `.claude/rules/agent-development.md` § "Model Selection for Agents".

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
