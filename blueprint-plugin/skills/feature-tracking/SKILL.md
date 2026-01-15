---
created: 2026-01-02
modified: 2026-01-09
reviewed: 2026-01-02
name: feature-tracking
description: "Track feature implementation status against requirements documents. Provides hierarchical FR code tracking, phase management, and sync with work-overview.md and TODO.md."
---

# Feature Tracking Skill

Track feature implementation status against requirements documents using hierarchical FR codes.

## Overview

The feature tracker maintains a JSON file that maps requirements from a source document (e.g., REQUIREMENTS.md) to implementation status. It supports:

- **Hierarchical FR codes**: FR1, FR2.1, FR2.1.1, etc.
- **Phase-based development**: Group features by development phase
- **PRD integration**: Link features to Product Requirements Documents
- **Sync targets**: Keep work-overview.md and TODO.md in sync

## When to Use

Run feature tracking operations when:
- Feature implementation status changes
- New PRD is added or completed
- After major development milestones
- Before generating status reports
- Starting a new development phase

## Core Concepts

### Feature Status

Each feature has one of five statuses:
- `complete`: Implementation files exist, tests pass, TODO item checked
- `partial`: Some implementation exists, not all sub-features done
- `in_progress`: Active work, files modified recently
- `not_started`: No implementation files, TODO unchecked
- `blocked`: Missing dependencies or explicitly marked

### Hierarchical Structure

Features are organized hierarchically:
```
FR1 (Game Setup & Configuration)
├── FR1.1 (Window Configuration)
├── FR1.2 (Game Mode Selection)
│   ├── FR1.2.1 (Versus Mode)
│   └── FR1.2.2 (Cooperative Mode)
└── FR1.3 (Scenario Setup)
```

### Phase Organization

Features are grouped by development phase:
- `phase-0`: Foundation
- `phase-1`: Core gameplay
- `phase-2`: Advanced features
- etc.

## File Structure

```
docs/blueprint/
├── feature-tracker.json       # Main tracker file
├── work-overview.md           # Sync target: progress overview
└── schemas/                   # Optional: local schema copy
    └── feature-tracker.schema.json
```

The project's `TODO.md` is also a sync target.

## Quick Commands

### View completion stats
```bash
jq '.statistics' docs/blueprint/feature-tracker.json
```

### List incomplete features
```bash
jq -r '.. | objects | select(.status == "not_started") | .name' docs/blueprint/feature-tracker.json
```

### Show PRD completion
```bash
jq '.prds | to_entries | .[] | "\(.key): \(.value.status)"' docs/blueprint/feature-tracker.json
```

### List features by phase
```bash
jq -r '.. | objects | select(.phase == "phase-1") | .name' docs/blueprint/feature-tracker.json
```

### Count features by status
```bash
jq '[.. | objects | select(.status?) | .status] | group_by(.) | map({(.[0]): length}) | add' docs/blueprint/feature-tracker.json
```

## Schema

The feature tracker uses a JSON Schema for validation. The schema is bundled with the blueprint-plugin at:
```
schemas/feature-tracker.schema.json
```

Key schema features:
- Strict FR code validation: `^FR\d+(\.\d+)*$`
- Phase pattern validation: `^phase-\d+$`
- Recursive feature definitions for nesting
- PRD naming pattern: `^PRD_[A-Z_]+$`

### Validate tracker
```bash
# Using ajv-cli or similar JSON schema validator
ajv validate -s schemas/feature-tracker.schema.json \
             -d docs/blueprint/feature-tracker.json
```

## Integration Points

### Manifest Integration

The `manifest.json` references the feature tracker:
```json
{
  "structure": {
    "has_feature_tracker": true
  },
  "feature_tracker": {
    "file": "feature-tracker.json",
    "source_document": "REQUIREMENTS.md",
    "sync_targets": ["work-overview.md", "TODO.md"]
  }
}
```

### PRD Mapping

Features link to PRDs via the `prd` field:
```json
{
  "name": "Terrain Visual Enhancement",
  "status": "complete",
  "prd": "PRD_TERRAIN_VISUAL_ENHANCEMENT"
}
```

PRDs track which features they implement:
```json
{
  "PRD_TERRAIN_VISUAL_ENHANCEMENT": {
    "name": "Terrain Visual Enhancement",
    "status": "complete",
    "features_implemented": ["FR2.8.1", "FR2.8.2", "FR2.8.3"],
    "tests_passing": 107
  }
}
```

### Work Order Integration

Work orders can reference specific FR codes. When a work order is completed, update the corresponding feature status in the tracker.

## Sync Process

The sync process ensures consistency between:
1. `feature-tracker.json` (source of truth)
2. `work-overview.md` (human-readable summary)
3. `TODO.md` (checkbox-based task list)

### Sync Steps

1. **Load current state** from feature-tracker.json
2. **Compare** with work-overview.md and TODO.md
3. **Verify** implementation status for each feature
4. **Recalculate** statistics
5. **Update** sync targets with changes
6. **Report** what was synchronized

### Status Verification

For each feature, verify:
- `complete`: Files exist, tests pass (if applicable), TODO checked
- `partial`: Some files exist, not all sub-features complete
- `in_progress`: Recent commits touch feature files
- `not_started`: No implementation evidence
- `blocked`: Documented dependency issues

## Commands

Related blueprint commands:
- `/blueprint-feature-tracker-status`: Display statistics and completion summary
- `/blueprint-feature-tracker-sync`: Synchronize tracker with sync targets

## Example: Updating Feature Status

When completing a feature:

1. Update feature status in `feature-tracker.json`:
   ```json
   {
     "name": "Unit Selection",
     "status": "complete",
     "phase": "phase-2",
     "implementation": {
       "files": ["src/systems/selection.rs"],
       "notes": "Box selection and click selection",
       "tests": ["tests/selection_tests.rs"]
     }
   }
   ```

2. Run `/blueprint-feature-tracker-sync` to update:
   - work-overview.md "Completed" section
   - TODO.md checkboxes
   - Statistics recalculation

3. Commit all changes together for consistency

## Statistics

The tracker maintains aggregate statistics:
```json
{
  "statistics": {
    "total_features": 42,
    "complete": 22,
    "partial": 4,
    "in_progress": 2,
    "not_started": 14,
    "blocked": 0,
    "completion_percentage": 52.4
  }
}
```

These are recalculated during sync operations.
