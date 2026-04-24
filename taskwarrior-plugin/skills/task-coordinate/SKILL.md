---
name: task-coordinate
description: |
  Surface the next N unblocked taskwarrior tasks sorted by urgency,
  filtered to skip any that contend on the same exclusive lock (Ghidra
  project, git index, migration, bulk task store). Produces a
  candidate-agent list for a parallel or wave dispatch. Use when
  planning a parallel-agent-dispatch wave, when deciding which tasks
  share a dispatch slot, or when deciding whether to pre-dump a locked
  resource before fanning out.
args: "[--n=N] [--lock=<resource>] [--wave]"
allowed-tools: Bash(task *), Bash(jq *), Read, TodoWrite
argument-hint: optional count (default 3) and lock filter
created: 2026-04-24
modified: 2026-04-24
reviewed: 2026-04-24
---

# /taskwarrior:task-coordinate

Next-candidate-agent surfacing for parallel / wave dispatch. Pairs with `agent-patterns-plugin:parallel-agent-dispatch` and `workflow-orchestration-plugin:workflow-wave-dispatch`.

## Context

- Task CLI available: !`command -v task`
- Pending with urgency: !`task status:pending -BLOCKED export`
- Pending blocked: !`task +BLOCKED export`

## Parameters

Parse `$ARGUMENTS`:

- `--n=N` — number of candidates to surface (default 3)
- `--lock=<resource>` — exclude candidates that need the named lock (e.g. `ghidra`, `migration`, `task-bulk`)
- `--wave` — format output as a wave brief (orchestrator-ready)

## Execution

Execute this workflow:

### Step 1: Load unblocked pending tasks

```bash
task status:pending -BLOCKED export \
  | jq 'sort_by(-.urgency) | .[] | {id, description, urgency, tags, bpid, depends}'
```

Already filters out `depends:`-blocked tasks via the `-BLOCKED` virtual
attribute. Never use `task next` — exits 1 on empty.

### Step 2: Detect lock contenders

Classify each task by the locks implied by its tags or `bpid`:

| Tag / ID prefix | Implied lock |
|-----------------|--------------|
| `+re` on decomp work, `tmp/decomp/` in description | `ghidra` |
| `+migration`, bpid starts with `MIG-` | `migration` |
| `+bulk-task` | `task-bulk` (taskwarrior itself — single-writer) |
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

## Agentic Optimizations

| Context | Command |
|---------|---------|
| Unblocked sorted by urgency | `task status:pending -BLOCKED export \| jq 'sort_by(-.urgency)'` |
| Same-lock siblings | Filter on `tags` / bpid prefix locally, not via `task` filter |
| Wave brief | `--wave` flag emits table with exclusion column |
| Skip failing-filter variants | Never `task next`, always `export \| jq` |

## Quick Reference

| Flag | Default | Purpose |
|------|---------|---------|
| `--n=3` | 3 | How many candidates |
| `--lock=ghidra` | unset | Drop ghidra-contending tasks |
| `--wave` | off | Emit wave brief format |

## Related

- `agent-patterns-plugin:parallel-agent-dispatch` — the dispatch contract these candidates feed
- `agent-patterns-plugin:exclusive-lock-dispatch` — when to pre-dump instead of serialise
- `workflow-orchestration-plugin:workflow-wave-dispatch` — wave scheduling that consumes the brief
- `.claude/rules/parallel-safe-queries.md` — `export | jq` idiom
- `/taskwarrior:task-status` — full queue audit
