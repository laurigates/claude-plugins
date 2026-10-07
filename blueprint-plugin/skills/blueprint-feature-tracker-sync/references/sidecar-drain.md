# feature-tracker-sync — Taskwarrior Sidecar Drain (`--drain-wave`)

The full procedure for the drain mode.

### Step 1: Parse the wave list

Split `--drain-wave` on commas. For each WO ID, line up the matching evidence
source in this priority order:

1. The matching positional entry in `--evidence-files` (file path), read with
   `jq --rawfile` to dodge single-quote collisions.
2. `--evidence` (single-WO drains only).
3. The latest `annotate` line on the linked taskwarrior task (Step 2).
4. As a last resort, prompt the user for evidence with `AskUserQuestion`.

Refuse the run with a clear message if the WO list and `--evidence-files`
list are both provided but their lengths disagree — partial drains are
worse than no drain.

### Step 2: Source evidence from taskwarrior

For each WO in the wave, fetch the latest annotation. Use the parallel-safe
`export | jq` idiom — never `task list` — so a missing-task case returns
exit 0 instead of cancelling sibling tool calls (see
`.claude/rules/parallel-safe-queries.md`):

```bash
task bpid:"$WO" status:completed export \
  | jq -r '.[0].annotations | sort_by(.entry) | last | .description // empty'
```

If the result is empty, fall back to `status:any` (the user may have closed
the task before drain). If still empty, fall back to the next priority source
from Step 1.

Persist each evidence string to a temp file (`mktemp`) — embedded single
quotes in commit messages collide with shell when inlined into a `jq`
program literal, and `--rawfile` is the standard escape:

```bash
ev_file="$(mktemp)"
printf '%s' "$EVIDENCE_STRING" > "$ev_file"
```

### Step 3: Drain pending → completed

For each `WO-NNN` in the wave, with its evidence file `$ev_file`, advance
the tracker in a single `jq` pass per WO. Store the date once and pass it
in as an argument so the same value lands on every entry:

```bash
today="$(date -u +%Y-%m-%d)"
jq --arg id "$WO" \
   --arg today "$today" \
   --rawfile ev "$ev_file" '
  .tasks.completed = (
    [ .tasks.pending[]
      | select(.id == $id)
      | . + {"completed": $today, "evidence": $ev}
    ] + .tasks.completed
  )
  | .tasks.pending = [.tasks.pending[] | select(.id != $id)]
' docs/blueprint/feature-tracker.json > docs/blueprint/feature-tracker.json.tmp
mv docs/blueprint/feature-tracker.json.tmp docs/blueprint/feature-tracker.json
```

Loop the WOs sequentially — each pass reads the file the previous pass
wrote — so concurrent writes cannot collide on the same file.

If a WO ID is not in `tasks.pending`, report `skipped: not pending` for
that entry and continue. Do not error the whole wave.

### Step 4: Flip FR status when implementing WOs are all closed

For each feature whose `implementing_wos` array overlaps the drained wave,
recompute its `status`. The flip is the second hand-jq pattern users
repeat per wave; do it once here. For the `jq` recipe, see
[REFERENCE.md](../REFERENCE.md#fr-status-flip-jq-recipe---drain-wave-step-4).

If the tracker schema stores features in a flat `features` array but with a
different shape (e.g., nested under `phases[].features[]`), adapt the path
prefix while preserving the same logic: a feature flips to `complete` only
when **every** WO ID listed in `implementing_wos` appears in
`tasks.completed`.

Record each flip in the run report (Step 6). Never silently downgrade an
already-`complete` FR.

### Step 5: Recalculate statistics

Re-run Step 6 of **Mode: Full Sync (Default)** so the totals reflect the
drained WOs and any flipped FRs. Then write the updated `last_updated` and
`current_phase` per Step 7 of Full Sync, and verify the result with **Step 7a**
of Full Sync — a drain moves ids between `tasks.pending` and `tasks.completed`,
which is exactly when `statistics` and task/feature agreement drift.

### Step 6: Report

Print a Drain Report covering the wave list, each WO's drained/skipped outcome
with its evidence source, the FR flips, the updated statistics, and the
`/taskwarrior:task-done` follow-up. For the report template, see
[REFERENCE.md](../REFERENCE.md#sidecar-drain-report-example).

Clean up temp evidence files with `rm -f "$ev_file"`.

### Single-WO short form

For the common one-WO case, the same flow with `--drain-wave WO-031` and
either `--evidence "<text>"` or no evidence flag (annotation autosourced) is
shorter than the legacy hand-rolled `jq` one-liner — and emits the same
on-disk shape. Prefer `/taskwarrior:task-done` when you also need to close
the linked taskwarrior task; this skill only edits the tracker.

## Related

- `taskwarrior-plugin:task-done` — close a single taskwarrior task and drain
  the linked tracker entry; pairs with this skill's `--drain-wave` for
  wave-granular drains where multiple WOs land at once.
- `taskwarrior-plugin:task-coordinate` — surface the next N unblocked tasks
  before starting a wave, so the WOs you eventually drain here line up with
  what the queue actually scheduled.
- `session-plugin:session-end` — the session wind-down orchestrator offers a
  `--drain-wave` pass when its survey finds closed WO-linked (`bpid`)
  taskwarrior tasks still sitting in the tracker's `tasks.pending`, so the
  drain happens at the session bookend instead of drifting until someone
  remembers to run this sync by hand.
- `.claude/rules/parallel-safe-queries.md` — the `task ... export | jq`
  idiom is mandatory whenever this skill queries taskwarrior. `task list`
  exits 1 on empty results and silently cancels sibling parallel tool calls.
