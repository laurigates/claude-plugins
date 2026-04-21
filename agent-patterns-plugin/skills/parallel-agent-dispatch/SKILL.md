---
name: parallel-agent-dispatch
description: |
  Dispatch contract for any workflow that spawns more than one agent in parallel —
  whether via the native TeamCreate / agent-teams flow or plain parallel Agent tool
  fan-out. Covers the three recurring failure modes: worktree hygiene collisions,
  unbounded agent scope leading to context overflow, and silent agent exits that
  leave loose ends invisible to the orchestrator. Use when planning to spawn two
  or more agents that run concurrently, when authoring a lead/orchestrator prompt
  that will fan out work, or when recovering from a silent agent exit or worktree
  collision. Complements agent-teams (TeamCreate mechanics) and
  custom-agent-definitions (agent file structure).
user-invocable: false
allowed-tools: Read, Glob, Grep, TodoWrite
created: 2026-04-21
modified: 2026-04-21
reviewed: 2026-04-21
---

# Parallel Agent Dispatch

Conventions that apply every time more than one agent runs in parallel. Prevents
the top failure modes observed across real multi-agent sessions: dirty-worktree
cross-contamination, context overflow mid-task, and silent exits that require
manual salvage from orphan branches.

## When to Use This Skill

Activate whenever the orchestrator is about to spawn **>1 agent in parallel**:

- Plain `Agent` tool fan-out (N concurrent invocations in one message)
- `TeamCreate` + teammate spawn via `agent-teams`
- Worktree-isolated parallel implementation across multiple repos or features
- Parallel investigation / audit swarms

Single-agent delegation does not need this contract — `agent-teams`'
out-of-scope protocol is sufficient for one-off subagents.

## The Three Pillars

### 1. Worktree Preflight

Before spawning, the orchestrator must verify:

| Check | Rationale |
|-------|-----------|
| Main working tree is clean (`git status --porcelain` empty) | Agents inherit cwd; uncommitted changes cross-contaminate worktrees |
| No existing worktree at each planned path (`git worktree list`) | Nested or duplicate worktrees are the #1 source of salvage work |
| Each agent gets a **unique** branch name | Prevents commits landing on the wrong branch when cwd resolution drifts |
| Shared counters snapshot (next ADR/PRP number, feature-tracker IDs) | Prevents numbering collisions in parallel doc writes |

If any check fails, **refuse to dispatch** and report the blocker. Do not
"clean up" uncommitted user work — surface it and ask.

See also: `agent-teams` Lead Preflight Checklist for file-scope and pin-budget
checks that stack on top of these.

### 2. Scope Budget (per-agent prompt rules)

Every agent prompt must declare:

- **File scope**: exclusive write paths (glob or explicit list). No agent may
  write outside its declared scope. Out-of-scope discovery → stop and report
  (see `agent-teams`).
- **Read budget**: soft cap on files examined before producing output. A
  reasonable default is "≤10 files per exploration hop, ≤3 hops before
  returning a result."
- **Output budget**: expected length of the return summary. Discourages
  agents from echoing full file contents when a diff or line reference will do.

These budgets are what prevents the "security audit agent hit context limits"
and "prompt is too long" failure modes — without them, a well-intentioned
agent exhausts its window on exploration and truncates its actual deliverable.

### 3. Return Contract (mandatory structured summary)

Every parallel agent must end its run with this schema as its final message,
regardless of success or failure:

```markdown
## Result
- status: success | partial | failed
- branch: <branch-name>
- pr: <url> | not opened: <reason>
- commits: <N> (<short-sha-range>)
- worktree: <path> (clean | dirty: <file list>)

## Scope delivered
- 2–4 bullets on what actually landed

## Deferred / skipped
- Anything explicitly out of scope or punted
- Empty is fine — the section must exist

## Issues encountered
- Hook fires, retries, test flakes, manual workarounds
- Unexpected findings worth surfacing (e.g. second root cause)
- Empty is fine — the section must exist

## Orchestrator action needed
- none | <one line: what the lead must do before next phase>
```

Include the schema verbatim in every dispatched agent's prompt under a heading
like `### Return contract (mandatory)`. Do not paraphrase — agents follow
concrete schemas more reliably than prose instructions.

## Why the Schema Matters

| Failure mode (observed) | Schema field that catches it |
|-------------------------|------------------------------|
| Silent mid-task exit | No return message → orchestrator treats as stall and resumes |
| Work on wrong branch | `branch` + `worktree` fields force self-report |
| Uncommitted loose ends | `worktree: dirty` is explicit, impossible to gloss over |
| Second root cause missed | `Issues encountered` has a home for "bonus" findings |
| Follow-up work invisible | `Deferred / skipped` and `Orchestrator action needed` |
| Budget overrun | `status: partial` + explicit deferred list beats a truncated claim of success |

## Who Pushes?

Agents push their own commits in the normal case — worktree isolation plus
per-agent branches makes this safe and keeps the main orchestrator context
lean. Centralizing pushes through the lead collapses the isolation benefit
and bloats the lead's transcript with N agents' worth of diffs.

Exceptions where the lead should push instead:

- **Web sandbox sessions** (`CLAUDE_CODE_REMOTE=true`) — teammates may hit
  TLS errors on push. See `agent-teams` Sandbox Considerations.
- **Cross-agent dependencies** where Phase 1 agents' commits must land
  together as a single merge base for Phase 2.
- **Explicit user instruction** ("I'll push manually, just commit").

Default remains: agent commits, agent pushes, agent opens its own PR, agent
reports the URL back in the Return Contract.

## Handling a Missing Return

If an agent exits without emitting the Return Contract:

1. Treat as a **silent stall**, not a success.
2. Check the agent's worktree for uncommitted work (`git status`) and
   committed-but-unpushed branches (`git log --branches --not --remotes`).
3. Either resume the agent with a message asking for the missing summary,
   or salvage the work yourself and file a tracking issue noting the stall.
4. Do **not** report the parent task as complete until every spawned agent
   has produced a Return Contract (or been explicitly accounted for).

## Composition with agent-teams

`agent-teams` covers the TeamCreate / SendMessage / TaskUpdate mechanics.
This skill adds the dispatch-time contract that applies to both team and
non-team parallel fan-out. When both apply, follow both — the out-of-scope
protocol from `agent-teams` slots naturally into the `Issues encountered`
and `Deferred / skipped` sections of the Return Contract here.

## Quick Reference

### Orchestrator Checklist

- [ ] Working tree clean; no conflicting worktrees
- [ ] Each agent has unique branch name and exclusive file scope
- [ ] Each prompt includes file/read/output budgets
- [ ] Each prompt includes the Return Contract schema verbatim
- [ ] Agents authorized to push their own commits (unless sandbox/dependency exception)
- [ ] Every returned summary parsed; missing returns treated as stalls

### Common Mistakes

| Mistake | Correct Approach |
|---------|-----------------|
| Spawning agents from a dirty main tree | Commit or stash first; refuse to dispatch on dirty state |
| Scope described in prose, not glob | Explicit write-path list per agent |
| "Report back when done" with no schema | Include Return Contract verbatim in every prompt |
| Treating agent silence as success | No Return Contract = stall; investigate before reporting done |
| Centralizing pushes as a default | Agent pushes its own work; lead pushes only on sandbox/dependency exceptions |

## Related

- `agent-teams` — TeamCreate/SendMessage mechanics, out-of-scope discovery protocol
- `custom-agent-definitions` — agent file structure, tool restrictions, context forking
- `.claude/rules/agent-development.md` — agent authoring conventions
- `.claude/rules/sandbox-guidance.md` — when sandbox constraints override push defaults
