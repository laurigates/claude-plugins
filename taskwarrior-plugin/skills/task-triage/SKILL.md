---
name: task-triage
description: Judge every pending taskwarrior task against current repo/PR/CI state via read-only cluster agents, then apply done/obsolete/update by UUID. Use when triaging or cleaning up a large, outdated queue.
args: "[--dry-run]"
allowed-tools: Bash(task *), Bash(jq *), Bash(python3 *), Bash(gh *), Read, Write, Agent, AskUserQuestion, TodoWrite
argument-hint: optional --dry-run to stop after validation and the apply preview
created: 2026-11-03
modified: 2026-11-03
reviewed: 2026-11-03
---

# /taskwarrior:task-triage

Triage a whole queue: decide, for every pending task, whether it is **done**,
**obsolete**, needs an **update**, or should be **kept** — each verdict backed
by evidence read from the system today, not from the task text. Read-only
agents do the judging per cluster of projects; the main session validates the
verdicts and applies them in one UUID-addressed pass.

## When to Use This Skill

| Use this skill when... | Use a sibling skill instead when... |
|---|---|
| The queue is large (dozens–hundreds of tasks) and much of it is probably outdated | Only tasks mirroring a GitHub issue/PR need retiring — `task-reconcile` |
| Tasks are follow-ups, watches and verifications whose state lives in repos, CI, upstream releases | Auditing the queue without changing it — `task-status` |
| You want closes backed by evidence, not by age or a cited PR's state | Applying an already-decided batch change — `task-bulk-ops` |

**Why not `task-reconcile` for this:** a merged PR or closed issue cited in a
task is usually the *context* the follow-up came from ("found during PR #44"),
not proof the follow-up is done. Reconcile closes on the ref's state; triage
closes on evidence that the described action happened. Also see
laurigates/claude-plugins#3387 — under `--all`, reconcile resolves bare `#N`
against the cwd repo.

## Parameters

| Flag | Default | Effect |
|---|---|---|
| `--dry-run` | off | Run Steps 1–4 and the `apply --dry-run` preview, then stop: no task is closed, deleted or annotated |

To triage a subset (one project, one org), map only those slugs and pass `--partial` to `split`; unmapped projects are skipped and listed as `SKIPPED_PROJECTS=`.

## Execution

### Step 1: Inventory and front-load decisions

```bash
task status:pending export | jq -r '.[] | (.project // "(none)")' | sort | uniq -c | sort -rn
```

Ask once, with `AskUserQuestion`, before dispatching anything:

- **Depth** — agent fan-out (thorough, a token burst) vs. mechanical checks only.
- **Authority** — the recommended default: `done` closes directly with an
  evidence annotation; `obsolete` waits for one approval of the full list
  (judgment calls like "time-boxed, window passed" belong in front of the user).

State the agent count when proposing the fan-out (one agent per cluster).

### Step 2: Split into clusters

Write a map of cluster → project slugs, balancing ~50–80 tasks per cluster and
keeping related repos together (one org's infra in one cluster, one product's
sub-projects in another). Every slug must appear exactly once — `split` refuses
unmapped or doubly-mapped projects.

```bash
python3 "${CLAUDE_SKILL_DIR}/scripts/triage.py" split --dir <scratch> --map <scratch>/map.json
```

This writes `<scratch>/pending.json` (snapshot) and `<scratch>/clusters/<C>.json`.

### Step 3: Dispatch read-only agents

Copy [references/agent-brief.md](references/agent-brief.md) to
`<scratch>/clusters/BRIEF.md`, fill in the location hints for this machine
(where repos live, slug→repo mappings that are not obvious), and dispatch one
agent per cluster **in a single message**, in the background, on a strong model
(the verdicts gate closes). Each prompt names: the brief path, its cluster file,
its output path `<scratch>/verdicts/<C>.jsonl`, and any leads you already have
(tasks whose cited ref looked stale, tasks with completed dependencies).

The agents never write to taskwarrior. Concurrent `task` writers renumber IDs
under each other; centralising writes in the main session removes that class.

### Step 4: Validate and spot-check

```bash
python3 "${CLAUDE_SKILL_DIR}/scripts/triage.py" validate --dir <scratch>
```

It fails on a missing verdict file, a task with no verdict, a uuid outside its
cluster, a duplicate, or an unknown verdict. Then re-run a sample of `done`
claims yourself (`gh pr view`, file reads) — an agent's wrong verdict arrives
as well-formed as its right ones. Note any agent that strayed outside the
brief's read-only scope for the report.

### Step 5: Apply

```bash
python3 "${CLAUDE_SKILL_DIR}/scripts/triage.py" apply --dir <scratch> --verdicts done,update --dry-run
python3 "${CLAUDE_SKILL_DIR}/scripts/triage.py" apply --dir <scratch> --verdicts done,update
```

Present the `obsolete` list (description + reason, duplicates naming their
survivor) in one `AskUserQuestion`, then:

```bash
python3 "${CLAUDE_SKILL_DIR}/scripts/triage.py" apply --dir <scratch> --verdicts obsolete
```

`done` → annotate + `task done`; `obsolete` → annotate + `task delete`;
`update` → annotate, plus a description rewrite when the agent supplied one.
Tasks closed by someone else since the snapshot are skipped. Tag changes the
verdicts call for (e.g. dropping `+blocked` once deps closed) are applied by
hand afterwards.

### Step 6: Report

Counts per verdict, the pending count before/after, and the findings agents
surfaced that no task tracks (red default branches, security items, unbacked
local-only repos, pending user decisions). Offer to file those as tasks —
don't bury them in the agents' JSONL.

## Agentic Optimizations

| Context | Command |
|---|---|
| Project histogram | `task status:pending export \| jq -r '.[]\|(.project//"(none)")' \| sort \| uniq -c \| sort -rn` |
| Split | `python3 scripts/triage.py split --dir D --map D/map.json` |
| Validate | `python3 scripts/triage.py validate --dir D` |
| Apply preview | `python3 scripts/triage.py apply --dir D --verdicts done,update --dry-run` |
| Restrict apply to approved uuids | `python3 scripts/triage.py apply --dir D --verdicts obsolete --only approved.txt` |
| Undo one close | `task <uuid> modify status:pending` |

## Related

- `task-reconcile` — ref-state-driven close; fine for pure GitHub mirrors
- `task-bulk-ops` — the UUID / stdin / annotate-before-done discipline `apply` follows
- `task-status` — read-only queue report to confirm the result
- `agent-patterns-plugin:parallel-agent-dispatch` — dispatch contract for the fan-out
