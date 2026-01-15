---
created: 2025-12-17
modified: 2026-01-09
reviewed: 2025-12-22
description: "Show blueprint version, configuration, and check for available upgrades"
allowed_tools: [Read, Bash, Glob, AskUserQuestion]
---

Display the current blueprint configuration status with three-layer architecture breakdown.

**Steps**:

1. **Check if blueprint is initialized**:
   - Look for `docs/blueprint/manifest.json`
   - If not found, report:
     ```
     Blueprint not initialized in this project.
     Run `/blueprint:init` to get started.
     ```

2. **Read manifest and gather information**:
   - Parse `manifest.json` for version and configuration
   - Count PRDs in `docs/prds/`
   - Count ADRs in `docs/adrs/`
   - Count PRPs in `docs/prps/`
   - Count work-orders (pending, completed, archived)
   - Count generated rules in `.claude/rules/`
   - Count custom skills in `.claude/skills/`
   - Count custom commands in `.claude/commands/`
   - Check for `.claude/rules/` directory
   - Check for `CLAUDE.md` file
   - Check for `docs/blueprint/feature-tracker.json`
   - If feature tracker exists, read statistics and last_updated

3. **Check for upgrade availability**:
   - Compare `format_version` in manifest with current plugin version
   - Current format version: **3.0.0**
   - If manifest version < current → upgrade available

4. **Check generated content status**:
   - For each generated rule in manifest:
     - Hash current file content
     - Compare with stored `content_hash`
     - Status: `current` (unchanged), `modified` (user edited), `stale` (source PRDs changed)

5. **Display status report**:
   ```
   Blueprint Status

   Version: v{format_version} {upgrade_indicator}
   Initialized: {created_at}
   Last Updated: {updated_at}

   Project Configuration:
   - Name: {project.name}
   - Type: {project.type}
   - Stack: {project.detected_stack}
   - Rules Mode: {structure.claude_md_mode}

   Project Documentation (docs/):
   - PRDs: {count} in docs/prds/
   - ADRs: {count} in docs/adrs/
   - PRPs: {count} in docs/prps/

   Work Orders (docs/blueprint/work-orders/):
   - Pending: {count}
   - Completed: {count}
   - Archived: {count}

   Three-Layer Architecture:

   Layer 1: Plugin (blueprint-plugin)
   - Commands: /blueprint:* (auto-updated with plugin)
   - Skills: blueprint-development, blueprint-migration, confidence-scoring
   - Agents: requirements-documentation, architecture-decisions, prp-preparation

   Layer 2: Generated (.claude/rules/)
   - Rules: {count} ({status_summary})
     {list each with status indicator: ✅ current, ⚠️ modified, 🔄 stale}

   Layer 3: Custom (.claude/skills/, .claude/commands/)
   - Skills: {count} (user-maintained)
   - Commands: {count} (user-maintained)

   {If feature_tracker enabled:}
   Feature Tracker:
   - Status: Enabled
   - Source: {feature_tracker.source_document}
   - Progress: {statistics.complete}/{statistics.total_features} ({statistics.completion_percentage}%)
   - Last Sync: {last_updated}
   - Phases: {count in_progress} active, {count complete} complete

   Structure:
   ✅ docs/blueprint/manifest.json
   {✅|❌} docs/prds/
   {✅|❌} docs/adrs/
   {✅|❌} docs/prps/
   {✅|❌} docs/blueprint/work-orders/
   {✅|❌} docs/blueprint/ai_docs/
   {✅|❌} docs/blueprint/feature-tracker.json
   {✅|❌} .claude/rules/
   {✅|❌} CLAUDE.md

   {If upgrade available:}
   Upgrade available: v{current} → v{latest}
      Run `/blueprint:upgrade` to upgrade.

   {If modified generated content:}
   Modified content detected: {count} files
      Run `/blueprint:sync` to review changes.
      Run `/blueprint:promote [name]` to move to custom layer.

   {If stale generated content:}
   Stale content detected: {count} files (PRDs changed since generation)
      Run `/blueprint:generate-skills` to regenerate.

   {If up to date:}
   Blueprint is up to date.
   ```

