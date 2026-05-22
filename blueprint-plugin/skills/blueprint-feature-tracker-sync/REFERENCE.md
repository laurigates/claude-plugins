# Feature Tracker Sync — Reference

Reference material for `blueprint-feature-tracker-sync`: direct-edit `jq` recipes for tracker mutations, plus a sample summary report.

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
