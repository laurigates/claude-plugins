---
created: 2026-01-02
modified: 2026-11-13
reviewed: 2026-07-26
description: Display feature tracker stats, phase progress, and completion summary. Use when checking feature status, viewing blocked features, or seeing ready-to-start work.
allowed-tools: Read, Bash, AskUserQuestion
model: sonnet
name: blueprint-feature-tracker-status
---

Display feature tracker statistics, phase progress, and completion summary.

## When to Use This Skill

| Use this skill when... | Use blueprint-feature-tracker-sync instead when... |
|---|---|
| You want a read-only view of completion stats and phase progress | You need to reconcile TODO.md with the tracker (writes) |
| You want to see PRD coverage and ready-to-start work | You want to drain WO entries via `--drain-wave` |
| You're checking blocked features without modifying state | You want to recalculate completion percentages |
| You want a quick "where are we?" snapshot | Use feature-tracking instead for low-level FR-code edits |

## Execution

Execute this status workflow:

### Step 1: Check if feature tracking is enabled

   - Look for `docs/blueprint/feature-tracker.json`
   - If not found, report:
     ```
     Feature tracking not enabled in this project.
     Run `/blueprint:init` and enable feature tracking to get started.
     ```

### Step 2: Load tracker data

   - Read `feature-tracker.json`
   - Extract project name, source document, last_updated
   - Get statistics section
   - Get phase information
   - Get PRD status

### Step 3: Calculate derived metrics (if not in statistics)

   - Count features by status at all nesting levels
   - Calculate completion percentage
   - Count features per phase
   - Count PRDs by status

### Step 3a: Confirm the statistics cache is trustworthy (read-only)

   Everything this skill displays is quoted from `statistics`, which is a
   **cache** of the features collection — so verify it before quoting it:

   ```bash
   bash "${CLAUDE_SKILL_DIR}/../../scripts/blueprint-tracker-check.sh" --project-dir "$(pwd)"
   ```

   On `STATUS=ERROR` with `TYPE=statistics_divergence` rows, display the
   recomputed `EXPECTED=` figures (not the cached ones) and add a line to the
   report: `Statistics cache is stale — run /blueprint:feature-tracker-sync`.
   Surface any other `ISSUES:` rows verbatim under a "Tracker Integrity"
   heading. This skill never writes, so it reports and defers the fix to
   `/blueprint:feature-tracker-sync` (its Step 7a).

### Step 4: Display status report

   Render the display from the template in
   [references/status-display.md](references/status-display.md), which also
   holds a filled-in example and the quick commands to show at the end of the
   display. Use the Step 5 progress bar for `{progress_bar}`.

### Step 4a: Resolve portfolio links (v3.3.0+)

   For each feature with non-empty `implemented_by`, open each referenced child
   `<workspace>/docs/blueprint/feature-tracker.json` and look up the `ref` FR to
   obtain its current status. Warn (do not fail) on missing workspaces or
   refs; suggest `/blueprint:workspace-scan` + `/blueprint:feature-tracker-sync`.

### Step 5: Display visual progress bar

   Create ASCII progress bar:
   ```
   [##########----------] 52.4%
   ```
   - `#` for complete percentage
   - `-` for remaining
   - 20 characters wide

### Step 6: Check for staleness

   - If `last_updated` is more than 7 days old, warn:
     ```
     Note: Tracker hasn't been synced in {N} days.
     Run `/blueprint:feature-tracker-sync` to update.
     ```

### Step 7: Prompt for next action (use AskUserQuestion)

   Build options dynamically based on state:
   - If stale → Include "Sync feature tracker"
   - If not_started features exist → Include "Start next feature"
   - If in_progress features exist → Include "Continue current work"
   - Always include "View detailed breakdown" and "Exit"

   ```
   question: "What would you like to do?"
   options:
     {Dynamic options based on state}
     - label: "Sync feature tracker" (if stale)
       description: "Update tracker from project state"
     - label: "Start next feature" (if not_started exist)
       description: "Begin work on the next pending feature"
     - label: "Continue current work" (if in_progress exist)
       description: "Resume work on in-progress features"
     - label: "View features by status"
       description: "List all features filtered by status"
     - label: "Exit"
       description: "Done viewing status"
   ```

   **Based on selection:**
   - "Sync" → Run `/blueprint:feature-tracker-sync`
   - "Start next" → Show next not_started feature details, suggest starting
   - "Continue" → Show in_progress features, suggest continuing
   - "View by status" → Ask which status, then list matching features
   - "Exit" → End command

## Agentic Optimizations

| Context | Command |
|---------|---------|
| Cached stats only | `jq -c '.statistics' docs/blueprint/feature-tracker.json` |
| Is the cache trustworthy? | `bash "${CLAUDE_SKILL_DIR}/../../scripts/blueprint-tracker-check.sh" \| grep -E '^(STATUS\|ISSUE_COUNT)='` |
| Recomputed vs cached figures | `bash "${CLAUDE_SKILL_DIR}/../../scripts/blueprint-tracker-check.sh" \| grep -E '^(EXPECTED\|ACTUAL)_'` |
| Blocked features only | `jq -r '.. \| objects \| select(.status? == "blocked") \| .name' docs/blueprint/feature-tracker.json` |
