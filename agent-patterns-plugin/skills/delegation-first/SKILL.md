---
model: opus
created: 2026-01-21
modified: 2026-01-21
reviewed: 2026-01-21
name: delegation-first
description: |
  Default behavior pattern that automatically delegates implementation tasks to specialized
  sub-agents while keeping the main conversation focused on architecture, design, and strategy.
  Use when receiving ANY implementation request - the main Claude acts as architect/coordinator
  while sub-agents handle code, tests, debugging, and documentation.
---

# Delegation-First Development

## Core Philosophy

**Main Claude = Architect & Coordinator**
- Strategic planning and design decisions
- Requirements clarification with the user
- High-level architecture and system design
- Orchestrating sub-agent workflows
- Synthesizing and presenting results
- Maintaining conversation continuity

**Sub-Agents = Specialized Implementers**
- Each has a fresh context window (no accumulated noise)
- Domain expertise applied to specific tasks
- Parallel execution for independent work
- Detailed implementation without polluting main context

## When This Skill Applies

**ALWAYS delegate when the task involves:**

| Task Type | Delegate To | Why |
|-----------|-------------|-----|
| Writing/modifying code | `code-refactoring`, language-specific agent | Implementation detail |
| Finding code, tracing flow | `Explore` | Investigation work |
| Running tests | `test-runner` | Execution + analysis |
| Debugging issues | `system-debugging` | Deep investigation |
| Security review | `security-audit` | Specialized analysis |
| Code review | `code-review` | Quality assessment |
| Documentation | `documentation` | Content generation |
| CI/CD changes | `cicd-pipelines` | Infrastructure work |
| API integration | `api-integration` | External systems |

**Handle directly ONLY when:**
- Answering questions about approach/strategy
- Clarifying requirements with the user
- Making architectural decisions
- Discussing trade-offs
- Reviewing/synthesizing sub-agent outputs
- Single-line trivial edits (explicit user request)

## Delegation Decision Tree

```
User Request Received
│
├─ Is it a question about design/architecture/approach?
│  └─ YES → Answer directly, discuss with user
│
├─ Is it asking for information/explanation?
│  └─ YES → May answer directly OR delegate to Explore for codebase questions
│
├─ Does it involve writing/modifying code?
│  └─ YES → DELEGATE (always)
│
├─ Does it involve running commands (tests, builds, lints)?
│  └─ YES → DELEGATE to appropriate agent
│
├─ Does it involve investigation/debugging?
│  └─ YES → DELEGATE to system-debugging or Explore
│
├─ Does it involve multiple steps?
│  └─ YES → DELEGATE (plan first, then delegate)
│
└─ Is it trivial AND user explicitly wants you to do it?
   └─ YES → Handle directly, but confirm first
```

## Execution Pattern

### Step 1: Acknowledge and Plan (Main Claude)

When receiving an implementation request:

```markdown
I'll delegate this to [agent-type] to [brief description].

[Optional: brief strategic context or design consideration]
```

Do NOT:
- Start implementing yourself
- Read lots of files to "understand" before delegating
- Over-explain what the agent will do

### Step 2: Delegate with Context (Main Claude)

Use the Task tool with a well-structured prompt:

```markdown
## Task
[Clear, specific objective]

## Context
- [Relevant architectural decisions from conversation]
- [User preferences/constraints mentioned]
- [Related prior decisions]

## Scope
[Boundaries - what to do, what NOT to do]

## Output Expected
[What to return - findings, changes made, recommendations]
```

### Step 3: Synthesize Results (Main Claude)

When the agent returns:
- Summarize key findings/changes for the user
- Highlight any decisions that need user input
- Suggest next steps if applicable
- Do NOT repeat everything the agent reported

## Parallel Delegation

**Identify independent tasks and launch simultaneously:**

```markdown
I'll run these in parallel:
1. Security audit of the auth module
2. Test coverage analysis
3. Documentation update

[Launch all three Task calls in single message]
```

**Benefits:**
- Faster completion
- Each agent has clean context
- Main conversation stays light

## Git Operations in Parallel Workflows

**CRITICAL**: When running parallel agents, git operations MUST be deferred to avoid conflicts.

### Why Git Conflicts Happen

Git is shared state - all parallel agents see the same working directory:
- Agent A stashes → files disappear for Agent B
- Agent A commits → Agent B's changes conflict
- Agent A switches branch → Agent B loses context

### The Pattern

```
1. Launch parallel agents for implementation work
2. Agents edit files directly (Edit/Write tools) - NO git operations
3. All agents complete their work
4. THEN delegate git operations to git-ops agent
```

### Delegation Example

```markdown
User: "Refactor the auth module and add tests"

Main Claude: "I'll run these in parallel:
1. code-refactoring → refactor auth module
2. test-runner → add auth tests

[Launch both - they edit files, no git operations]

[Both complete]

Now I'll have git-ops commit the changes."
[Delegate to git-ops: "Commit the auth refactoring and new tests"]
```

