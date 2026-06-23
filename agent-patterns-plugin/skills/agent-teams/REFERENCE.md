# Agent Teams — Reference

Supporting material for [`agent-teams`](SKILL.md). Loaded on demand. The
operational workflow and decision tables live in `SKILL.md`; this file carries
the worked setup examples, communication snippets, shutdown procedures, the
worktree path-resolution recovery routine, and common dispatch patterns.

> **BREAKING (Claude Code 2.1.178)**: `TeamCreate` / `TeamDelete` were removed.
> Every session has **one implicit team** when `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1`
> is set — there is no team to create, name, or delete. `team_name` is accepted
> but ignored on the tools that took it; omit it. The examples below use the
> implicit team.

## Team architecture

```
Lead Agent (orchestrator)        [implicit team — CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1]
    ├── Agent tool — spawns teammate agents (give each a `name`)
    ├── SendMessage — communicates with teammates
    ├── TaskCreate/TaskUpdate — creates and assigns shared tasks
    └── Teammates (run in parallel)
            ├── TaskList/TaskUpdate — claim and complete tasks
            └── SendMessage — report back to lead (by `name`)
```

## Team setup workflow

### 1. Create initial tasks

The team is implicit — start by creating work, not a team:

```
TaskCreate({
  title: "Implement security review",
  description: "Audit auth module for vulnerabilities",
  status: "pending"
})
```

### 2. Spawn teammates

```
Agent tool with:
  subagent_type: "agents-plugin:security-audit"
  name: "security-reviewer"
  prompt: "Work on the security review task in the shared task list..."
```

(`team_name` is accepted but ignored — there is one implicit team. Omit it.)

### 3. Assign tasks

```
TaskUpdate({
  task_id: "task-1",
  owner: "security-reviewer",
  status: "in_progress"
})
```

### 4. Receive results

Teammates send messages automatically — delivered to the lead's inbox between
turns. No polling needed.

## TaskList usage

Teammates check `TaskList` after completing each task to find available work,
claiming tasks in **ID order** (lowest first — earlier tasks set up context):

```
TaskList()
TaskUpdate({ task_id: "N", owner: "my-name" })
```

## Communication (SendMessage)

### DM example

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

Broadcasting sends a separate delivery to every teammate — N teammates = N API
round-trips. Reserve for genuine team-wide blockers.

### Discovering team members

The reliable handle is the `name` you assign each teammate at spawn — use it
directly as the `recipient`. Implicit-team membership state lives under
`~/.claude/teams/` (members carry name, agentId, agentType) if you need to
enumerate peers, but you should rarely need to read it: spawn with a known
`name` and address by that `name`.

Always use the **name** field (not agentId) for `recipient` in SendMessage.

## Shutdown procedures

### Graceful shutdown (lead → teammate)

```
SendMessage({
  type: "shutdown_request",
  recipient: "security-reviewer",
  content: "All tasks complete, wrapping up"
})
```

### Teammate approves shutdown

```
SendMessage({
  type: "shutdown_response",
  request_id: "<id from shutdown_request JSON>",
  approve: true
})
```

### Cleanup (lead)

There is no team to delete (2.1.178 removed `TeamDelete`). Cleanup **is** the
shutdown handshake: once every teammate has approved its `shutdown_request`, the
team is wound down. Confirm no teammate is still active before ending the
session; use `TaskStop` to halt a background teammate that is not responding to a
shutdown request.

## Out-of-scope discovery protocol

Include this verbatim in every agent's prompt when that agent has an exclusive
write scope:

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

This prevents the "investigate out of scope → exhaust budget → truncated
summary" failure mode. The lead addresses the dependency before the next phase
or assigns a follow-up issue.

## Worktree-isolated Edit/Write path resolution (#1091)

> **Known failure mode (worktree isolation):** Agents launched with
> `isolation: "worktree"` may have `Edit`/`Write` tool calls silently resolve
> relative paths against the **parent repo** rather than the agent's worktree,
> even though `Bash` commands and `git status` correctly operate inside the
> worktree. The agent gets no immediate signal — commits can land on a sibling
> agent's branch or on the parent repo's working tree. Cleanup requires
> cherry-pick + rebase drop-if-upstream after the fact.
>
> Tracking: laurigates/claude-plugins#1091

The bug lives in Claude Code's worktree path-resolution layer (upstream). Until
fixed, harden every worktree-isolated agent prompt with the preamble below and
run the post-flight check before merging.

### Recommended agent-prompt preamble

Paste verbatim at the **top** of any worktree-isolated agent's prompt — before
any other instructions:

```
**First action MUST be:**

  pwd
  git rev-parse --show-toplevel
  ls -la

**All file edits must use absolute paths rooted at your worktree.**
**If `Edit` or `Write` appears to target anything outside your worktree,
stop and report — do not retry.**
```

Absolute paths bypass the relative-resolution bug entirely; the "stop and
report" clause prevents the recovery-by-retry loop that compounds the damage.

### Lead post-flight check

After agents return, run from the **parent repo** before merging:

```bash
git diff origin/main..HEAD     # parent's intended branch should be clean
git status --porcelain         # no straggler edits in parent worktree
```

If either is non-empty, an agent's `Edit`/`Write` leaked into the parent.

### Recovery pattern

1. **Cherry-pick** the commit onto the intended branch: `git cherry-pick <stray-sha>`.
2. **Rewrite the wrong branch** to drop the duplicate:
   `git rebase --onto <new-base> <old-base> <wrong-branch>` (with
   `git config rebase.dropOnUpstream true`, or `git rebase -i` and delete the line).
3. **Verify** with `git log --oneline <wrong-branch> ^<intended-branch>` that
   only the wrong-branch's own commits remain.

For the broader concurrency context, see `.claude/rules/agent-coworker-detection.md`.

## Common patterns

### Parallel code review

```
Tasks: security-audit, performance-review, correctness-check (TaskCreate)
Teammates: security-agent, performance-agent, correctness-agent (Agent, all parallel)
Lead: collects results, synthesizes findings
```

### Parallel implementation with worktrees

```
Tasks: backend-api, frontend-ui, tests (TaskCreate)
Teammates: each spawned via Agent with isolation: "worktree"
Lead: delegates git push (sub-agents must not push independently in sandbox)
```

### Multi-phase architecture refactor

```
(implicit team — CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1)
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

Real-world outcome: +1850/−1826 lines, zero file-scope collisions across 6
agents, tests exposed a bug on first build.

### Blocked task resolution

Set the `blocked_by` field in TaskCreate. Teammates check TaskList and skip
blocked tasks until the blocking task is completed.

## Team roles

| Role | Behavior | When to Use |
|------|----------|-------------|
| **Lead** | Orchestrates, assigns tasks, receives results | Always — coordinates the team |
| **Teammate** | Parallel execution with messaging | Ongoing collaboration, progress reporting |
| **Subagent** | Focused, isolated, returns single result | Simple bounded tasks, no coordination needed |
