---
created: 2025-12-17
modified: 2026-01-09
reviewed: 2026-01-09
description: "Upgrade blueprint structure to the latest format version"
allowed_tools: [Read, Write, Edit, Bash, Glob, AskUserQuestion]
---

Upgrade the blueprint structure to the latest format version.

**Current Format Version**: 2.0.0

This command delegates version-specific migration logic to the `blueprint-migration` skill.

**Steps**:

1. **Check current state**:
   - Read `.claude/blueprints/.manifest.json`
   - If not found, suggest running `/blueprint:init` instead
   - Extract current `format_version` (default to "1.0.0" if field missing)

2. **Determine upgrade path**:
   ```bash
   # Read current version
   current=$(jq -r '.format_version // "1.0.0"' .claude/blueprints/.manifest.json)
   target="2.0.0"
   ```

   **Version compatibility matrix**:
   | From Version | To Version | Migration Document |
   |--------------|------------|-------------------|
   | 1.0.x        | 1.1.x      | `migrations/v1.0-to-v1.1.md` |
   | 1.x.x        | 2.0.0      | `migrations/v1.x-to-v2.0.md` |
   | 2.0.0        | 2.0.0      | Already up to date |

3. **Display upgrade plan**:
   ```
   Blueprint Upgrade

   Current version: v{current}
   Target version: v2.0.0

   Major changes in v2.0:
   - PRDs, ADRs, PRPs move to docs/ (project documentation)
   - Generated content tracked in .claude/blueprints/generated/
   - Custom overrides in .claude/skills/ and .claude/commands/
   - Content hashing for modification detection
   ```

4. **Confirm with user** (use AskUserQuestion):
   ```
   question: "Ready to upgrade blueprint from v{current} to v2.0.0?"
   options:
     - "Yes, upgrade now" → proceed
     - "Show detailed migration steps" → display migration document
     - "Create backup first" → run git stash or backup then proceed
     - "Cancel" → exit
   ```

5. **Load and execute migration document**:
   - Read the appropriate migration document from `blueprint-migration` skill
   - For v1.x → v2.0: Load `migrations/v1.x-to-v2.0.md`
   - Execute each step with user confirmation for destructive operations

6. **v1.x → v2.0 migration overview** (from migration document):

   a. **Create docs/ structure**:
      ```bash
      mkdir -p docs/prds docs/adrs docs/prps
      ```

   b. **Move documentation to docs/**:
      - `.claude/blueprints/prds/*` → `docs/prds/`
      - `.claude/blueprints/adrs/*` → `docs/adrs/`
      - `.claude/blueprints/prps/*` → `docs/prps/`

   c. **Create generated/ structure**:
      ```bash
      mkdir -p .claude/blueprints/generated/skills
      mkdir -p .claude/blueprints/generated/commands
      ```

   d. **Relocate generated content**:
      - For each skill in `manifest.generated_artifacts.skills`:
        - Hash current content
        - If modified: offer to promote to `.claude/skills/` (custom layer)
        - Otherwise: move to `.claude/blueprints/generated/skills/`

   e. **Update manifest to v2.0.0 schema**:
      - Add `generated` section with content tracking
      - Add `custom_overrides` section
      - Add `project.detected_stack` field
      - Bump `format_version` to "2.0.0"

   f. **Enable document detection option** (new in v2.1):
      ```
      Use AskUserQuestion:
      question: "Would you like to enable automatic document detection? (New feature)"
      options:
        - label: "Yes - Detect PRD/ADR/PRP opportunities"
          description: "Claude will prompt when conversations should become documents"
        - label: "No - Keep manual commands only"
          description: "Continue using explicit /blueprint: commands"
      ```

      If enabled:
      - Set `has_document_detection: true` in manifest
      - If modular rules enabled, copy `document-management-rule.md` template to `.claude/rules/document-management.md`

   g. **Migrate root documentation** (if any found):
      ```bash
      # Find documentation files in root (excluding standard files)
      fd -d 1 -e md . | grep -viE '^\./(README|CHANGELOG|CONTRIBUTING|LICENSE|CODE_OF_CONDUCT|SECURITY)'
      ```

      If documentation files found (e.g., REQUIREMENTS.md, ARCHITECTURE.md, DESIGN.md):
      ```
      Use AskUserQuestion:
      question: "Found documentation files in root: {file_list}. Would you like to migrate them to docs/?"
      options:
        - label: "Yes, migrate to docs/"
          description: "Move to appropriate docs/ subdirectory"
        - label: "No, leave in root"
          description: "Keep files in current location"
      ```

      If "Yes" selected:
      - Analyze each file to determine document type
      - Move to appropriate `docs/` subdirectory
      - Record migration in upgrade_history

7. **Update manifest**:
   ```json
   {
     "format_version": "2.0.0",
     "created_at": "[preserved]",
     "updated_at": "[now]",
     "created_by": {
       "blueprint_plugin": "2.0.0"
     },
     "project": {
       "name": "[preserved]",
       "type": "[preserved]",
       "detected_stack": []
     },
     "structure": {
       "has_prds": true,
       "has_adrs": "[detected]",
       "has_prps": "[detected]",
       "has_work_orders": true,
       "has_ai_docs": "[detected]",
       "has_modular_rules": "[preserved]",
       "has_document_detection": "[based on user choice]",
       "claude_md_mode": "[preserved]"
     },
     "generated": {
       "skills": {
         "[skill-name]": {
           "source": "docs/prds/...",
           "source_hash": "sha256:...",
           "generated_at": "[now]",
           "plugin_version": "2.0.0",
           "content_hash": "sha256:...",
           "status": "current"
         }
       },
       "commands": {}
     },
     "custom_overrides": {
       "skills": ["[any promoted skills]"],
       "commands": []
     },
     "upgrade_history": [
       {
         "from": "{previous}",
         "to": "2.0.0",
         "date": "[now]",
         "changes": ["Moved PRDs to docs/", "Created generated/ layer", "..."]
       }
     ]
   }
   ```

8. **Report**:
   ```
   Blueprint upgraded successfully!

   v{previous} → v2.0.0

   Moved to docs/:
   - {n} PRDs
   - {n} ADRs
   - {n} PRPs

   Generated layer (.claude/blueprints/generated/):
   - {n} skills
   - {n} commands

   Custom layer (.claude/skills/, .claude/commands/):
   - {n} promoted skills (preserved modifications)
   - {n} promoted commands

   [Document detection: enabled (if selected)]
   [Migrated root documentation: {list of files} (if migrated)]

   New architecture:
   - Plugin layer: Auto-updated with blueprint-plugin
   - Generated layer: Regeneratable from docs/prds/
   - Custom layer: Your overrides, never auto-modified
   ```

9. **Prompt for next action** (use AskUserQuestion):
   ```
   question: "Upgrade complete. What would you like to do next?"
   options:
     - label: "Check status (Recommended)"
       description: "Run /blueprint:status to see updated configuration"
     - label: "Regenerate skills from PRDs"
       description: "Update generated skills with new tracking"
     - label: "Update CLAUDE.md"
       description: "Reflect new architecture in project docs"
     - label: "Commit changes"
       description: "Stage and commit the migration"
   ```

   **Based on selection:**
   - "Check status" → Run `/blueprint:status`
   - "Regenerate skills" → Run `/blueprint:generate-skills`
   - "Update CLAUDE.md" → Run `/blueprint:claude-md`
   - "Commit changes" → Run `/git:commit` with migration message

**Rollback**:
If upgrade fails:
- Check git status for changes made
- Use `git checkout -- .claude/` to restore original structure
- Manually move docs/ content back if needed
- Report specific failure point for debugging
