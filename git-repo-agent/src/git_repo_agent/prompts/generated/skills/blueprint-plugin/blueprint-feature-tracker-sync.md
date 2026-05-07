Synchronize the feature tracker JSON with TODO.md and manage task progress.
## Mode Selection (run first)

Decide which mode applies before any work:

1. If `--summary` is present, run **Mode: Generate Summary** and exit.
2. If `--drain-wave` is present, run **Mode: Taskwarrior Sidecar Drain** and exit.
3. Otherwise, run sidecar detection (Step 0 below). If a sidecar is detected and
   `TODO.md` is absent, prefer **Sidecar Drain** semantics for any user-facing
   completion prompts; otherwise run **Mode: Full Sync (Default)**.

---


## Mode: Generate Summary (`--summary`)

When `--summary` is provided, generate a human-readable progress report without modifying any files:

```bash
jq -r '
  "# Work Overview: \(.project)\n\n" +
  "## Current Phase: \(.current_phase // "Not set")\n\n" +
  "**Progress**: \(.statistics.complete)/\(.statistics.total_features) features (\(.statistics.completion_percentage)%)\n\n" +
  "### In Progress\n" +
  (if (.tasks.in_progress | length) == 0 then "- (none)\n" else (.tasks.in_progress | map("- \(.description) [\(.id)]") | join("\n")) + "\n" end) +
  "\n### Pending\n" +
  (if (.tasks.pending | length) == 0 then "- (none)\n" else (.tasks.pending | map("- \(.description) [\(.id)]") | join("\n")) + "\n" end) +
  "\n### Recently Completed\n" +
  (if (.tasks.completed | length) == 0 then "- (none)\n" else (.tasks.completed | map("- \(.description) [\(.id)]") | join("\n")) + "\n" end) +
  "\n## Phase Status\n" +
  (.phases | map("- \(.name): \(.status)") | join("\n"))
' docs/blueprint/feature-tracker.json
```

Output example:
```markdown

# Work Overview: my-project


## Current Phase: phase-1

**Progress**: 22/42 features (52.4%)


### In Progress
- Implement OAuth integration [FR2.3]
- Add rate limiting [FR3.1]


### Pending
- Webhook support [FR4.1]
- Admin dashboard [FR5.1]


### Recently Completed
- User authentication [FR2.1]
- Session management [FR2.2]


## Phase Status
- Foundation: complete
- Core Features: in_progress
- Advanced Features: not_started
```

**Exit** after displaying summary.


## Mode: Full Sync (Default)


### Step 0: Detect taskwarrior sidecar

Determine whether this project uses the taskwarrior-sidecar convention
(taskwarrior is the authoritative pending/completed queue, linked to blueprint
via the `bpid`/`bpdoc` UDAs). Either signal is sufficient:

1. **Marker rule file**: `test -f .claude/rules/task-tracking.md`.
2. **Live taskwarrior linkage**: any task carries a `bpid` matching one of the
   project's blueprint IDs.

   Use the parallel-safe `export | jq` idiom (see
   `.claude/rules/parallel-safe-queries.md`) — never `task list`, which exits
   1 on empty results and silently cancels sibling tool calls in a parallel
   Bash batch:

   ```bash
   task bpid.any: status:any export | jq 'length'
   ```

   Treat any non-zero count as "sidecar present".

If a sidecar is detected, set `SIDECAR=true` and:

- Skip the `TODO.md` reconciliation steps (Steps 4–5, 8) — there is no
  authoritative TODO file to align against.
- Continue with statistics recalculation (Step 6) and tracker write (Step 7),
  using taskwarrior `status:completed` as the truth signal for WO entries.
- When the user is closing one or more WOs, route them to **Mode: Taskwarrior
  Sidecar Drain** instead of editing `TODO.md`.


### Step 1: Check if feature tracking is enabled

```bash
test -f docs/blueprint/feature-tracker.json
```

**If not found**, report:
```
Feature tracking not enabled in this project.
Run `/blueprint:init` and enable feature tracking to get started.
```


### Step 2: Load current state

- Read `docs/blueprint/feature-tracker.json` for current feature and task status
- Read `TODO.md` for checkbox states (if exists)
- Read manifest for configuration


### Step 3: Analyze each feature

For each feature in the tracker:

a. **Verify status consistency**:
   - `complete`: Check TODO.md has `[x]` (if tracked there)
   - `partial`: Some checkboxes checked, some not
   - `in_progress`: Should have entry in `tasks.in_progress`
   - `not_started`: Check TODO.md has `[ ]`, not in completed
   - `blocked`: Note if blocking reason is documented

b. **Check implementation evidence** (optional, for thorough sync):
   - Look for files listed in `implementation.files`
   - Check if tests exist in `implementation.tests`
   - Verify commits in `implementation.commits`


### Step 4: Detect discrepancies

Look for inconsistencies:
- Feature marked `complete` in tracker but unchecked in TODO.md
- Feature checked in TODO.md but not `complete` in tracker
- Feature in `tasks.in_progress` but tracker says `complete`
- PRD status doesn't match feature implementation status


### Step 5: Ask user about discrepancies

