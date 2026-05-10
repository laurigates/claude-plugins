---
name: task-coordinate
description: Surface the next N unblocked taskwarrior tasks sorted by urgency, skipping lock-contending tasks. Use when planning a parallel-agent-dispatch wave or deciding which tasks share a dispatch slot.
args: "[--n=N] [--lock=<resource>] [--wave] [--project=<name>] [--all]"
allowed-tools: Bash(task *), Bash(git rev-parse *), Bash(jq *), Read, TodoWrite
argument-hint: optional count (default 3) and lock filter
created: 2026-04-24
modified: 2026-05-09
reviewed: 2026-05-09
---

# /taskwarrior:task-coordinate

Next-candidate-agent surfacing for parallel / wave dispatch. Pairs with `agent-patterns-plugin:parallel-agent-dispatch` and `workflow-orchestration-plugin:workflow-wave-dispatch`.

## When to Use This Skill

| Use this skill when... | Use `task-status` / `task-add` / `task-done` instead when... |
|---|---|
| Picking the top-N unblocked tasks for a parallel-agent wave | Producing a full queue audit (pending + blocked + drift) — use `task-status` |
| Filtering candidates that contend on the same exclusive lock (`ghidra`, `migration`) | Filing a new task before there is anything to coordinate — use `task-add` |
| Emitting a `--wave` brief for an orchestrator to fan out | Closing a task that already landed via commit — use `task-done` |

## Context

- Task CLI available: !`task --version`
- Git toplevel: !`git rev-parse --show-toplevel`
- Known projects: !`task _projects`

## Parameters

Parse `$ARGUMENTS`:

- `--n=N` — number of candidates to surface (default 3)
- `--lock=<resource>` — exclude candidates that need the named lock (e.g. `ghidra`, `migration`, `task-bulk`)
- `--wave` — format output as a wave brief (orchestrator-ready)
- `--project=<name>` — override the auto-detected project filter
- `--all` — opt out of project filtering (cross-project wave; rare — usually wrong for dispatch)
- `--include-active` — include `+ACTIVE` (already-claimed) tasks in candidate ranking. Default behaviour excludes them so a wave is never dispatched onto work another agent has already started via `/taskwarrior:task-claim`.
- `--stale-after=N` — threshold (hours) for flagging a `+ACTIVE` claim as stale in the report. Default 4. Stale claims are reported only — never auto-stopped.

### Project resolution

Default behaviour is project-scoped. A wave dispatch almost always wants
candidates from a single repo, so cross-project candidates are filtered
out by default. Resolve `$PROJECT` in this order:

1. `--project=<name>` if provided.
2. `--all` → no project filter (cross-project wave).
3. Basename of the path reported as `Git toplevel` in Context.
4. If no git repo, basename of cwd.

## Execution

Execute this workflow:

### Step 1: Load unblocked pending tasks

Substitute the literal project name into the filter (no `$()` command
substitution — shell-operator protections will reject it). Default
behaviour excludes both `+BLOCKED` (depends-blocked) and `+ACTIVE`
(already claimed via `/taskwarrior:task-claim`):

```bash
task project:myrepo status:pending -BLOCKED -ACTIVE export \
  | jq 'sort_by(-.urgency) | .[] | {id, description, urgency, tags, bpid, depends}'
```

With `--include-active`, drop the `-ACTIVE` clause so already-claimed
tasks compete for ranking. With `--all`, drop the `project:` clause.
Never use `task next` — exits 1 on empty.

### Step 1b: Snapshot in-flight claims

In parallel with Step 1 (these are independent reads), collect the set
of currently-claimed tasks for the report:

```bash
task project:myrepo status:pending +ACTIVE export \
  | jq '.[] | {id, description, agent, pid, host, branch, worktree, start, urgency}'
```

Empty array is exit-0 from `task export` — safe in parallel batches.

### Step 1c: Detect stale claims

Filter the in-flight set for claims older than `--stale-after` hours:

```bash
task project:myrepo +ACTIVE start.before:now-4h export \
  | jq '.[] | {id, agent, host, branch, start}'
```

Stale claims are surfaced in the report only; `task-coordinate` never
calls `task stop` on its own. The orchestrator (or the original claimer)
decides whether to release.

### Step 2: Detect lock contenders

Classify each task by the locks implied by its tags or `bpid`:

| Tag / ID prefix | Implied lock |
|-----------------|--------------|
| `+re` on decomp work, `tmp/decomp/` in description | `ghidra` |
| `+migration`, bpid starts with `MIG-` | `migration` |
| `+bulk_task` | `task-bulk` (taskwarrior itself — single-writer) |
| Matching `bpdoc` in shared manifest | `manifest` |

