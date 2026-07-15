---
name: task-coordinate
description: Surface next N unblocked taskwarrior tasks by urgency, skipping lock-contending tasks. Use when planning a parallel-agent wave or choosing tasks for a dispatch slot.
args: "[--n=N] [--lock=<resource>] [--wave] [--project=<name>] [--all]"
allowed-tools: Bash(task *), Bash(git rev-parse *), Bash(jq *), Read, TodoWrite
argument-hint: optional count (default 3) and lock filter
created: 2026-04-24
modified: 2026-05-22
reviewed: 2026-05-22
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
- Git repo detected: !`find . -maxdepth 1 -name '.git' -print -quit`
- Known projects: !`task _projects`

`git rev-parse --show-toplevel` writes to stderr in a no-git cwd, and
stderr from a Context backtick aborts the skill before its body runs.
Project resolution is done in the body (Step 1 below) via the Bash tool
where `2>/dev/null` and exit-code handling are tolerated.

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
3. Basename of `git rev-parse --show-toplevel 2>/dev/null`, run via the
   Bash tool (where stderr suppression and non-zero exits are tolerated).
4. If no git repo (Step 3 returned empty), basename of cwd.

## Execution

Execute this workflow:

### Step 1: Load unblocked pending tasks

Substitute the literal project name into the filter (no `$()` command
substitution — shell-operator protections will reject it). Use taskwarrior's
native `+READY` virtual tag, which means *pending, unblocked, not waiting, and
either unscheduled or scheduled before now* — so it subsumes the old
`-BLOCKED` clause AND respects `scheduled:` / `wait:` dates. Add `-ACTIVE` to
exclude tasks already claimed via `/taskwarrior:task-claim`:

```bash
task project:myrepo status:pending +READY -ACTIVE export \
  | jq 'sort_by(-.urgency) | .[] | {id, description, urgency, tags, bpid, depends, due, scheduled}'
```

With `--include-active`, drop the `-ACTIVE` clause so already-claimed
tasks compete for ranking. With `--all`, drop the `project:` clause.
`+READY` automatically hides `wait:`-deferred and future-`scheduled:` tasks,
so a task parked with `wait:` until a PR merges never appears as a candidate.
Never use `task next` — exits 1 on empty.

### Step 1b: Snapshot in-flight claims

In parallel with Step 1 (these are independent reads), collect the set
of currently-claimed tasks for the report:

```bash
task project:myrepo status:pending +ACTIVE export \
  | jq '.[] | {id, uuid, description, agent, pid, host, branch, worktree, start, urgency}'
```

Empty array is exit-0 from `task export` — safe in parallel batches.

### Step 1c: Detect stale claims

Filter the in-flight set for claims older than `--stale-after` hours:

```bash
task project:myrepo +ACTIVE start.before:now-4h export \
  | jq '.[] | {id, uuid, agent, host, branch, start}'
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

| Task | UUID | Agent | Branch | Host | Started |
|------|------|-------|--------|------|---------|
| #4 (WO-008) | a1b2c3d4 | claude-a1b2c3d4 | feature/parser | host-1 | 2h ago |
| #9 (WO-011) | 9f8e7d6c | claude-9f8e7d6c | feature/api    | host-2 | 30m ago |

## Stale claims (>4h)

| Task | UUID | Agent | Started | Action |
|------|------|-------|---------|--------|
| #2 (WO-005) | 44556677 | claude-44556677 | 6h ago | Investigate; release with `/taskwarrior:task-release 44556677...` (or `#2` — task-release resolves either form to the immutable UUID internally) if abandoned |
```

Empty sections render as "(none)". Never auto-stop a stale claim —
report only, per the v1 design. The `UUID` column (`.uuid[0:8]`) is a
copy-pasteable immutable form offered as convenience — `task-release` /
`task-claim` / `task-done` resolve and mutate by UUID internally regardless
of which form is pasted, so it is not the safety mechanism (see
`.claude/rules/task-id-stability.md`).

## Agentic Optimizations

| Context | Command |
|---------|---------|
| Project ready + unclaimed | `task project:myrepo status:pending +READY -ACTIVE export \| jq 'sort_by(-.urgency)'` |
| Include claimed (rare) | drop `-ACTIVE` clause |
| Overdue candidates | `task project:myrepo status:pending +OVERDUE export \| jq 'sort_by(-.urgency)'` |
| In-flight snapshot | `task project:myrepo +ACTIVE export \| jq '.[] \| {id, agent, branch, start}'` |
| Stale claims | `task project:myrepo +ACTIVE start.before:now-4h export \| jq` |
| Cross-project (`--all`) | `task status:pending +READY -ACTIVE export \| jq 'sort_by(-.urgency)'` |
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
- `.claude/rules/task-id-stability.md` — why the UUID column is convenience, not the safety mechanism
