# agents-plugin

Task-focused agents following 12-factor agent principles. Each agent completes a bounded task (3-20 steps) without handoffs.

## Agents

| Agent | Model | Purpose |
|-------|-------|---------|
| `test` | haiku | Write and run tests |
| `review` | opus | Code review, commit review, PR review |
| `debug` | opus | Diagnose and fix bugs |
| `docs` | haiku | Generate documentation |
| `ci` | haiku | Pipeline configuration |

## Design Principles

- **Task-oriented**: Each agent maps to a real user request
- **Complete the job**: No @HANDOFF patterns, agents finish what they start
- **Small scope**: 3-20 steps per task
- **Generic + Skills**: Expertise lives in skills, agents are task runners

## Usage

Agents are invoked automatically based on task context or explicitly via agent routing.

### Examples

```
"Write tests for the auth module" → test agent
"Review this PR" → review agent
"This endpoint is returning 500" → debug agent
"Document the API" → docs agent
"Set up GitHub Actions" → ci agent
```
