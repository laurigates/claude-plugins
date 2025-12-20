---
created: 2025-12-17
modified: 2025-12-17
reviewed: 2025-12-17
description: "Show blueprint version, configuration, and check for available upgrades"
allowed_tools: [Read, Bash, Glob]
---

Display the current blueprint configuration status and check for upgrades.

**Steps**:

1. **Check if blueprint is initialized**:
   - Look for `.claude/blueprints/.manifest.json`
   - If not found, report:
     ```
     ❌ Blueprint not initialized in this project.
     Run `/blueprint-init` to get started.
     ```

2. **Read manifest and gather information**:
   - Parse `.manifest.json` for version and configuration
   - Count PRDs in `.claude/blueprints/prds/`
   - Count work-orders (pending, completed, archived)
   - Check for `.claude/rules/` directory and count rules
   - Check for `CLAUDE.md` file

3. **Check for upgrade availability**:
   - Compare `format_version` in manifest with current plugin version
   - Current format version: **1.1.0**
   - If manifest version < current → upgrade available

4. **Display status report**:
   ```
   📋 Blueprint Status

   Version: v{format_version} {upgrade_indicator}
   Initialized: {created_at}
   Last Updated: {updated_at}

   Project Configuration:
   - Name: {project.name}
   - Type: {project.type}
   - Rules Mode: {structure.claude_md_mode}

   Content:
   - PRDs: {count} documents
   - Work Orders: {pending} pending, {completed} completed, {archived} archived
   - Generated Commands: {count}
   - Generated Skills: {count}
   - Modular Rules: {count} files

   Structure:
   ✅ .claude/blueprints/.manifest.json
   {✅|❌} .claude/blueprints/prds/
   {✅|❌} .claude/blueprints/work-orders/
   {✅|❌} .claude/blueprints/work-overview.md
   {✅|❌} .claude/rules/
   {✅|❌} CLAUDE.md

   {If upgrade available:}
   ⬆️  Upgrade available: v{current} → v{latest}
      Run `/blueprint-upgrade` to upgrade.

   {If up to date:}
   ✅ Blueprint is up to date.
   ```

5. **Additional checks**:
   - Warn if work-overview.md is stale (older than latest work-order)
   - Warn if PRDs exist but no work-orders generated
   - Warn if modular rules enabled but `.claude/rules/` is empty
   - Suggest next actions based on state

**Example Output**:
```
📋 Blueprint Status

Version: v1.0.0 (upgrade available!)
Initialized: 2024-01-10T09:00:00Z
Last Updated: 2024-01-15T14:30:00Z

Project Configuration:
- Name: my-awesome-project
- Type: team
- Rules Mode: both

Content:
- PRDs: 3 documents
- Work Orders: 5 pending, 12 completed, 2 archived
- Generated Commands: 2 (project-continue, project-test-loop)
- Generated Skills: 4
- Modular Rules: 3 files

Structure:
✅ .claude/blueprints/.manifest.json
✅ .claude/blueprints/prds/
✅ .claude/blueprints/work-orders/
✅ .claude/blueprints/work-overview.md
✅ .claude/rules/
✅ CLAUDE.md

⬆️  Upgrade available: v1.0.0 → v1.1.0
   Run `/blueprint-upgrade` to upgrade.

💡 Suggestions:
- work-overview.md hasn't been updated in 3 days
- Consider running `/blueprint-claude-md` to sync CLAUDE.md
```
