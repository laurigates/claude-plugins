# agents-plugin

Task-focused agents following 12-factor agent principles. Each agent completes a bounded task (3-20 steps) without handoffs.

## Agents

| Agent | Model | Purpose | Context Value |
|-------|-------|---------|---------------|
| `test` | haiku | Write and run tests | Test output stays isolated |
| `review` | opus | Code review, commit review, PR review | Large diffs stay in agent |
| `debug` | opus | Diagnose and fix bugs | Debug logging stays isolated |
| `docs` | haiku | Generate documentation | Codebase analysis stays isolated |
| `ci` | haiku | Pipeline configuration | Workflow file generation |
| `security-audit` | opus | Vulnerability scanning, OWASP analysis | Verbose scan results summarized |
| `refactor` | opus | Code restructuring, SOLID improvements | Large refactoring diffs isolated |
| `terraform-ops` | haiku | Plan/apply, drift detection, state ops | Terraform plan output (100s of lines) summarized |
| `k8s-diagnostics` | haiku | Pod failures, log analysis, troubleshooting | kubectl describe/logs output summarized |
| `git-ops` | haiku | Merge conflicts, rebase, bisect, cherry-pick | Conflict resolution context isolated |
| `container-build` | haiku | Docker build, layer analysis, debugging | Build output (100s of lines) summarized |
| `dependency-audit` | haiku | CVE scanning, outdated packages, licenses | Audit output summarized to actionable items |
| `research` | opus | API docs, framework evaluation, best practices | Web fetches and docs stay in agent |
| `performance` | opus | Profiling, bottleneck identification, benchmarks | Profiler output summarized to hot paths |

## Design Principles

- **Task-oriented**: Each agent maps to a real user request
- **Complete the job**: No @HANDOFF patterns, agents finish what they start
- **Small scope**: 3-20 steps per task
- **Generic + Skills**: Expertise lives in skills, agents are task runners
- **Context isolation**: Verbose output stays in agent, only summaries return

## Model Selection

| Model | When Used | Agents |
|-------|-----------|--------|
| haiku | Structured operations, mechanical tasks | test, docs, ci, terraform-ops, k8s-diagnostics, git-ops, container-build, dependency-audit |
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
"Run terraform plan for staging" → terraform-ops agent
"Pods are crashing in production" → k8s-diagnostics agent
"Resolve merge conflicts on this branch" → git-ops agent
"Docker build is failing" → container-build agent
"Check for vulnerable dependencies" → dependency-audit agent
"How does the Stripe API handle pagination?" → research agent
"The API endpoint is slow, find the bottleneck" → performance agent
```

## Skills Integration

Some agents preload skills for domain expertise:

| Agent | Preloaded Skills |
|-------|-----------------|
| `terraform-ops` | terraform-workflow, terraform-state-management |
| `k8s-diagnostics` | kubernetes-operations, kubernetes-debugging |
| `git-ops` | git-cli-agentic, git-commit |
| `container-build` | docker-development, dockerfile-optimization |