If discrepancies found (use report to orchestrator):
```
question: "Found {N} discrepancies. How should they be resolved?"
options:
  - label: "Update tracker from TODO.md"
    description: "Trust TODO.md, update tracker to match"
  - label: "Update TODO.md from tracker"
    description: "Trust the tracker, update TODO.md to match"
  - label: "Review each discrepancy"
    description: "Show each discrepancy and decide individually"
  - label: "Skip - don't resolve discrepancies"
    description: "Report discrepancies but don't change anything"
```


### Step 6: Recalculate statistics

- Count features by status across all nested levels
- Calculate completion percentage: `(complete / total) * 100`
- Update phase status based on contained features:
  - `complete` if all features complete
  - `in_progress` if any feature in_progress
  - `partial` if some complete, some not
  - `not_started` if no features started


### Step 6a: Resolve portfolio links (v3.3.0+, root blueprints only)

Run only when the manifest at the root has `workspaces.role == "root"` AND the
feature-tracker contains any feature with a non-empty `implemented_by` array.

1. For each feature with `implemented_by`:
   - For every `{workspace, ref}` entry, read
     `<workspace>/docs/blueprint/feature-tracker.json` and look up `ref`.
   - Collect the child statuses. If any entry cannot be resolved (missing file
     or missing ref), record a warning and treat that entry as `not_started`
     for the rollup.
   - Derive the root feature's `status` using this rule:

     | Child statuses observed | Derived status |
     |-------------------------|----------------|
     | All resolved entries `complete` | `complete` |
     | Any `blocked` | `blocked` |
     | Any `in_progress`, or a mix of `complete`/`not_started` | `partial` |
     | All `not_started` | `not_started` |

   - Overwrite the feature's `status` with the derived value. Do NOT touch
     `implementation` on portfolio features; status alone is recomputed.

2. Rebuild the top-level `workspaces` summary by reading each child's
   `statistics` block:

   ```json
   "workspaces": {
     "projects/esp32-lamp": {
       "total": 14, "complete": 6, "completion_percentage": 42.9,
       "current_phase": "phase-1", "last_synced_at": "<now>"
     }
   }
   ```

3. Recompute root `statistics` after the derived statuses are applied so the
   portfolio-level totals reflect the child-driven states.

4. Emit warnings in the sync report (Step 9) for unresolved `implemented_by`
   entries, and suggest `/blueprint:workspace-scan` when a referenced
   workspace is not present in the root manifest's `workspaces.children`.


### Step 7: Update feature-tracker.json

- Apply resolved discrepancies
- Update `statistics` section
- Update `last_updated` to today's date
- Update PRD status if features changed
- Update `current_phase` to first incomplete phase


### Step 8: Update TODO.md (if exists)

- Ensure checkbox states match feature status
- `[x]` for `complete` features
- `[ ]` for `not_started` features
- Note partial completion in task text if needed


### Step 9: Output sync report

```
Feature Tracker Sync Report
===========================
Last Updated: {date}

Statistics:
- Total Features: {total}
- Complete: {complete} ({percentage}%)
- Partial: {partial}
- In Progress: {in_progress}
- Not Started: {not_started}
- Blocked: {blocked}

Current Phase: {current_phase}

Phase Status:
- Phase 0: {status}
- Phase 1: {status}
...

Active Tasks:
{tasks.in_progress | list}

Changes Made:
{If changes made:}
- {feature}: {old_status} -> {new_status}
- Updated TODO.md: checked {N} items
{If no changes:}
- No changes needed, all in sync

{If discrepancies skipped:}
Unresolved Discrepancies:
- {feature}: tracker says {status}, TODO.md shows {checkbox_state}
```


### Step 10: Update task registry

Update the task registry entry in `docs/blueprint/manifest.json`:

```bash
jq --arg now "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  --arg todo_hash "$(sha256sum TODO.md 2>/dev/null | cut -d' ' -f1)" \
  --argjson processed "${FEATURES_SYNCED:-0}" \
  '.task_registry["feature-tracker-sync"].last_completed_at = $now |
   .task_registry["feature-tracker-sync"].last_result = "success" |
   .task_registry["feature-tracker-sync"].context.last_todo_hash = $todo_hash |
   .task_registry["feature-tracker-sync"].stats.runs_total = ((.task_registry["feature-tracker-sync"].stats.runs_total // 0) + 1) |
   .task_registry["feature-tracker-sync"].stats.items_processed = $processed' \
  docs/blueprint/manifest.json > tmp.json && mv tmp.json docs/blueprint/manifest.json
```


### Step 11: Prompt for next action

Use report to orchestrator:
```
question: "Sync complete. What would you like to do next?"
options:
  - label: "View detailed status"
    description: "Run /blueprint:feature-tracker-status for full breakdown"
  - label: "Continue development"
    description: "Run /project:continue to work on next task"
  - label: "I'm done"
    description: "Exit sync"
```

---


## Mode: Taskwarrior Sidecar Drain (`--drain-wave`)

Drain one or more completed WOs from `tasks.pending` into `tasks.completed`,
sourcing evidence from taskwarrior annotations (or from named files / an
inline string), then flip any FR-level entries whose implementing WOs are
now all closed.


