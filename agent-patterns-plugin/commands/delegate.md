---
description: Delegate tasks to specialized agents with automatic task-agent matching and parallel execution
allowed-tools: Task, TodoWrite, AskUserQuestion
argument-hint: "<task-description>"
---

## Context

- Working directory: !`pwd`
- Git status: !`git status --porcelain 2>/dev/null | head -10`
- Project type: !`ls -1 package.json pyproject.toml Cargo.toml go.mod 2>/dev/null | head -1`
- Recent files: !`git diff --name-only HEAD~5 2>/dev/null | head -10`

## Parameters

- `$1+`: Task description(s) - can be a single task or multiple tasks (comma-separated, numbered list, or natural language list)

## Your Task

**Intelligently delegate tasks to the most appropriate specialized agents, executing in parallel when possible.**

### Step 1: Parse and Analyze Tasks

Extract individual tasks from the user's input. Tasks may be provided as:
- A comma-separated list
- A numbered or bulleted list
- Natural language with implicit task boundaries (look for "and", "also", conjunctions)
- A single complex task that should be decomposed

### Step 2: Match Tasks to Agents

For each identified task, determine the best agent match using this reference:

| Task Pattern | Best Agent | When to Use |
|--------------|------------|-------------|
| Code exploration, finding implementations, tracing dependencies | `Explore` | Understanding code structure, locating patterns |
| Security review, vulnerability assessment, OWASP analysis | `security-audit` | Security concerns, auth flows, injection risks |
| Code quality review, architecture analysis | `code-review` | Quality assessment, design evaluation |
| Bug investigation, root cause analysis | `system-debugging` | Complex debugging, error analysis |
| Documentation generation, API docs | `documentation` | Creating/updating documentation |
| Running tests, analyzing failures | `test-runner` | Test execution and reporting |
| Test strategy, coverage analysis | `test-architecture` | Testing design decisions |
| CI/CD pipelines, GitHub Actions | `cicd-pipelines` | Build/deployment automation |
| Refactoring, SOLID principles | `code-refactoring` | Code quality improvements |
| TypeScript development, type safety | `typescript-development` | TS-specific work |
| Python development, tooling | `python-development` | Python-specific work |
| JavaScript/Node development | `javascript-development` | JS-specific work |
| Requirements, PRDs | `requirements-documentation` | Feature specifications |
| UX implementation, accessibility | `ux-implementation` | User interface work |
| API integration, REST endpoints | `api-integration` | External API work |
| Research, documentation lookup | `research-documentation` | Technical research |
| General multi-step tasks | `general-purpose` | Tasks not matching specific domains |

### Step 3: Task Decomposition (When Beneficial)

Consider splitting a task when:
- It spans multiple domains (e.g., "review and fix security issues" = security-audit + code-refactoring)
- It has sequential dependencies that can be parallelized partially
- It's too large for a single agent to handle effectively
- Different parts require different expertise

**Do NOT split when:**
- The task is atomic and domain-specific
- Splitting would add overhead without benefit
- The user explicitly wants a unified result

### Step 4: Plan the Delegation

Create a delegation plan with TodoWrite:
- List each task/subtask
- Assign the selected agent
- Note any dependencies between tasks
- Identify which tasks can run in parallel

### Step 5: Execute in Parallel

**CRITICAL: Launch all independent tasks simultaneously using multiple Task tool calls in a single message.**

For each task, use the Task tool with:
- `subagent_type`: The matched agent type
- `prompt`: Detailed task description with all relevant context
- `description`: Brief task summary

Include in each agent prompt:
- The specific task to perform
- Relevant context from the parsed input
- Project/file context from above
- Clear success criteria
- Whether to produce output or take action

### Step 6: Consolidate Results

After all agents complete:
1. Summarize findings from each agent
2. Highlight any cross-cutting concerns discovered
3. Note any follow-up actions needed
4. Present a unified report to the user

## Execution Guidelines

### Parallel Execution Example

When delegating multiple independent tasks, send them all at once:

```markdown
[Task 1 - security-audit agent]
[Task 2 - code-review agent]
[Task 3 - test-runner agent]
```

All three launch simultaneously, maximizing efficiency.

### Handling Dependencies

If Task B depends on Task A:
1. Launch Task A first
2. Wait for completion
3. Pass Task A results to Task B
4. Continue with any remaining parallel tasks

### Agent Prompt Template

When calling each agent, structure the prompt as:

```
## Task
[Clear description of what to accomplish]

## Context
- Project: [type/framework]
- Files of interest: [relevant paths]
- Recent changes: [if applicable]

## Scope
[Specific boundaries for the task]

## Expected Output
[What the agent should produce/report]
```

## Output

Report back to the user with:

```markdown
## Delegation Summary

### Tasks Identified
1. [Task 1] → `agent-type` ✓
2. [Task 2] → `agent-type` ✓
3. [Task 3] → `agent-type` ✓

### Execution Status
- Parallel: Tasks 1, 2, 3 launched simultaneously
- Sequential: [any dependent tasks]

### Results

#### [Task 1 Summary]
[Key findings/actions]

#### [Task 2 Summary]
[Key findings/actions]

#### [Task 3 Summary]
[Key findings/actions]

### Follow-up Actions
- [Any remaining work]
- [Cross-cutting concerns]
```

## Examples

### Example 1: Multiple Independent Tasks
```
/delegate Review the auth module for security issues, update the API documentation, and run the test suite
```
→ Launches: `security-audit`, `documentation`, `test-runner` in parallel

### Example 2: Complex Task Requiring Decomposition
```
/delegate Investigate why the login flow is broken and fix it
```
→ Launches: `system-debugging` (investigate) → `code-refactoring` (fix) sequentially

### Example 3: Single Specialized Task
```
/delegate Find all usages of the deprecated UserService class
```
→ Launches: `Explore` agent (single task, no splitting needed)

## See Also

- **CLAUDE.md** (`.claude/CLAUDE.md`) - Delegation strategy and agent reference
- **Commands** - `/code:review`, `/test:run`, `/git:commit` for specific workflows
- **Skills** - Domain-specific skills auto-invoked by agents
