---
name: agent-teams
description: |
  Configure and orchestrate Claude Code agent teams (TeamCreate, SendMessage, TaskUpdate
  workflow). Use when you need multiple agents working in parallel on a complex task,
  want to coordinate background agents with messaging, or are setting up a lead/teammate
  architecture with a shared task list. Teams are experimental — enable with
  --enable-teams flag.
user-invocable: false
allowed-tools: Read, Glob, Grep, TodoWrite
model: opus
created: 2026-03-03
modified: 2026-05-06
reviewed: 2026-04-25
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

## Sub-Agent Caveat: Spawn Teams from the Main Thread

`TeamCreate`, `Agent`, and the related parallel-spawn tools may not be present in a **sub-agent's** tool surface, even if the parent conversation has them. A sub-agent designed to orchestrate its own team can silently degrade to sequential single-thread execution — same content, much longer wall-clock — without surfacing the failure until its post-completion summary.

**Authoring guidance:**

| Situation | Recommended pattern |
|-----------|---------------------|
| Fan-out from the main conversation | Spawn the team / parallel `Agent` calls directly — full tool surface available |
| Sub-agent orchestrating its own team | Avoid by design when possible: split the work so the main thread does the fan-out |
| Sub-agent must orchestrate a team | Detect tool availability up front; report sequential fallback as a first-class outcome |

**Detection contract for coordinating sub-agents:**

Brief the orchestrating sub-agent to verify before dispatching:

```
1. Confirm Agent / TeamCreate are callable. If unavailable (e.g. ToolSearch
   does not surface them, or invocation returns "tool not found"), do NOT
   silently fall back.
2. Report the constraint as the first line of the final summary:
   "Parallel fan-out unavailable in this sandbox; executed sequentially."
3. Continue sequentially with the same input contract — outputs should be
   identical in content, only longer in wall-clock.
```

The wall-clock cost is real: a 5-way fan-out that degrades to sequential takes ~5× longer. Plan top-level orchestration in the main conversation when you can; reserve sub-agent orchestrators for cases where the team's outputs do not need to feed back into the main thread.

> Evidence: a Phase 2 portability-audit dispatch instructed a coordinating sub-agent to spawn 5 parallel auditors via `Agent`; the `Agent` tool was not registered in the sub-agent's sandbox. Output was equivalent but wall-clock was much longer than designed, and the failure surfaced only in the post-completion note.

## Core Concepts

### Team Architecture

```
Lead Agent (orchestrator)
    ├── TeamCreate — creates team + shared task list
    ├── Agent tool — spawns teammate agents
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

Use the Agent tool to spawn each teammate with the team context:

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

## Lead Preflight Checklist

Before drafting the PRP and launching agents, run these checks:

| Check | Command | Why |
|-------|---------|-----|
| Next ADR/PRD/PRP sequence number | `ls docs/blueprint/adrs/ \| sort -V \| tail -1` | Prevents numbering collisions when agents write docs in parallel |
| Filename conflicts | `git ls-files \| grep <filename>` | Agent scope tables can't guard against a stale mental model of the tree |
| Hardware pin budget (embedded) | Read `pin_config.h` or equivalent | Prevents pin assignments overlapping across Phase 1 agents |

A 30-second sweep prevents multi-edit renaming work after agents return.

## Out-of-Scope Discovery Protocol

Include this protocol in every agent's prompt when that agent has an exclusive write scope:

```markdown
### Out-of-scope discovery protocol

If you discover that a file outside your declared write scope needs to change
for your deliverables to work:

1. **STOP immediately.** Do not read, investigate, or edit the out-of-scope file.
2. In your final summary, include a section titled `Out-of-scope dependencies` that lists:
   - The file(s) that need changes
   - What changes are needed (one line each)
   - Which of your deliverables is blocked without those changes
3. Exit. The lead will triage and either expand your scope, reassign to another agent,
   or handle it directly.
