# agents-plugin

Task-focused agents following 12-factor agent principles. Each agent completes a bounded task (3-20 steps) and can operate as a teammate (parallel, communicating) or subagent (focused, isolated).

## Agents

| Agent | Model | Purpose | Team Role |
|-------|-------|---------|-----------|
| `test` | haiku | Write and run tests | Either — parallel test suites as teammate, focused testing as subagent |
| `review` | opus | Code review, commit review, PR review | Teammate preferred — parallel security/performance/correctness review |
| `debug` | opus | Diagnose and fix bugs | Either — parallel investigation as teammate, single fix as subagent |
| `docs` | haiku | Generate documentation | Teammate preferred — parallel doc generation across modules |
| `ci` | haiku | Pipeline configuration | Either — parallel setup as teammate, single workflow as subagent |
| `security-audit` | opus | Vulnerability scanning, OWASP analysis | Teammate preferred — continuous audit alongside development |
| `refactor` | opus | Code restructuring, SOLID improvements | Either — parallel refactoring with file-locking as teammate |
| `dependency-audit` | haiku | CVE scanning, outdated packages, licenses | Subagent preferred — quick focused audit |
| `research` | opus | API docs, framework evaluation, best practices | Teammate preferred — parallel research alongside implementation |
| `performance` | opus | Profiling, bottleneck identification, benchmarks | Subagent preferred — verbose profiling isolated |

## Team Roles

Each agent includes a `## Team Configuration` section documenting when to use it as a teammate vs subagent:

| Role | When to Use |
|------|-------------|
| **Teammate** | Task benefits from parallel execution and inter-agent communication via shared task list |
| **Subagent** | Task is focused, short, and produces a single isolated result |

### Recommended Roles

| Best as Teammate | Best as Subagent | Either |
|------------------|------------------|--------|
| review, security-audit, research, docs | dependency-audit, performance | test, debug, ci, refactor |

## Design Principles

- **Task-oriented**: Each agent maps to a real user request
- **Complete the job**: Agents finish what they start
- **Small scope**: 3-20 steps per task
- **Generic + Skills**: Expertise lives in skills, agents are task runners
- **Context isolation**: Verbose output stays in agent, only summaries return
- **Team-aware**: Each agent documents its optimal team role

## Model Selection

| Model | When Used | Agents |
|-------|-----------|--------|
| haiku | Structured operations, mechanical tasks | test, docs, ci, dependency-audit |
| opus | Deep reasoning, complex analysis, code restructuring | review, debug, security-audit, performance, refactor, research |

## Usage

Agents are invoked automatically based on task context or explicitly via agent routing.

### Examples

```
"Write tests for the auth module" → test agent
"Review this PR" → review agent
"This endpoint is returning 500" → debug agent
"Document the API" → docs agent
"Set up GitHub Actions" → ci agent
"Check for security vulnerabilities" → security-audit agent
"Clean up this class, it's too complex" → refactor agent
"Check for vulnerable dependencies" → dependency-audit agent
"How does the Stripe API handle pagination?" → research agent
"The API endpoint is slow, find the bottleneck" → performance agent
```
