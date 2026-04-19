---
created: 2026-01-02
modified: 2026-04-19
reviewed: 2026-04-12
description: |
  Synchronize feature tracker with TODO.md and PRDs, manage tasks. Use when the user asks
  to "sync feature tracker", reconcile discrepancies between TODO.md checkboxes and tracker
  status, recalculate completion statistics, add/complete tasks in tasks.in_progress, or
  generate a markdown progress summary with --summary.
allowed-tools: Read, Write, Bash, Glob, AskUserQuestion
name: blueprint-feature-tracker-sync
---

Synchronize the feature tracker JSON with TODO.md and manage task progress.

**Note**: As of v1.1.0, feature-tracker.json is the single source of truth for progress tracking. The `tasks` section replaces work-overview.md.

**Usage**: `/blueprint:feature-tracker-sync [--summary]`

**Flags**:
| Flag | Description |
|------|-------------|
| `--summary` | Generate human-readable markdown summary (stdout only, no file) |

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

If discrepancies found (use AskUserQuestion):
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

Use AskUserQuestion:
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
