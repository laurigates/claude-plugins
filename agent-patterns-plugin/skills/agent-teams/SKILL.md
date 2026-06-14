---
name: agent-teams
description: Configure Claude Code agent teams (TeamCreate, SendMessage, TaskUpdate). Use when running parallel agents, coordinating with messaging, or setting up a lead/teammate architecture.
user-invocable: false
allowed-tools: Read, Glob, Grep, TodoWrite
model: opus
created: 2026-03-03
modified: 2026-06-14
reviewed: 2026-06-14
---

# Agent Teams

> **Experimental**: Agent teams require the `--enable-teams` flag and may change between Claude Code versions.

For the worked setup examples, communication snippets, shutdown procedures, the
worktree path-resolution recovery routine, and common dispatch patterns, see
[REFERENCE.md](REFERENCE.md).

## When to Use This Skill

| Use agent teams when... | Use subagents instead when... |
|------------------------|------------------------------|
| Multiple agents need to work in parallel | Tasks are sequential and interdependent |
| Ongoing communication between agents is needed | One focused task produces one result |
| Background tasks need progress reporting | Agent output feeds directly into next step |
| Complex workflows benefit from task coordination | Simple, bounded, isolated execution |
| Independent changes to the same codebase (with worktrees) | Context sharing is fine and efficient |

## Sub-Agent Caveat: Spawn Teams from the Main Thread

`TeamCreate`, `Agent`, and the related parallel-spawn tools may not be present in
a **sub-agent's** tool surface, even if the parent conversation has them. A
sub-agent designed to orchestrate its own team can silently degrade to sequential
single-thread execution — same content, ~5× longer wall-clock — without surfacing
the failure until its post-completion summary.

| Situation | Recommended pattern |
|-----------|---------------------|
| Fan-out from the main conversation | Spawn the team / parallel `Agent` calls directly — full tool surface available |
| Sub-agent orchestrating its own team | Avoid by design: split the work so the main thread does the fan-out |
| Sub-agent must orchestrate a team | Detect tool availability up front; report sequential fallback as a first-class outcome |

**Detection contract** to brief into a coordinating sub-agent: confirm
`Agent`/`TeamCreate` are callable; if not, do **not** silently fall back — report
"Parallel fan-out unavailable in this sandbox; executed sequentially." as the
first line of the summary, then continue sequentially with the same input
contract. Plan top-level orchestration in the main conversation when you can.

## Native Team Tools

| Tool | Purpose |
|------|---------|
| `TeamCreate` | Create team and shared task list directory |
| `TeamDelete` | Clean up team when all work is complete (fails if teammates active) |
| `SendMessage` | Send DMs, broadcasts, shutdown requests, plan approvals |
| `TaskOutput` | Get output from a background agent |
| `TaskStop` | Stop a running background agent |