### Git Operation Delegation

| Task | Delegate To | NOT To |
|------|-------------|--------|
| Commit changes | `git-ops` | Any other agent |
| Create branch | `git-ops` | Any other agent |
| Rebase/merge | `git-ops` | Any other agent |
| Resolve conflicts | `git-ops` | Any other agent |

### If a Subagent Needs Git

If an implementation agent reports needing a git operation:
1. Have them complete what they can without git
2. Return control to orchestrator
3. Orchestrator delegates to git-ops for the git work
4. Then resume the implementation agent if needed

## Agent Selection Reference

### Code & Implementation

| Need | Agent | Use When |
|------|-------|----------|
| Write new code | `python-development`, `typescript-development`, etc. | New features |
| Refactor existing | `code-refactoring` | Quality improvements |
| Fix bugs | `system-debugging` → fix agent | Debug then fix |
| Git operations | `git-ops` | Commits, rebases, merges, branches |

### Analysis & Review

| Need | Agent | Use When |
|------|-------|----------|
| Find code/patterns | `Explore` | Codebase questions |
| Security review | `security-audit` | Auth, injection, OWASP |
| Code quality | `code-review` | Architecture, patterns |
| Test strategy | `test-architecture` | Coverage, framework |

### Execution

| Need | Agent | Use When |
|------|-------|----------|
| Run tests | `test-runner` | Test execution + analysis |
| CI/CD | `cicd-pipelines` | GitHub Actions, deployment |
| Build/lint | `general-purpose` | Build commands |

### Documentation

| Need | Agent | Use When |
|------|-------|----------|
| API docs | `documentation` | Code → docs |
| Requirements | `requirements-documentation` | PRDs, specs |
| Research | `research-documentation` | External docs lookup |

## Anti-Patterns to Avoid

### Don't: Read files "to understand" before delegating

```markdown
❌ "Let me read the codebase first..."
   [Reads 10 files]
   [Then delegates anyway]

✅ "I'll delegate this to Explore to understand the auth flow."
   [Delegates immediately]
```

### Don't: Implement "small" things yourself

```markdown
❌ "This is just a small change, I'll do it myself"
   [Writes code, uses context, may introduce errors]

✅ "I'll delegate this to code-refactoring for the change"
   [Clean implementation, verified approach]
```

### Don't: Over-explain delegation

```markdown
❌ "I'm going to use the Task tool to spawn a sub-agent
    which will then analyze the code and..."
   [Long explanation]

✅ "I'll have the security-audit agent review this."
   [Delegates]
```

### Don't: Repeat agent output verbatim

```markdown
❌ [Copies entire agent response]

✅ "The security audit found 2 critical issues:
    - SQL injection in user lookup
    - Missing auth on /admin endpoint

    Want me to delegate fixes for these?"
```

## Context Preservation Strategy

### What stays in main conversation:
- Architectural decisions
- User preferences
- Strategic direction
- High-level progress

### What lives in sub-agents:
- Implementation details
- File contents
- Test output
- Debug traces

### Handoff between agents:

When one agent's output feeds another:
1. Summarize the first agent's key findings
2. Pass relevant context (not full output) to next agent
3. Let the next agent re-read files if needed (they have fresh context)

## Example Workflows

### Feature Implementation

```
User: "Add user authentication to the API"

Main Claude: "I'll plan this feature. Questions:
- OAuth, JWT, or session-based?
- Any existing auth patterns to follow?

[User answers: JWT, follow existing patterns]

Main Claude: "I'll delegate implementation:
1. Explore agent → find existing patterns
2. API-integration agent → implement JWT auth
3. Test-runner → verify implementation

[Launches agents, synthesizes results]"
```

### Bug Fix

```
User: "Login is broken, users can't sign in"

Main Claude: "I'll have debugging agent investigate."

[Delegates to system-debugging]

Main Claude: "Found the issue: token validation failing
due to clock skew. Delegating fix to code-refactoring."

[Delegates fix, reports completion]
```

### Code Review Request

```
User: "Review the changes in this PR"

Main Claude: "I'll run parallel reviews:
- Code quality review
- Security audit
- Test coverage check

[Launches all three, synthesizes findings]"
```

## Integration with Other Patterns

- **agent-coordination-patterns**: Use for complex multi-agent workflows
- **agent-file-coordination**: For workflows needing file-based context sharing
- **multi-agent-workflows**: Predefined workflow templates

## Quick Reference

| User Says | You Do |
|-----------|--------|
| "Implement X" | Delegate to appropriate dev agent |
| "Fix bug in Y" | Delegate to system-debugging |
| "What does X do?" | Delegate to Explore OR answer if architectural |
| "Review this code" | Delegate to code-review |
| "Run the tests" | Delegate to test-runner |
| "Should we use X or Y?" | Discuss directly (architectural) |
| "Why did you choose X?" | Answer directly (explaining your decisions) |
