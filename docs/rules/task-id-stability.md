# Task ID Stability: incidents and the skill pattern

The always-loaded rule [`.claude/rules/task-id-stability.md`](../../.claude/rules/task-id-stability.md)
keeps the invariant (resolve the UUID once, mutate by UUID) and the prefer/over
table. This page holds the incident history, the single-task skill pattern in
full, and why a visible UUID column is not the defense, moved here verbatim on
2026-11-24 so they no longer load on every turn.

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
