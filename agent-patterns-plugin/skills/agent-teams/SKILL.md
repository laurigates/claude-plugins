---
model: sonnet
name: agent-teams
description: |
  Configure and orchestrate Claude Code agent teams (TeamCreate, SendMessage, TaskUpdate
  workflow). Use when you need multiple agents working in parallel on a complex task,
  want to coordinate background agents with messaging, or are setting up a lead/teammate
  architecture with a shared task list. Teams are experimental — enable with
  --enable-teams flag.
user-invocable: false
allowed-tools: Read, Glob, Grep, TodoWrite
created: 2026-03-03
modified: 2026-03-03
reviewed: 2026-03-03
---

# Agent Teams

> **Experimental**: Agent teams require the `--enable-teams` flag and may change between Claude Code versions.

## When to Use This Skill

| Use agent teams when... | Use subagents instead when... |
|------------------------|------------------------------|
| Multiple agents need to work in parallel | Tasks are sequential and interdependent |
| Ongoing communication between agents is needed | One focused task produces one result |
| Background tasks need progress reporting | Agent output feeds directly into next step |
| Complex workflows benefit from task coordination | Simple, bounded, isolated execution |
| Independent changes to the same codebase (with worktrees) | Context sharing is fine and efficient |

## Core Concepts

### Team Architecture

```
Lead Agent (orchestrator)
    ├── TeamCreate — creates team + shared task list
    ├── Task tool — spawns teammate agents
    ├── SendMessage — communicates with teammates
    ├── TaskUpdate — assigns tasks to teammates
    └── Teammates (run in parallel)
            ├── Read team config from ~/.claude/teams/<name>/config.json
            ├── TaskList/TaskUpdate — claim and complete tasks
            └── SendMessage — report back to lead
```

### Native Team Tools

| Tool | Purpose |
|------|---------|
| `TeamCreate` | Create team and shared task list directory |
| `TeamDelete` | Clean up team when all work is complete |
| `SendMessage` | Send DMs, broadcasts, shutdown requests, plan approvals |
| `TaskOutput` | Get output from a background agent |
| `TaskStop` | Stop a running background agent |

## Team Setup Workflow

### 1. Create the Team

```
TeamCreate({
  team_name: "my-project",
  description: "Working on feature X"
})
```

This creates:
- `~/.claude/teams/<team-name>/` — team config directory
- `~/.claude/tasks/<team-name>/` — shared task list directory

### 2. Create Initial Tasks

```
TaskCreate({
  team_name: "my-project",
  title: "Implement security review",
  description: "Audit auth module for vulnerabilities",
  status: "pending"
})
```

### 3. Spawn Teammates

Use the Task tool to spawn each teammate with the team context:

```
Agent tool with:
  subagent_type: "agents-plugin:security-audit"
  team_name: "my-project"
  name: "security-reviewer"
  prompt: "Join team my-project and work on security review task..."
```

### 4. Assign Tasks

```
TaskUpdate({
  team_name: "my-project",
  task_id: "task-1",
  owner: "security-reviewer",
  status: "in_progress"
})
```

### 5. Receive Results

Teammates send messages automatically — they are delivered to the lead's inbox between turns. No polling needed.

## Task Management

### Task States

| State | Meaning |
|-------|---------|
| `pending` | Not yet started |
| `in_progress` | Assigned and active (one at a time per teammate) |
| `completed` | Finished successfully |
| `blocked` | Waiting on another task |

### Task Priority

Teammates should claim tasks in **ID order** (lowest first) — earlier tasks often set up context for later ones.

### TaskList Usage

Teammates should check `TaskList` after completing each task to find available work:

```
TaskList({ team_name: "my-project" })
→ Returns all tasks with status, owner, and blocked-by info
```

Claim an unassigned task:
```
TaskUpdate({ team_name: "my-project", task_id: "N", owner: "my-name" })
```

## Communication (SendMessage)

### Message Types

| Type | Use When |
|------|----------|
| `message` | Direct message to a specific teammate |
| `broadcast` | Critical team-wide announcement (use sparingly — expensive) |
| `shutdown_request` | Ask a teammate to gracefully exit |
| `shutdown_response` | Approve or reject a shutdown request |
| `plan_approval_response` | Approve or reject a teammate's plan |

### DM Example

```
SendMessage({
  type: "message",
  recipient: "security-reviewer",  // Use NAME, not agent ID
  content: "Please also check the payment module",
  summary: "Adding payment module to scope"
})
```

### Broadcast (use sparingly)

```
SendMessage({
  type: "broadcast",
  content: "Stop all work — critical blocker found in auth module",
  summary: "Critical blocker: halt work"
})
```

