---
created: 2025-12-22
modified: 2026-08-09
reviewed: 2026-08-09
description: "Check for stale generated content and offer regeneration or promotion. Use when syncing blueprint after PRD changes, or reconciling .claude/rules/ drift."
args: "[--dry-run]"
argument-hint: "--dry-run to preview sync status without modifying files"
allowed-tools: Read, Bash, Glob, AskUserQuestion
name: blueprint-sync
---

Check the status of generated content and offer options for modified or stale files.

## When to Use This Skill

| Use this skill when... | Use blueprint-promote instead when... |
|---|---|
| You want to detect stale or modified generated rules/skills | You've decided to keep one specific edited rule (single artifact) |
| You're reconciling drift between `.claude/rules/` and the manifest | You want to acknowledge modifications and stop sync warnings |
| You want regenerate/promote/keep options for many files at once | Use blueprint-generate-rules instead to (re)generate from PRDs |
| You preview status with `--dry-run` before changing anything | Use blueprint-sync-ids instead for ID assignment, not content drift |

## Flags

| Flag | Description |
|------|-------------|
| `--dry-run` | Preview sync status report without interactive prompts or file modifications |

## Interaction Mode

Before any closing `AskUserQuestion` menu, resolve the automation config:

```bash
bash "${CLAUDE_SKILL_DIR}/../../scripts/get-automation-config.sh"
```

When `EFFECTIVE_INTERACTION_MODE=quiet` **and** this invocation was
automation-initiated (autopilot, session bookend, drift-nudge follow-up — not
a slash command the user typed), skip closing navigation menus ("what next?" /
"create another?" style): apply the safe default and end with a one-line
receipt instead. Quiet mode never skips confirmation gates that guard writes —
only navigation menus. A direct user invocation always behaves fully
interactively (explicit intent overrides quiet; see ADR-0020).

## Steps

**Purpose**:
- Detect when generated skills/commands have been manually modified
- Detect when source PRDs have changed (making generated content stale)
- Offer appropriate actions: regenerate, promote to custom, or keep as-is

1. **Read manifest**:
   ```bash
   cat docs/blueprint/manifest.json
   ```
   - Extract `generated.rules` section
   - If no generated content, report "Nothing to sync"

2. **Check each generated rule**:

   First resolve the rules directory from the manifest — never hardcode
   `.claude/rules/`, or sync looks in the wrong place in every repo that chose
   an isolated `generated_rules_path` in `/blueprint:init` Step 4a
   (issues #1043, #1675, #2331):

   ```bash
   RULES_DIR=$(jq -r '.structure.generated_rules_path // ".claude/rules/"' docs/blueprint/manifest.json)
   RULES_DIR="${RULES_DIR%/}"
   ```

   `generated.rules` is an **object map** keyed by filename (see
   `blueprint-plugin/schemas/manifest.schema.json`), so iterate it with
   `to_entries[]`:

   ```bash
   jq -r '(.generated.rules // {}) | to_entries[] | [.key, (.value.content_hash // ""), (.value.source_hash // "")] | @tsv' docs/blueprint/manifest.json
   ```

   For each entry, `{key}` is the rule's **bare filename including the `.md`
   extension**, relative to `$RULES_DIR`. Resolve it as `"$RULES_DIR/{key}"` —
   do **not** append `.md`, which would look for `development.md.md` and report
   every registered rule as missing.

   a. **Verify file exists**:
      ```bash
      test -f "$RULES_DIR/{key}"
      ```

   b. **Hash current content** (bare hex, matching the `content_hash` the
      producers write — no `sha256:` prefix):
      ```bash
      sha256sum "$RULES_DIR/{key}" | cut -d' ' -f1
      ```

   c. **Compare hashes**:
      - If `content_hash` matches → status: `current`
      - If `content_hash` differs → status: `modified`

   d. **Check source freshness** (for rules from PRDs):
      - Hash current PRD content
      - Compare with `source_hash` in manifest
      - If differs → status: `stale`
      - A record with no `source_hash` (rules written by `/blueprint:init`) is
        never stale — only `modified` applies

3. **Display sync report**:
   ```
   Generated Content Sync Status

   Rules ($RULES_DIR):
   ✅ architecture-patterns.md: Current
   ⚠️ testing-strategies.md: Modified locally
   🔄 implementation-guides.md: Stale (PRDs changed)
   ✅ quality-standards.md: Current

   Summary:
   - Current: 3 files
   - Modified: 1 file (user edited)
   - Stale: 1 file (source changed)
   ```

4. **If `--dry-run`**: Output the sync report from Step 3 and exit. Skip all remaining steps.

5. **For modified content**, offer options:
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
   - "Regenerate" → Regenerate this rule from PRDs
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
