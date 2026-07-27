# Feature Tracker Sync — Reference

Reference material for `blueprint-feature-tracker-sync`: direct-edit `jq` recipes for tracker mutations, the portfolio-link rollup rules, the tracker-integrity issue-type responses, and sample report output. The execution flow itself lives in [SKILL.md](SKILL.md).

## Direct Tracker Edits (jq Recipes)

These recipes manipulate `docs/blueprint/feature-tracker.json` directly. Prefer the skill's mode-driven flows (`--summary`, `--drain-wave`, default full sync) for routine work — these recipes are for ad-hoc surgery.

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

## Evidence Backfill jq Recipe

After Step 3b scans the working tree and git history, merge results into the tracker. For each feature `$FR_ID` with scanned `$NEW_COMMITS` (newline-separated SHAs in `/tmp/scan-commits.txt`), `$NEW_TESTS` (newline-separated paths in `/tmp/scan-tests.txt`), and an `$INFERRED_STATUS` of `complete` / `partial` / `null`:

```bash
jq --arg id "$FR_ID" \
   --rawfile commits /tmp/scan-commits.txt \
   --rawfile tests /tmp/scan-tests.txt \
   --arg status "$INFERRED_STATUS" \
   --arg today "$(date -u +%Y-%m-%d)" '
  (.features // []) |= map(
    if .id == $id then
      . as $fr
      | .implementation.commits = (
          ((.implementation.commits // []) +
           ($commits | split("\n") | map(select(length > 0))))
          | unique
        )
      | .implementation.tests = (
          ((.implementation.tests // []) +
           ($tests | split("\n") | map(select(length > 0))))
          | unique
        )
      | if ($fr.status // "not_started") == "not_started" and $status != "null"
        then .status = $status
             | (if $status == "complete" then .completed_at = $today else . end)
        else .
        end
    else .
    end
  )
' docs/blueprint/feature-tracker.json > docs/blueprint/feature-tracker.json.tmp
mv docs/blueprint/feature-tracker.json.tmp docs/blueprint/feature-tracker.json
```

Run sequentially per feature so concurrent writes don't collide. The recipe preserves any existing commit/test entries (deduped via `unique`) and only flips `status` upward from `not_started` — already-`complete`/`in_progress`/`partial` features are left alone.

## Task Registry Update jq Recipe

Full Sync Step 10 updates the task registry entry in `docs/blueprint/manifest.json`:

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

## FR Status Flip jq Recipe (`--drain-wave` Step 4)

For each feature whose `implementing_wos` array overlaps the drained wave, recompute its `status`:

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

## Portfolio Link Resolution (v3.3.0+, root blueprints only)

Full Sync Step 6a. Runs only when the manifest at the root has `workspaces.role == "root"` AND the feature-tracker contains any feature with a non-empty `implemented_by` array.

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

## Tracker Integrity Issue Types

Responses to the `ISSUES:` rows emitted by `blueprint-tracker-check.sh` (Full Sync Step 7a):

| `TYPE=` | Response |
|---------|----------|
| `statistics_divergence` | Write the `EXPECTED=` value; the checker uses the same `round(complete/total*1000)/10` formula as Step 6 |
| `feature_status_near_miss` | Rewrite the status to the `CANONICAL=` spelling |
| `feature_status_unknown` | Ask the user which schema status was meant (`not_started`, `in_progress`, `partial`, `complete`, `blocked`) |
| `task_feature_disagreement` | An undrained `tasks.pending` entry (route to `--drain-wave`) or a task closed ahead of its feature |
| `fr_cited_not_minted` | Mint the FR, or correct the citing document — an unminted FR is invisible to every status query |
| `doc_status_stale` | Offer to advance the doc's frontmatter `status:` (it is still unfinished while every FR it cites has landed) |
| `dead_statistics_bucket` / `duplicate_timestamp_field` | Drop the non-schema bucket; keep `last_updated`, drop the alias |

Repo conventions (document status vocabulary, doc globs, excluded basenames)
come from the manifest `validation` block via
`scripts/get-validation-config.sh` — absent, it uses working defaults.

The check never reports an FR id appearing in **both** the features collection
and a task list as a duplicate: that repetition is the documented drain design.
Status is read from the features collection only.

## Sync Report Template

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

Inferred from evidence (Step 3b):
{For each feature flipped from not_started:}
- {feature_id} ({feature_title}): not_started -> {inferred_status}
  Files: {implementation.files | join(", ")}
  Commits backfilled: {N} SHAs

{If discrepancies skipped:}
Unresolved Discrepancies:
- {feature}: tracker says {status}, TODO.md shows {checkbox_state}
```

## Example Summary Output

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

## Work Overview Summary Output (`--summary`)

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

## Sidecar Drain Report Example

Printed by `--drain-wave` Step 6:

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
