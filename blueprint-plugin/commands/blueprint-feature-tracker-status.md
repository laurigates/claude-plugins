---
created: 2026-01-02
modified: 2026-01-02
reviewed: 2026-01-02
description: "Display feature tracker statistics and completion summary"
allowed_tools: [Read, Bash, AskUserQuestion]
---

Display feature tracker statistics, phase progress, and completion summary.

**Steps**:

1. **Check if feature tracking is enabled**:
   - Look for `.claude/blueprints/feature-tracker.json`
   - If not found, report:
     ```
     Feature tracking not enabled in this project.
     Run `/blueprint-init` and enable feature tracking to get started.
     ```

2. **Load tracker data**:
   - Read `feature-tracker.json`
   - Extract project name, source document, last_updated
   - Get statistics section
   - Get phase information
   - Get PRD status

3. **Calculate derived metrics** (if not in statistics):
   - Count features by status at all nesting levels
   - Calculate completion percentage
   - Count features per phase
   - Count PRDs by status

4. **Display status report**:
   ```
   Feature Tracker Status
   ======================
   Project: {project}
   Source: {source_document}
   Last Updated: {last_updated}

   Overall Progress:
   ==================
   {progress_bar} {completion_percentage}% ({complete}/{total_features})

   Complete:     {complete}
   Partial:      {partial}
   In Progress:  {in_progress}
   Not Started:  {not_started}
   Blocked:      {blocked}

   Phase Progress:
   ===============
   {For each phase:}
   Phase {N}: {name}
   Status: {status}
   Features: {complete}/{total} complete

   PRD Coverage:
   =============
   {For each PRD:}
   {PRD_NAME}: {status}
     Features: {features_implemented count}
     {If tests_passing:} Tests: {tests_passing} passing

   {If blocked features exist:}
   Blocked Features:
   =================
   {For each blocked feature:}
   - {FR code}: {name}
     Reason: {implementation.notes or "No reason documented"}

   {If not_started features exist and count <= 10:}
   Ready to Start:
   ===============
   {List first 10 not_started features by phase order}
   - {FR code}: {name} (Phase {N})
   ```

5. **Display visual progress bar**:
   Create ASCII progress bar:
   ```
   [##########----------] 52.4%
   ```
   - `#` for complete percentage
   - `-` for remaining
   - 20 characters wide

6. **Check for staleness**:
   - If `last_updated` is more than 7 days old, warn:
     ```
     Note: Tracker hasn't been synced in {N} days.
     Run `/blueprint-feature-tracker-sync` to update.
     ```
   - If work-overview.md is newer than tracker, warn:
     ```
     Note: work-overview.md has been modified since last sync.
     Run `/blueprint-feature-tracker-sync` to reconcile.
     ```

7. **Prompt for next action** (use AskUserQuestion):
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
   - "Sync" → Run `/blueprint-feature-tracker-sync`
   - "Start next" → Show next not_started feature details, suggest starting
   - "Continue" → Show in_progress features, suggest continuing
   - "View by status" → Ask which status, then list matching features
   - "Exit" → End command

**Example Output**:
```
Feature Tracker Status
======================
Project: gooho
Source: REQUIREMENTS.md
Last Updated: 2026-01-01

Overall Progress:
==================
[##########----------] 52.4% (22/42)

Complete:     22
Partial:      4
In Progress:  2
Not Started:  14
Blocked:      0

Phase Progress:
===============
Phase 0: Foundation
Status: complete
Features: 4/4 complete

Phase 1: Core Gameplay
Status: complete
Features: 8/8 complete

Phase 2: Advanced Features
Status: in_progress
Features: 10/14 complete

Phase 3-8: Future Development
Status: not_started
Features: 0/16 complete

PRD Coverage:
=============
PRD_GAME_SETUP_FLOW: complete
  Features: 4
  Tests: 45 passing

PRD_TERRAIN_VISUAL_ENHANCEMENT: complete
  Features: 6
  Tests: 107 passing

PRD_ENTITY_BEHAVIOR_SYSTEM: complete
  Features: 8
  Tests: 187 passing

PRD_UI_CONTROLS_SYSTEM: partial
  Features: 3/5

Ready to Start:
===============
- FR3.1: Resource Types (Phase 3)
- FR3.2: Resource Gathering (Phase 3)
- FR3.3: Resource Storage (Phase 3)
- FR4.1: Basic Crafting (Phase 4)
- FR4.2: Recipe System (Phase 4)

Note: 14 features ready to start. Run `/blueprint-feature-tracker-sync` before beginning new work.
```

**Quick Commands** (shown at end):
```
Quick commands for feature tracker:
- jq '.statistics' .claude/blueprints/feature-tracker.json
- jq '.. | objects | select(.status == "not_started") | .name' .claude/blueprints/feature-tracker.json
- jq '.prds | to_entries | .[] | "\(.key): \(.value.status)"' .claude/blueprints/feature-tracker.json
```