6. **Additional checks**:
   - Warn if work-overview.md is stale (older than latest work-order)
   - Warn if PRDs exist but no generated rules
   - Warn if modular rules enabled but `.claude/rules/` is empty
   - Warn if generated content is modified or stale
   - Warn if feature-tracker.json is older than 7 days (needs sync)
   - Warn if feature-tracker sync targets have been modified since last sync

7. **Prompt for next action** (use AskUserQuestion):

   **Build options dynamically based on state:**
   - If upgrade available → Include "Upgrade to v{latest}"
   - If modified content → Include "Sync generated content"
   - If stale content → Include "Regenerate skills"
   - If PRDs exist but no generated skills → Include "Generate skills from PRDs"
   - If skills exist but no commands → Include "Generate workflow commands"
   - If CLAUDE.md stale → Include "Update CLAUDE.md"
   - If feature tracker exists but stale → Include "Sync feature tracker"
   - Always include "Continue development" and "I'm done"

   ```
   question: "What would you like to do?"
   options:
     # Dynamic - include based on state detected above
     - label: "Upgrade to v{latest}" (if upgrade available)
       description: "Upgrade blueprint format to latest version"
     - label: "Sync generated content" (if modified)
       description: "Review changes to generated skills/commands"
     - label: "Regenerate from PRDs" (if stale)
       description: "Update generated content from changed PRDs"
     - label: "Generate rules from PRDs" (if PRDs exist, no rules)
       description: "Extract project-specific rules from your PRDs"
     - label: "Update CLAUDE.md" (if stale or missing)
       description: "Regenerate project overview document"
     - label: "Sync feature tracker" (if feature tracker stale)
       description: "Synchronize tracker with work-overview.md and TODO.md"
     # Always include these:
     - label: "Continue development"
       description: "Run /project:continue to work on next task"
     - label: "I'm done for now"
       description: "Exit status check"
   ```

   **Based on selection:**
   - "Upgrade" → Run `/blueprint:upgrade`
   - "Sync" → Run `/blueprint:sync`
   - "Regenerate" → Run `/blueprint:generate-rules`
   - "Generate rules" → Run `/blueprint:generate-rules`
   - "Update CLAUDE.md" → Run `/blueprint:claude-md`
   - "Sync feature tracker" → Run `/blueprint:feature-tracker-sync`
   - "Continue development" → Run `/project:continue`
   - "I'm done" → Exit

**Example Output**:
```
Blueprint Status

Version: v3.0.0
Initialized: 2024-01-10T09:00:00Z
Last Updated: 2024-01-15T14:30:00Z

Project Configuration:
- Name: my-awesome-project
- Type: team
- Stack: typescript, bun, react
- Rules Mode: modular

Project Documentation (docs/):
- PRDs: 3 in docs/prds/
- ADRs: 5 in docs/adrs/
- PRPs: 2 in docs/prps/

Work Orders (docs/blueprint/work-orders/):
- Pending: 5
- Completed: 12
- Archived: 2

Three-Layer Architecture:

Layer 1: Plugin (blueprint-plugin)
- Commands: 13 /blueprint:* commands (auto-updated)
- Skills: 3 (blueprint-development, blueprint-migration, confidence-scoring)
- Agents: 3 (requirements-documentation, architecture-decisions, prp-preparation)

Layer 2: Generated (.claude/rules/)
- Rules: 4 (3 current, 1 modified)
  - ✅ architecture-patterns.md (current)
  - ⚠️ testing-strategies.md (modified locally)
  - ✅ implementation-guides.md (current)
  - ✅ quality-standards.md (current)

Layer 3: Custom (.claude/skills/, .claude/commands/, .claude/rules/)
- Skills: 1 (my-custom-skill)
- Commands: 0
- Rules: 0 (user-maintained)

Feature Tracker:
- Status: Enabled
- Source: REQUIREMENTS.md
- Progress: 22/42 (52.4%)
- Last Sync: 2024-01-14
- Phases: 1 active, 2 complete

Structure:
✅ docs/blueprint/manifest.json
✅ docs/prds/
✅ docs/adrs/
✅ docs/prps/
✅ docs/blueprint/work-orders/
✅ docs/blueprint/ai_docs/
✅ docs/blueprint/feature-tracker.json
✅ .claude/rules/
✅ CLAUDE.md

Modified content detected: 1 file
   Run `/blueprint:sync` to review or `/blueprint:promote testing-strategies` to preserve.

Blueprint is up to date.
```
