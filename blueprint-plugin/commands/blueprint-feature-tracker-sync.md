---
model: opus
created: 2026-01-02
modified: 2026-01-09
reviewed: 2026-01-02
description: "Synchronize feature tracker with work-overview.md, TODO.md, and PRDs"
allowed_tools: [Read, Write, Bash, Glob, AskUserQuestion]
---

Synchronize the feature tracker JSON with work-overview.md and TODO.md to maintain consistency.

**Steps**:

1. **Check if feature tracking is enabled**:
   - Look for `docs/blueprint/feature-tracker.json`
   - If not found, report:
     ```
     Feature tracking not enabled in this project.
     Run `/blueprint-init` and enable feature tracking to get started.
     ```

2. **Load current state**:
   - Read `docs/blueprint/feature-tracker.json` for current feature status
   - Read `docs/blueprint/work-overview.md` for completed/pending sections
   - Read `TODO.md` for checkbox states
   - Read manifest for `sync_targets` configuration

3. **Analyze each feature**:
   For each feature in the tracker:

   a. **Verify status consistency**:
      - `complete`: Check TODO.md has `[x]`, work-overview lists in "Completed"
      - `partial`: Some checkboxes checked, some not
      - `in_progress`: Listed in "In Progress" section
      - `not_started`: Check TODO.md has `[ ]`, not in "Completed"
      - `blocked`: Note if blocking reason is documented

   b. **Check implementation evidence** (optional, for thorough sync):
      - Look for files listed in `implementation.files`
      - Check if tests exist in `implementation.tests`
      - Verify commits in `implementation.commits`

4. **Detect discrepancies**:
   Look for inconsistencies:
   - Feature marked `complete` in tracker but unchecked in TODO.md
   - Feature checked in TODO.md but not `complete` in tracker
   - Feature in work-overview.md "Completed" but tracker says `not_started`
   - PRD status doesn't match feature implementation status

5. **Ask user about discrepancies** (use AskUserQuestion):
   If discrepancies found:
   ```
   question: "Found {N} discrepancies. How should they be resolved?"
   options:
     - label: "Update tracker from TODO.md/work-overview.md"
       description: "Trust the documentation, update tracker to match"
     - label: "Update TODO.md/work-overview.md from tracker"
       description: "Trust the tracker, update documentation to match"
     - label: "Review each discrepancy"
       description: "Show each discrepancy and decide individually"
     - label: "Skip - don't resolve discrepancies"
       description: "Report discrepancies but don't change anything"
   ```

6. **Recalculate statistics**:
   - Count features by status across all nested levels
   - Calculate completion percentage: `(complete / total) * 100`
   - Update phase status based on contained features:
     - `complete` if all features complete
     - `in_progress` if any feature in_progress
     - `partial` if some complete, some not
     - `not_started` if no features started

7. **Update feature-tracker.json**:
   - Apply resolved discrepancies
   - Update `statistics` section
   - Update `last_updated` to today's date
   - Update PRD status if features changed

8. **Update sync targets**:

   **work-overview.md:**
   - Add newly completed features to "Completed" section
   - Move features from "Pending" to "In Progress" or "Completed" as appropriate
   - Update PRD completion status if shown

   **TODO.md:**
   - Ensure checkbox states match feature status
   - `[x]` for `complete` features
   - `[ ]` for `not_started` features
   - Note partial completion in task text if needed

9. **Output sync report**:
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

   Phase Status:
   - Phase 0: {status}
   - Phase 1: {status}
   ...

   Changes Made:
   {If changes made:}
   - {feature}: {old_status} -> {new_status}
   - Updated work-overview.md: added {N} to Completed
   - Updated TODO.md: checked {N} items
   {If no changes:}
   - No changes needed, all in sync

   {If discrepancies skipped:}
   Unresolved Discrepancies:
   - {feature}: tracker says {status}, TODO.md shows {checkbox_state}
   ```

10. **Prompt for next action** (use AskUserQuestion):
    ```
    question: "Sync complete. What would you like to do next?"
    options:
      - label: "View detailed status"
        description: "Run /blueprint-feature-tracker-status for full breakdown"
      - label: "Continue development"
        description: "Run /project:continue to work on next task"
      - label: "I'm done"
        description: "Exit sync"
    ```

**Example Output**:
```
Feature Tracker Sync Report
===========================
Last Updated: 2026-01-02

Statistics:
- Total Features: 42
- Complete: 22 (52.4%)
- Partial: 4
- In Progress: 2
- Not Started: 14
- Blocked: 0

Phase Status:
- Phase 0: complete
- Phase 1: complete
- Phase 2: in_progress
- Phase 3-8: not_started

Changes Made:
- FR2.6.1 (Skill Progression): partial -> complete
- FR2.6.2 (Experience Points): not_started -> complete
- Updated work-overview.md: added 2 features to Completed
- Updated TODO.md: checked 2 items

All sync targets updated successfully.
```
