---
created: 2025-12-17
modified: 2025-12-17
reviewed: 2025-12-17
description: "Upgrade blueprint structure to the latest format version"
allowed_tools: [Read, Write, Edit, Bash, Glob, AskUserQuestion]
---

Upgrade the blueprint structure to the latest format version.

**Current Format Version**: 1.1.0

**Steps**:

1. **Check current state**:
   - Read `.claude/blueprints/.manifest.json`
   - If not found, suggest running `/blueprint-init` instead
   - Compare versions to determine upgrade path

2. **Display upgrade plan**:
   ```
   🔄 Blueprint Upgrade

   Current version: v{current}
   Target version: v1.1.0

   Changes to be applied:
   {list of changes based on version delta}
   ```

3. **Confirm with user** (use AskUserQuestion):
   ```
   question: "Ready to upgrade blueprint from v{current} to v1.1.0?"
   options:
     - "Yes, upgrade now" → proceed
     - "Show detailed changes first" → display migration details
     - "Create backup first" → backup then proceed
     - "Cancel" → exit
   ```

4. **Apply migrations based on version**:

   **v1.0.0 → v1.1.0 migrations**:
   - Create `.manifest.json` if missing (for pre-manifest blueprints)
   - Add `project` section to manifest
   - Add `structure.has_modular_rules` field
   - Add `structure.claude_md_mode` field
   - Add `generated_artifacts.rules` array
   - Create `.claude/rules/` directory structure (optional)

   **Pre-1.0.0 → v1.1.0 migrations** (legacy detection):
   - Detect if `.claude/blueprints/` exists without manifest
   - Create manifest from detected structure
   - Preserve existing content

5. **Offer modular rules migration** (use AskUserQuestion):
   ```
   question: "Would you like to enable modular rules?"
   options:
     - "Yes, create .claude/rules/ structure" → create rules dir
     - "Yes, and migrate sections from CLAUDE.md" → extract and migrate
     - "No, keep current setup" → skip
   ```

6. **If migrating from CLAUDE.md**:
   - Parse existing CLAUDE.md for major sections
   - Offer to split into modular rules:
     - Development workflow → `rules/development.md`
     - Testing requirements → `rules/testing.md`
     - Code style → `rules/code-style.md`
     - Architecture patterns → `rules/architecture.md`
   - Keep CLAUDE.md as overview, reference rules/

7. **Update manifest**:
   ```json
   {
     "format_version": "1.1.0",
     "created_at": "[preserved]",
     "updated_at": "[now]",
     "upgraded_from": "{previous_version}",
     "created_by": {
       "blueprint_plugin": "1.0.0"
     },
     "project": {
       "name": "[detected or asked]",
       "type": "[detected or asked]"
     },
     "structure": {
       "has_prds": true,
       "has_work_orders": true,
       "has_ai_docs": "[detected]",
       "has_templates": "[detected]",
       "has_modular_rules": "[user choice]",
       "claude_md_mode": "[user choice]"
     },
     "generated_artifacts": {
       "commands": "[detected]",
       "skills": "[detected]",
       "rules": "[created]"
     },
     "upgrade_history": [
       {
         "from": "{previous}",
         "to": "1.1.0",
         "date": "[now]",
         "changes": ["list of applied changes"]
       }
     ]
   }
   ```

8. **Report**:
   ```
   ✅ Blueprint upgraded successfully!

   v{previous} → v1.1.0

   Changes applied:
   - {list of changes}

   New features available:
   - Version tracking via .manifest.json
   - Modular rules support (.claude/rules/)
   - CLAUDE.md management commands

   Run `/blueprint-status` to see current configuration.
   ```

**Rollback**:
If upgrade fails:
- Restore from backup (if created)
- Report what went wrong
- Suggest manual fixes

**Version Compatibility Matrix**:
| From Version | To Version | Migrations |
|--------------|------------|------------|
| (none)       | 1.1.0      | Full init with manifest |
| 1.0.0        | 1.1.0      | Add manifest fields, optional rules migration |
| 1.1.0        | 1.1.0      | Already up to date |
