---
created: 2025-12-22
modified: 2025-12-22
reviewed: 2025-12-22
description: "Check for stale generated content and offer regeneration or promotion"
allowed_tools: [Read, Bash, Glob, AskUserQuestion]
---

Check the status of generated content and offer options for modified or stale files.

**Purpose**:
- Detect when generated skills/commands have been manually modified
- Detect when source PRDs have changed (making generated content stale)
- Offer appropriate actions: regenerate, promote to custom, or keep as-is

**Steps**:

1. **Read manifest**:
   ```bash
   cat .claude/blueprints/.manifest.json
   ```
   - Extract `generated.skills` and `generated.commands` sections
   - If no generated content, report "Nothing to sync"

2. **Check each generated skill**:
   For each skill in `manifest.generated.skills`:

   a. **Verify file exists**:
      ```bash
      test -f .claude/blueprints/generated/skills/{name}/skill.md
      ```

   b. **Hash current content**:
      ```bash
      sha256sum .claude/blueprints/generated/skills/{name}/skill.md | cut -d' ' -f1
      ```

   c. **Compare hashes**:
      - If `content_hash` matches → status: `current`
      - If `content_hash` differs → status: `modified`

   d. **Check source freshness** (for skills from PRDs):
      - Hash current PRD content
      - Compare with `source_hash` in manifest
      - If differs → status: `stale`

3. **Check each generated command**:
   Same process as skills, but for `.claude/blueprints/generated/commands/`

4. **Display sync report**:
   ```
   Generated Content Sync Status

   Skills (.claude/blueprints/generated/skills/):
   ✅ architecture-patterns: Current
   ⚠️ testing-strategies: Modified locally
   🔄 implementation-guides: Stale (PRDs changed)
   ✅ quality-standards: Current

   Commands (.claude/blueprints/generated/commands/):
   ✅ project-continue: Current
   ✅ project-test-loop: Current

   Summary:
   - Current: 4 files
   - Modified: 1 file (user edited)
   - Stale: 1 file (source changed)
   ```

5. **For modified content**, offer options:
   ```
   question: "{name} has been modified locally. What would you like to do?"
   options:
     - label: "Keep modifications (promote to custom)"
       description: "Move to .claude/skills/ to preserve your changes"
     - label: "Discard modifications (regenerate)"
       description: "Overwrite with fresh generation from PRDs"
     - label: "View diff"
       description: "See what changed before deciding"
     - label: "Skip this file"
       description: "Leave as-is for now"
   ```

   **Based on selection:**
   - "Promote" → Run `/blueprint:promote {name}`
   - "Regenerate" → Regenerate this skill from PRDs
   - "View diff" → Show diff then re-ask
   - "Skip" → Continue to next file

6. **For stale content**, offer options:
   ```
   question: "{name} is stale (PRDs have changed). What would you like to do?"
   options:
     - label: "Regenerate from PRDs (Recommended)"
       description: "Update with latest patterns from docs/prds/"
     - label: "Keep current version"
       description: "Mark as current without regenerating"
     - label: "View what changed in PRDs"
       description: "See PRD changes before deciding"
     - label: "Skip this file"
       description: "Leave stale for now"
   ```

   **Based on selection:**
   - "Regenerate" → Regenerate this skill from PRDs
   - "Keep" → Update `source_hash` to current, mark as current
   - "View" → Show PRD diff then re-ask
   - "Skip" → Continue to next file

7. **Update manifest** after changes:
   - Update `content_hash` for regenerated files
   - Update `source_hash` if PRD changes acknowledged
   - Update `status` field appropriately

8. **Final report**:
   ```
   Sync Complete

   Actions taken:
   - testing-strategies: Promoted to custom layer
   - implementation-guides: Regenerated from PRDs

   Current state:
   - 4 generated skills (all current)
   - 2 generated commands (all current)
   - 1 custom skill

   Manifest updated.
   ```

**Tips**:
- Run `/blueprint:sync` periodically to check for drift
- Promote skills you want to customize before regenerating
- Regenerating will overwrite local changes - promote first to preserve
- Stale content still works, but may miss new patterns from PRDs