Broadcasting sends a separate delivery to every teammate. With N teammates, that's N API round-trips. Reserve for genuine team-wide blockers.

## Teammate Behavior

### Discovering Team Members

Read the team config to find other members:

```
Read ~/.claude/teams/<team-name>/config.json
→ members array with name, agentId, agentType
```

Always use the **name** field (not agentId) for `recipient` in SendMessage.

### Idle State

Teammates go idle after every turn — this is normal. Idle ≠ unavailable. Sending a message to an idle teammate wakes them.

### Key Teammate Rules

- Mark exactly ONE task `in_progress` at a time
- Use `TaskUpdate` (not `SendMessage`) to report task completion
- System sends idle notifications automatically — no need for status JSON messages
- All communication requires `SendMessage` — plain text output is NOT visible to the team lead

## Shutdown Procedures

### Graceful Shutdown (Lead → Teammates)

```
SendMessage({
  type: "shutdown_request",
  recipient: "security-reviewer",
  content: "All tasks complete, wrapping up"
})
```

### Teammate Approves Shutdown

```
SendMessage({
  type: "shutdown_response",
  request_id: "<id from shutdown_request JSON>",
  approve: true
})
```

### Cleanup (Lead)

After all teammates shut down:

```
TeamDelete()
→ Removes ~/.claude/teams/<name>/ and ~/.claude/tasks/<name>/
```

TeamDelete fails if teammates are still active.

## Common Patterns

### Parallel Code Review

```
TeamCreate: "code-review"
Tasks: security-audit, performance-review, correctness-check
Teammates: security-agent, performance-agent, correctness-agent (all parallel)
Lead: collects results, synthesizes findings
```

### Parallel Implementation with Worktrees

```
TeamCreate: "feature-impl"
Tasks: backend-api, frontend-ui, tests
Teammates: each spawned with isolation: "worktree"
Lead: delegates git push (sub-agents must not push independently in sandbox)
```

### Blocked Task Resolution

If a task is blocked on another, set the `blocked_by` field in TaskCreate. Teammates check TaskList and skip blocked tasks until the blocking task is completed.

## Team Roles

| Role | Behavior | When to Use |
|------|----------|-------------|
| **Lead** | Orchestrates, assigns tasks, receives results | Always — coordinates the team |
| **Teammate** | Parallel execution with messaging | Ongoing collaboration, progress reporting |
| **Subagent** | Focused, isolated, returns single result | Simple bounded tasks, no coordination needed |

## Sandbox Considerations

In web sessions (`CLAUDE_CODE_REMOTE=true`):
- Sub-agents (teammates) may encounter TLS errors on `git push` — delegate all push/PR operations to the lead
- Each teammate runs in its own process context
- Worktree isolation is recommended for independent filesystem changes

## Agentic Optimizations

| Context | Approach |
|---------|----------|
| Quick parallel review | Spawn 2–4 teammates, broadcast task assignments |
| Large codebase split | Assign directory subsets as separate tasks |
| Long-running work | Background teammates, poll via TaskList |
| Minimize API cost | Prefer `message` over `broadcast` |
| Fast shutdown | Send shutdown_request to each teammate, then TeamDelete |

## Quick Reference

### Workflow Checklist

- [ ] `TeamCreate` with team name and description
- [ ] `TaskCreate` for each work unit
- [ ] Spawn teammates via Agent tool with `team_name` and `name`
- [ ] `TaskUpdate` to assign tasks to teammates (or let teammates self-assign)
- [ ] Receive messages automatically; respond via `SendMessage`
- [ ] `SendMessage shutdown_request` to each teammate when done
- [ ] `TeamDelete` after all teammates shut down

### Key Paths

| Path | Contents |
|------|----------|
| `~/.claude/teams/<name>/config.json` | Team members (name, agentId, agentType) |
| `~/.claude/tasks/<name>/` | Shared task list directory |

### Common Mistakes

| Mistake | Correct Approach |
|---------|-----------------|
| Using agentId as recipient | Use `name` field from config.json |
| Sending broadcast for every update | Use `message` for single-recipient comms |
| Polling for messages | Messages delivered automatically — just wait |
| Sending JSON status messages | Use `TaskUpdate` for status, plain text for messages |
| Sub-agent pushes to remote | Delegate push to lead orchestrator |
| TeamDelete before shutdown | Shutdown all teammates first |

## Related Rules

- `.claude/rules/agent-development.md` — agent file structure, model selection, worktree isolation
- `.claude/rules/agentic-permissions.md` — granular tool permission patterns
- `.claude/rules/sandbox-guidance.md` — web sandbox constraints and push delegation