```

This prevents the "investigate out of scope → exhaust budget → truncated summary" failure mode.
The lead can then address the dependency before the next phase or assign a follow-up issue.

## Worktree-Isolated Edit/Write Path Resolution

> **Known failure mode (worktree isolation):** Agents launched with
> `isolation: "worktree"` may have `Edit`/`Write` tool calls silently
> resolve relative paths against the **parent repo** rather than the
> agent's worktree, even though `Bash` commands and `git status`
> correctly operate inside the worktree. The agent gets no immediate
> signal that file writes are landing on the wrong branch — commits
> can land on a sibling agent's branch or on the parent repo's
> working tree. Cleanup requires cherry-pick + rebase
> drop-if-upstream after the fact.
>
> Tracking: laurigates/claude-plugins#1091

The bug lives in Claude Code's worktree path-resolution layer (upstream).
Until it is fixed, harden every worktree-isolated agent prompt with the
preamble below and run the post-flight check before merging.

### Recommended agent-prompt preamble

Paste this verbatim at the **top** of any worktree-isolated agent's
prompt — before any other instructions or task description:

```
**First action MUST be:**

  pwd
  git rev-parse --show-toplevel
  ls -la

**All file edits must use absolute paths rooted at your worktree.**
**If `Edit` or `Write` appears to target anything outside your worktree,
stop and report — do not retry.**
```

The three commands give the agent (and the transcript reader) an
unambiguous signal of where it actually is. Absolute paths bypass the
relative-resolution bug entirely. The "stop and report" clause prevents
the recovery-by-retry loop that compounds the damage.

### Lead post-flight check

After agents return, run from the **parent repo** before merging:

```bash
git diff origin/main..HEAD     # parent's intended branch should be clean
git status --porcelain         # no straggler edits in parent worktree
```

If either is non-empty, an agent's `Edit`/`Write` leaked into the parent.
Inspect the diff before any further git operations.

### Recovery pattern

If a stray commit lands on the wrong branch:

1. **Cherry-pick** the commit onto the intended branch:
   `git cherry-pick <stray-sha>`.
2. **Rewrite the wrong branch** to drop the duplicate. Rebase onto the
   correct base with drop-if-upstream so git removes the commit that
   already exists upstream:
   `git rebase --onto <new-base> <old-base> <wrong-branch>` (run with
   `git config rebase.dropOnUpstream true` or use `git rebase -i` and
   delete the duplicate line).
3. **Verify** with `git log --oneline <wrong-branch> ^<intended-branch>`
   that only the wrong-branch's own commits remain.

For the broader concurrency context (shared-clone vs. worktree
coordination), see `.claude/rules/agent-coworker-detection.md`.

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

### Multi-Phase Architecture Refactor

```
Phase 1 (3 parallel):  Framework upgrade + new module scaffolding + ADR draft
Phase 2 (1 serialized): Reactive executor — depends on Phase 1 contracts
Phase 3 (1 serialized): Wire-up + legacy deletion — exclusive main.c owner
Phase 4 (2 parallel):  Host tests + documentation finalization

Key rules:
- One owner per file across ALL phases (exclusive write scope per agent)
- "Agent writes, lead commits" — keep branch coherent between phases
- Phase boundaries = commit points (clean checkpoint semantics)
- Phase 3 deletion runs AFTER Phases 1–2 finalize their contracts
```

Real-world outcome: +1850/−1826 lines, zero file-scope collisions across 6 agents,
tests exposed a bug on first build. See also: the Out-of-Scope Discovery Protocol above —
include it in every focused-scope agent prompt.

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

## Related Skills and Rules

- `parallel-agent-dispatch` — worktree preflight, scope budgets, and the Return Contract that every teammate must emit on exit. Team dispatches are a superset of plain parallel fan-out; follow both.
- `.claude/rules/agent-development.md` — agent file structure, model selection, worktree isolation
- `.claude/rules/agentic-permissions.md` — granular tool permission patterns
- `.claude/rules/sandbox-guidance.md` — web sandbox constraints and push delegation