Drop any candidate that matches the `--lock=` filter. Two tasks that
would contend on the same lock cannot share a wave — keep the one with
higher urgency, defer the other to the next wave.

### Step 3: Rank and cap

Keep the top N by urgency. If ties, prefer:

1. Tasks with a pre-existing `bpdoc` (scope is already written down)
2. Tasks without exclusive-lock contention
3. Tasks with earlier `entry` (older first)

### Step 4: Emit candidates

Lead the output with the resolved project scope so the orchestrator
knows the wave is single-repo (default) or cross-project (`--all`):

```
Project: myrepo (auto-detected from git toplevel)
```

Default format (compact):

```
1. #7   WO-012   Implement foo decoder                u:14.2
2. #11  WO-013   Add foo CLI subcommand               u:12.8
3. #15  WO-014   Document foo format spec             u:11.1
```

With `--wave`, emit a wave brief:

```
## Wave N candidates (3 agents, no lock contention)

| # | Task | Scope | Exclusion |
|---|------|-------|-----------|
| A | WO-012 (task #7)  | src/codec/foo.c, tests/foo.c | orchestrator-only: CMakeLists.txt |
| B | WO-013 (task #11) | cli/commands/foo.c           | orchestrator-only: CMakeLists.txt |
| C | WO-014 (task #15) | docs/format-spec/foo.md      | orchestrator-only: docs/blueprint/manifest.json |

Pre-allocated IDs: WO-012, WO-013, WO-014 (see parallel-agent-dispatch §Pre-Allocated Blueprint IDs).
```

### Step 5: Note deferred lock-contenders

If the rank step dropped any lock-contending candidates, report them as
deferred-to-next-wave with the lock name — the orchestrator decides
whether to pre-dump via `exclusive-lock-dispatch` or serialise.

### Step 6: Append in-flight + stale-claim sections

Always emit two trailing sections so the orchestrator sees the full
state of the project queue, not just the dispatchable subset:

```
## In flight (claimed)

| Task | Agent | Branch | Host | Started |
|------|-------|--------|------|---------|
| #4 (WO-008) | claude-a1b2c3d4 | feature/parser | host-1 | 2h ago |
| #9 (WO-011) | claude-9f8e7d6c | feature/api    | host-2 | 30m ago |

## Stale claims (>4h)

| Task | Agent | Started | Action |
|------|-------|---------|--------|
| #2 (WO-005) | claude-44556677 | 6h ago | Investigate; release with `/taskwarrior:task-release 2` if abandoned |
```

Empty sections render as "(none)". Never auto-stop a stale claim —
report only, per the v1 design.

## Agentic Optimizations

| Context | Command |
|---------|---------|
| Project unclaimed + unblocked | `task project:myrepo status:pending -BLOCKED -ACTIVE export \| jq 'sort_by(-.urgency)'` |
| Include claimed (rare) | drop `-ACTIVE` clause |
| In-flight snapshot | `task project:myrepo +ACTIVE export \| jq '.[] \| {id, agent, branch, start}'` |
| Stale claims | `task project:myrepo +ACTIVE start.before:now-4h export \| jq` |
| Cross-project (`--all`) | `task status:pending -BLOCKED -ACTIVE export \| jq 'sort_by(-.urgency)'` |
| Same-lock siblings | Filter on `tags` / bpid prefix locally, not via `task` filter |
| Wave brief | `--wave` flag emits table with exclusion column |
| Skip failing-filter variants | Never `task next`, always `export \| jq` |

## Quick Reference

| Flag | Default | Purpose |
|------|---------|---------|
| `--n=3` | 3 | How many candidates |
| `--lock=ghidra` | unset | Drop ghidra-contending tasks |
| `--wave` | off | Emit wave brief format |
| `--project=<name>` | repo basename | Override the project filter |
| `--all` | off | Disable project filter (cross-project wave) |
| `--include-active` | off | Include `+ACTIVE` (claimed) tasks in candidate ranking |
| `--stale-after=N` | 4 | Hours before a `+ACTIVE` claim is flagged stale in the report |

## Related

- `/taskwarrior:task-claim` — the skill agents call after picking a candidate (sets `+ACTIVE`, which this skill respects)
- `/taskwarrior:task-release` — release a stale claim surfaced by this skill
- `/taskwarrior:task-status` — full queue audit
- `agent-patterns-plugin:parallel-agent-dispatch` — the dispatch contract these candidates feed
- `agent-patterns-plugin:exclusive-lock-dispatch` — when to pre-dump instead of serialise
- `workflow-orchestration-plugin:workflow-wave-dispatch` — wave scheduling that consumes the brief
- `.claude/rules/parallel-safe-queries.md` — `export | jq` idiom
