# blueprint-feature-tracker-status — Status Display (Step 4)

The display Step 4 renders, a filled-in example, and the quick commands shown
at the end of it.

## Template

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

{If any feature has non-empty implemented_by (monorepo portfolio, v3.3.0+):}
Portfolio Features (linked to child workspaces):
================================================
{For each portfolio feature with implemented_by:}
- {FR code}: {name} — derived status: {status}
  Implemented by:
  {For each link:}
    - {link.workspace}/{link.ref} → {status from child feature-tracker}

{If top-level "workspaces" summary present:}
Workspace Rollups:
==================
{For each workspace key:}
- {path}: {complete}/{total} ({completion_percentage}%) [last synced: {last_synced_at}]
```

## Example output

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

Note: 14 features ready to start. Run `/blueprint:feature-tracker-sync` before beginning new work.
```

## Quick commands

**Quick Commands** (shown at end):
```
Quick commands for feature tracker:
- jq '.statistics' docs/blueprint/feature-tracker.json
- jq '.. | objects | select(.status == "not_started") | .name' docs/blueprint/feature-tracker.json
- jq '.prds | to_entries | .[] | "\(.key): \(.value.status)"' docs/blueprint/feature-tracker.json
```