The setup sequence — `TeamCreate` → `TaskCreate` → spawn teammates via the
`Agent` tool (with `team_name` + `name`) → `TaskUpdate` to assign → receive
results automatically — is shown with full code in
[REFERENCE.md → Team setup workflow](REFERENCE.md#team-setup-workflow). Teammate
messages are delivered to the lead's inbox between turns; no polling needed.

## Task Management

| State | Meaning |
|-------|---------|
| `pending` | Not yet started |
| `in_progress` | Assigned and active (one at a time per teammate) |
| `completed` | Finished successfully |
| `blocked` | Waiting on another task (`blocked_by` field) |

Teammates claim tasks in **ID order** (lowest first) via `TaskList` +
`TaskUpdate`, and skip blocked tasks until their blocker completes.

## Communication (SendMessage)

| Type | Use When |
|------|----------|
| `message` | Direct message to a specific teammate (recipient = **name**, not agentId) |
| `broadcast` | Critical team-wide announcement (N teammates = N round-trips — use sparingly) |
| `shutdown_request` / `shutdown_response` | Graceful teammate exit handshake |
| `plan_approval_response` | Approve or reject a teammate's plan |

DM, broadcast, and discovery (`Read ~/.claude/teams/<name>/config.json` →
`members`) examples are in
[REFERENCE.md → Communication](REFERENCE.md#communication-sendmessage).

### Key Teammate Rules

- Mark exactly ONE task `in_progress` at a time.
- Use `TaskUpdate` (not `SendMessage`) to report task completion.
- Idle after every turn is normal — idle ≠ unavailable; a message wakes a teammate.
- All communication requires `SendMessage` — plain text output is NOT visible to the lead.
- Use the **name** field (not agentId) for `recipient`.

## Lead Preflight Checklist

Before drafting the PRP and launching agents, a 30-second sweep prevents
multi-edit renaming work after agents return:

| Check | Command | Why |
|-------|---------|-----|
| Next ADR/PRD/PRP sequence number | `ls docs/blueprint/adrs/ \| sort -V \| tail -1` | Prevents numbering collisions in parallel doc writes |
| Filename conflicts | `git ls-files \| grep <filename>` | Scope tables can't guard against a stale mental model of the tree |
| Hardware pin budget (embedded) | Read `pin_config.h` or equivalent | Prevents pin assignments overlapping across Phase 1 agents |

## Out-of-Scope Discovery Protocol

Include the out-of-scope discovery protocol in every agent's prompt when that
agent has an exclusive write scope — it prevents the "investigate out of scope →
exhaust budget → truncated summary" failure mode. Copy the verbatim block from
[REFERENCE.md → Out-of-scope discovery protocol](REFERENCE.md#out-of-scope-discovery-protocol):
the agent **stops immediately** on an out-of-scope dependency, lists it under an
`Out-of-scope dependencies` summary section, and exits for the lead to triage.

## Worktree Isolation Hazard

Worktree-isolated agents can have `Edit`/`Write` silently resolve relative paths
against the **parent repo** instead of their worktree (upstream bug
[#1091](https://github.com/laurigates/claude-plugins/issues/1091)), landing
commits on the wrong branch with no immediate signal. Harden every
worktree-isolated prompt with the absolute-path preamble, run the lead
post-flight check (`git diff origin/main..HEAD` + `git status --porcelain` from
the parent), and use the cherry-pick + rebase recovery — all in
[REFERENCE.md → Worktree path resolution](REFERENCE.md#worktree-isolated-editwrite-path-resolution-1091).
See also `.claude/rules/agent-coworker-detection.md`.

## Sandbox Considerations

In web sessions (`CLAUDE_CODE_REMOTE=true`):

- Sub-agents (teammates) may encounter TLS errors on `git push` — delegate all push/PR operations to the lead.
- Each teammate runs in its own process context.
- Worktree isolation is recommended for independent filesystem changes.

## Agentic Optimizations

| Context | Approach |
|---------|----------|
| Quick parallel review | Spawn 2–4 teammates, assign tasks |
| Large codebase split | Assign directory subsets as separate tasks |
| Long-running work | Background teammates, poll via TaskList |
| Minimize API cost | Prefer `message` over `broadcast` |
| Fast shutdown | Send shutdown_request to each teammate, then TeamDelete |

## Quick Reference

### Workflow Checklist

- [ ] `TeamCreate` with team name and description
- [ ] `TaskCreate` for each work unit
- [ ] Spawn teammates via Agent tool with `team_name` and `name`
- [ ] `TaskUpdate` to assign tasks (or let teammates self-assign)
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

- `parallel-agent-dispatch` — worktree preflight, scope budgets, and the Return Contract every teammate must emit on exit. Team dispatches are a superset of plain parallel fan-out; follow both.
- `.claude/rules/agent-development.md` — agent file structure, model selection, worktree isolation
- `.claude/rules/agentic-permissions.md` — granular tool permission patterns
- `.claude/rules/sandbox-guidance.md` — web sandbox constraints and push delegation
