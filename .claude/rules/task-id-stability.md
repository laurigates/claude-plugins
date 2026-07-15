---
created: 2026-07-15
modified: 2026-07-15
reviewed: 2026-07-15
---

# Task ID Stability (taskwarrior)

Taskwarrior numeric task IDs are a **display index over pending tasks**, not a
stable identifier. The moment any task completes or is deleted, every higher
numeric ID shifts down by one. A numeric ID captured at one moment is only
guaranteed correct until the *next* completion anywhere in the store — a loop
iteration, a later turn, another agent's concurrent `task done`, or a report
read now acted on minutes later. Resolve the immutable **UUID** at the moment
you decide to act, and mutate exclusively by UUID from then on.

## Why this keeps recurring

This bug class has bitten `taskwarrior-plugin` twice already, plus a live
incident that prompted this rule:

1. **Issue #1417** — `task-add` reported only the numeric ID after `task add`.
   A session created task 141, then 30 minutes later ran `task 141 annotate
   ...` and silently annotated a different, renumbered task.
2. **Follow-up to #1417** — the first fix shipped `task +LATEST _get uuid`.
   `_get` is a DOM accessor taking an `<id>.<attribute>` reference; given a
   *tag filter* (`+LATEST`) it silently returns empty (exit 0), so the "fix"
   captured no UUID and quietly reverted to the original bug. The corrected
   form is `task +LATEST uuids` (or `task +LATEST export | jq -r '.[0].uuid'`).
   A syntactic-only regression gate (a grep for the literal string) had let
   the broken form ship; the working fix needed an *executable* test
   (`task-add/scripts/tests/test-uuid-capture.sh`) that actually runs both
   forms against a scratch store.
3. **Mid-skill renumbering (this rule)** — `task-claim`, `task-release`, and
   `task-done` each resolve a task ID once early, then reuse that same
   possibly-numeric ID across several *later*, separately-issued mutating
   `task` commands. Each of these skills has a real, human-timescale gap
   between the resolve step and its mutating steps — an `AskUserQuestion`
   pause in `task-release`, a `SlashCommand` coworker-check in `task-claim`.
   If another agent's concurrent `task done` renumbers IDs in that window, a
   later step in the *same* skill invocation silently mutates the wrong task.
   No error surfaces — this is the shape of the live incident that prompted
   this rule ("closed the wrong task — 282 now points to a gitops task").

`task-bulk-ops` and `task-add` already document the loop/capture-time version
of this pattern in depth (see their own Foot-gun / Rule sections) — this rule
is the central citation point and the piece those skills didn't yet cover:
resolving once and reusing that resolution safely *within* a single skill's
own multi-step execution.

## Prefer X over Y

| Prefer | Over | Why |
|---|---|---|
| `task "$TASK_UUID" done` (captured once, reused) | `task "$TASKID" done` (re-using the caller-supplied numeric ID at every step) | The numeric ID can renumber underneath a skill's own later steps, not just across a bulk loop |
| `task +LATEST uuids` | `task +LATEST _get uuid` | `_get` is a DOM accessor (`<id>.<attribute>`); given a tag filter it silently returns empty — see #1417 |
| `task <filter> export \| jq -r '.[].uuid'` | `task <filter> list` | `export` emits `[]` and exits 0 on empty (parallel-safe); `list` exits 1 and cancels sibling calls |
| Capture UUIDs **before** the first mutation in a loop | Capturing/re-reading IDs mid-loop | Any task closing during the loop renumbers everything after it |
| `task depends:"$TASK_UUID" export` (after a close) | `task depends:"$TASKID" export` | Once completed, a task's numeric `id` becomes `0` and may be reassigned — the same query keyed on the old numeric ID checks the wrong thing |
| A short UUID column in a **report**, offered as convenience | Relying on a human/agent to notice and paste it instead of the numeric ID | See "Why not a visible UUID column" below — visibility is not the safety mechanism |

## Single-task skills: resolve once, mutate by UUID

`task-claim`, `task-release`, and `task-done` each load the task once (Step
1/2) and then issue several further `task` commands over the following steps.
Extend that initial load to also project `.uuid`, capture it as `$TASK_UUID`,
and address every later mutating call by `$TASK_UUID` instead of the
caller-supplied `$TASKID`:

```bash
# Step 1/2 — load once, capture both
task "$TASKID" export | jq '.[0] | {id, uuid, description, status, ...}'
# TASK_UUID="<the .uuid field>"

# Every later mutating call in this skill — by UUID, not $TASKID
task "$TASK_UUID" start
task "$TASK_UUID" modify agent:"$AGENT" ...
task "$TASK_UUID" annotate "..."
task "$TASK_UUID" done
```

The initial *load* call may still use the caller-supplied `$TASKID` (numeric
or UUID — taskwarrior accepts both for a lookup); only the resolve-then-mutate
chain needs to pin to the UUID. This is the same principle `task-bulk-ops`
Rule 1 and `release-stale-claims.sh` already apply to loops — this rule
extends it to a single task's own multi-step lifecycle.

## Bulk operations

Loop/batch operations over many tasks have their own dedicated treatment —
capturing UUIDs before the first mutation, the stdin/confirmation traps, and
the `export | jq` filter caveats — in `taskwarrior-plugin:task-bulk-ops`. This
rule does not duplicate that content; cite `task-bulk-ops` for the full bulk
treatment.

## Reporting skills: show the UUID as convenience, not as the defense

`task-status` and `task-coordinate` already fetch full task JSON via
`export | jq` — the UUID is already in that payload. Projecting it into the
rendered tables (a short form is enough) costs nothing and gives a human a
copy-pasteable immutable form. This is explicitly **not** the safety
mechanism — see below.

## Why not `.taskrc` / a visible UUID report column

Relying on a human or agent to *notice* a UUID column and *choose* to paste it
instead of the numeric ID reintroduces exactly the judgement-failure mode
`.claude/rules/offload-to-deterministic-substrate.md` exists to eliminate —
and it does nothing to protect a skill's own internal multi-step mutation
sequence, which is the actual gap this rule closes. `.taskrc` is also the
user's personal/global config, out of this repo's control to rewrite. The
primary defense is structural: skills resolve-and-mutate by UUID internally,
regardless of what any report displayed or what form the caller passed in.

## Related

- `taskwarrior-plugin:task-add` — the `+LATEST uuids` capture pattern originates here (issue #1417)
- `taskwarrior-plugin:task-bulk-ops` — full loop/batch treatment (Rule 1: address by UUID)
- `taskwarrior-plugin:task-claim` / `task-release` / `task-done` — single-task skills that resolve once and mutate by UUID
- `taskwarrior-plugin:task-status` / `task-coordinate` — report-only skills that surface the UUID as convenience
- `taskwarrior-plugin:task-reconcile` — bulk close paths, also UUID-keyed throughout
- `.claude/rules/offload-to-deterministic-substrate.md` — why the defense is structural, not visibility-based
- `.claude/rules/parallel-safe-queries.md` — the `export | jq` (exit-0-on-empty) idiom this rule assumes
- `.claude/rules/regression-testing.md` — the syntactic-vs-semantic gate lesson from the #1417 follow-up
- `.claude/rules/gh-json-fields.md` — sibling rule on getting the exact command form right
