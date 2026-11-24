---
created: 2026-07-15
modified: 2026-11-24
reviewed: 2026-07-15
---

# Task ID Stability (taskwarrior)

Unscoped on purpose: the hazard fires on a `task` **command**, which no `paths:`
glob can see (`.claude/rules/context-engineering.md`).

Taskwarrior numeric task IDs are a **display index over pending tasks**, not a
stable identifier. The moment any task completes or is deleted, every higher
numeric ID shifts down by one — a loop iteration, a later turn, another agent's
concurrent `task done`. Resolve the immutable **UUID** at the moment you decide
to act, and mutate exclusively by UUID from then on, including *within* a single
skill's own multi-step execution. A wrong-ID mutation raises no error ("closed
the wrong task — 282 now points to a gitops task").

| Prefer | Over | Why |
|---|---|---|
| `task "$TASK_UUID" done` (captured once, reused) | `task "$TASKID" done` at every step | The numeric ID can renumber underneath a skill's own later steps |
| `task +LATEST uuids` | `task +LATEST _get uuid` | `_get` is a DOM accessor (`<id>.<attribute>`); given a tag filter it silently returns empty (#1417) |
| `task <filter> export \| jq -r '.[].uuid'` | `task <filter> list` | `export` emits `[]` and exits 0 on empty (parallel-safe); `list` exits 1 |
| Capture UUIDs **before** the first mutation in a loop | Re-reading IDs mid-loop | Any close during the loop renumbers everything after it |
| `task depends:"$TASK_UUID" export` (after a close) | `task depends:"$TASKID" export` | A completed task's numeric `id` becomes `0` and may be reassigned |

Single-task skills (`task-claim`, `task-release`, `task-done`) load the task
once, capture `$TASK_UUID`, and address every later mutating call by it;
`taskwarrior-plugin/scripts/tests/test-task-id-stability.sh` pins that. Bulk
loops: `taskwarrior-plugin:task-bulk-ops`. The incident history, the skill
pattern in full, and why a visible UUID column is not the defense:
[`docs/rules/task-id-stability.md`](../../docs/rules/task-id-stability.md).

## Related

- `taskwarrior-plugin:task-add` — the `+LATEST uuids` capture pattern (issue #1417)
- `taskwarrior-plugin:task-bulk-ops` — full loop/batch treatment (Rule 1: address by UUID)
- `.claude/rules/parallel-safe-queries.md` — the `export | jq` (exit-0-on-empty) idiom