### Step 1: Parse the wave list

Split `--drain-wave` on commas. For each WO ID, line up the matching evidence
source in this priority order:

1. The matching positional entry in `--evidence-files` (file path), read with
   `jq --rawfile` to dodge single-quote collisions.
2. `--evidence` (single-WO drains only).
3. The latest `annotate` line on the linked taskwarrior task (Step 2).
4. As a last resort, prompt the user for evidence with `report to orchestrator`.

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
repeat per wave; do it once here:

```bash
jq --arg today "$today" '
  (.features // [])
  |= map(
    if (.implementing_wos // []) | length > 0 then
      . as $fr
      | (.implementing_wos
         | map(. as $woid
               | (($fr | .. | objects | select(has("id")) | select(.id == $woid))
                  // null)
               | . != null)) as $resolved
      | (((.implementing_wos | length) > 0)
         and ([.implementing_wos[] as $wo
                | any(($fr.parent_tracker.tasks.completed // [])[]; .id == $wo)]
              | all)) as $all_done
      | if $all_done and (.status // "") != "complete"
        then . + {"status": "complete", "completed_at": $today}
        else .
        end
    else .
    end
  )
' docs/blueprint/feature-tracker.json > docs/blueprint/feature-tracker.json.tmp
mv docs/blueprint/feature-tracker.json.tmp docs/blueprint/feature-tracker.json
```

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
`current_phase` per Step 7 of Full Sync.


### Step 6: Report

Print a Drain Report:

```
Sidecar Drain Report
====================
Wave: WO-031, WO-032, WO-033
Drained:
- WO-031: pending -> completed  (evidence: 142 chars from tw annotation)
- WO-032: pending -> completed  (evidence: 209 chars from /tmp/wo032_ev.txt)
- WO-033: skipped (not in tasks.pending)

FR flips:
- FR-017 (Skill Progression): in_progress -> complete

Statistics:
- Total Features: 42
- Complete: 23 (54.8%)  [+1 from FR-017]
- Recently Completed: WO-031, WO-032 added to top of tasks.completed

Next: run /taskwarrior:task-done if any sibling tasks should also close.
```

Clean up temp evidence files with `rm -f "$ev_file"`.


### Single-WO short form

For the common one-WO case, the same flow with `--drain-wave WO-031` and
either `--evidence "<text>"` or no evidence flag (annotation autosourced) is
shorter than the legacy hand-rolled `jq` one-liner — and emits the same
on-disk shape. Prefer `/taskwarrior:task-done` when you also need to close
the linked taskwarrior task; this skill only edits the tracker.

---


## Task Management


### Adding a task to in_progress

When starting work on a feature:

```bash
jq '.tasks.in_progress += [{"id": "FR2.3", "description": "Implement OAuth integration", "source": "PRP-002", "added": "2026-02-04"}]' \
  docs/blueprint/feature-tracker.json > tmp.json && mv tmp.json docs/blueprint/feature-tracker.json
```


### Completing a task

When finishing work:

```bash

# Move from in_progress to completed (keep last 10)
jq '
  .tasks.completed = ([.tasks.in_progress[] | select(.id == "FR2.3") | . + {"completed": "2026-02-04"}] + .tasks.completed)[:10] |
  .tasks.in_progress = [.tasks.in_progress[] | select(.id != "FR2.3")]
' docs/blueprint/feature-tracker.json > tmp.json && mv tmp.json docs/blueprint/feature-tracker.json
```


### Adding pending tasks

When planning future work:

```bash
jq '.tasks.pending += [{"id": "FR4.1", "description": "Webhook support", "source": "PRD-001", "added": "2026-02-04"}]' \
  docs/blueprint/feature-tracker.json > tmp.json && mv tmp.json docs/blueprint/feature-tracker.json
```


## Example Output

```
Feature Tracker Sync Report
===========================
Last Updated: 2026-02-04

Statistics:
- Total Features: 42
- Complete: 22 (52.4%)
- Partial: 4
- In Progress: 2
- Not Started: 14
- Blocked: 0

Current Phase: phase-2

Phase Status:
- Phase 0: complete
- Phase 1: complete
- Phase 2: in_progress
- Phase 3-8: not_started

Active Tasks:
- Implement OAuth integration [FR2.3]
- Add rate limiting [FR3.1]

Changes Made:
- FR2.6.1 (Skill Progression): partial -> complete
- FR2.6.2 (Experience Points): not_started -> complete
- Updated TODO.md: checked 2 items

All sync targets updated successfully.
```


## Related

- `taskwarrior-plugin:task-done` — close a single taskwarrior task and drain
  the linked tracker entry; pairs with this skill's `--drain-wave` for
  wave-granular drains where multiple WOs land at once.
- `taskwarrior-plugin:task-coordinate` — surface the next N unblocked tasks
  before starting a wave, so the WOs you eventually drain here line up with
  what the queue actually scheduled.
- `.claude/rules/parallel-safe-queries.md` — the `task ... export | jq`
  idiom is mandatory whenever this skill queries taskwarrior. `task list`
  exits 1 on empty results and silently cancels sibling parallel tool calls.