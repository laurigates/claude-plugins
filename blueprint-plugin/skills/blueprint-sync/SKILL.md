---
model: opus
created: 2025-12-22
modified: 2026-02-06
reviewed: 2025-12-22
description: "Check for stale generated content and offer regeneration or promotion"
allowed-tools: Read, Bash, Glob, AskUserQuestion
name: blueprint-sync
---

Check the status of generated content and offer options for modified or stale files.

**Purpose**:
- Detect when generated skills/commands have been manually modified
- Detect when source PRDs have changed (making generated content stale)
- Offer appropriate actions: regenerate, promote to custom, or keep as-is

**Steps**:

1. **Read manifest**:
   ```bash
   cat docs/blueprint/manifest.json
   ```
   - Extract `generated.rules` section
   - If no generated content, report "Nothing to sync"

2. **Check each generated rule**:
   For each rule in `manifest.generated.rules`:

   a. **Verify file exists**:
      ```bash
      test -f .claude/rules/{name}.md
      ```

   b. **Hash current content**:
      ```bash
      sha256sum .claude/rules/{name}.md | cut -d' ' -f1
      ```

   c. **Compare hashes**:
      - If `content_hash` matches → status: `current`
      - If `content_hash` differs → status: `modified`

   d. **Check source freshness** (for rules from PRDs):
      - Hash current PRD content
      - Compare with `source_hash` in manifest
      - If differs → status: `stale`

3. **Display sync report**:
   ```
   Generated Content Sync Status

   Rules (.claude/rules/):
   ✅ architecture-patterns.md: Current
   ⚠️ testing-strategies.md: Modified locally
   🔄 implementation-guides.md: Stale (PRDs changed)
   ✅ quality-standards.md: Current

   Summary:
   - Current: 3 files
   - Modified: 1 file (user edited)
   - Stale: 1 file (source changed)
   ```

4. **For modified content**, offer options:
   ```
   question: "{name} has been modified locally. What would you like to do?"
   options:
     - label: "Keep modifications"
       description: "Mark as acknowledged, preserve your changes"
     - label: "Discard modifications (regenerate)"
       description: "Overwrite with fresh generation from PRDs"
     - label: "View diff"
       description: "See what changed before deciding"
     - label: "Skip this file"
       description: "Leave as-is for now"
   ```

   **Based on selection:**
   - "Keep modifications" → Update `content_hash` to current, mark as acknowledged
   - "Regenerate" → Regenerate this rule from PRDs
   - "View diff" → Show diff then re-ask
   - "Skip" → Continue to next file

5. **For stale content**, offer options:
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
   - "Regenerate" → Regenerate this rule from PRDs
   - "Keep" → Update `source_hash` to current, mark as current
   - "View" → Show PRD diff then re-ask
   - "Skip" → Continue to next file

6. **Update manifest** after changes:
   - Update `content_hash` for regenerated files
   - Update `source_hash` if PRD changes acknowledged
   - Update `status` field appropriately

7. **Final report**:
   ```
   Sync Complete

   Actions taken:
   - testing-strategies.md: Modifications acknowledged
   - implementation-guides.md: Regenerated from PRDs

   Current state:
   - 4 generated rules (all current)

   Manifest updated.
   ```

**Tips**:
- Run `/blueprint:sync` periodically to check for drift
- Acknowledge modifications you want to keep
- Regenerating will overwrite local changes
- Stale content still works, but may miss new patterns from PRDs
