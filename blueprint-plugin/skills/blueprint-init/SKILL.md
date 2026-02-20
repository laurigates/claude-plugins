---
model: haiku
created: 2025-12-16
modified: 2026-02-20
reviewed: 2026-01-17
description: "Initialize Blueprint Development structure in current project"
allowed-tools: Bash, Write, Read, AskUserQuestion, Glob
name: blueprint-init
---

Initialize Blueprint Development in this project.

**Steps**:

1. **Check if already initialized**:
   - Look for `docs/blueprint/manifest.json`
   - If exists, read version and ask user:
     ```
     Use AskUserQuestion:
     question: "Blueprint already initialized (v{version}). What would you like to do?"
     options:
       - "Check for upgrades" → run /blueprint:upgrade
       - "Reinitialize (will reset manifest)" → continue with step 2
       - "Cancel" → exit
     ```

2. **Ask about feature tracking** (use AskUserQuestion):
   ```
   question: "Would you like to enable feature tracking?"
   options:
     - label: "Yes - Track implementation against requirements"
       description: "Creates feature-tracker.json to track FR codes from a requirements document"
     - label: "No - Skip feature tracking"
       description: "Can be added later with /blueprint:feature-tracker-sync"
   ```

   **If "Yes" selected:**
   a. Search for markdown files in the project that contain requirements, features, or user stories
   b. Auto-detect the most likely source document based on content analysis
   c. Create `docs/blueprint/feature-tracker.json` from template using the detected source
   d. Set `has_feature_tracker: true` in manifest

3. **Ask about document migration** (use AskUserQuestion):
   Search for existing markdown documentation files across the project (excluding standard files like README.md, CHANGELOG.md, CONTRIBUTING.md, LICENSE.md, CODE_OF_CONDUCT.md, SECURITY.md).

   ```bash
   # Find markdown files that look like documentation (not standard repo files)
   find . -name '*.md' -not -path '*/node_modules/*' -not -path '*/.git/*' | grep -viE '(README|CHANGELOG|CONTRIBUTING|LICENSE|CODE_OF_CONDUCT|SECURITY)\.md$'
   ```

   **If documentation files found** (e.g., REQUIREMENTS.md, ARCHITECTURE.md, DESIGN.md, docs in non-standard locations):
   ```
   Use AskUserQuestion:
   question: "Found existing documentation: {file_list}. Migrate these to Blueprint-managed paths? (Strongly recommended)"
   options:
     - label: "Yes, migrate documents (Recommended)"
       description: "Move docs into docs/prds/, docs/adrs/, docs/prps/ based on content type. Prevents stale and orphaned documents."
     - label: "No, leave them in place"
       description: "Warning: unmigrated docs may become stale or duplicated as Blueprint creates its own documents"
   ```

   **If "Yes" selected:**
   a. Analyze each file to determine type:
      - Contains requirements, features, user stories → `docs/prds/`
      - Contains architecture decisions, trade-offs → `docs/adrs/`
      - Contains implementation plans → `docs/prps/`
      - General documentation → `docs/`
   b. Move files to appropriate `docs/` subdirectory
   c. Rename to kebab-case if needed (REQUIREMENTS.md → requirements.md)
   d. Report migration results:
      ```
      Migrated documentation:
      - REQUIREMENTS.md → docs/prds/requirements.md
      - ARCHITECTURE.md → docs/adrs/0001-initial-architecture.md
      ```

   **If no documentation files found:** Skip this step silently.

4. **Ask about maintenance task scheduling** (use AskUserQuestion):
   ```
   question: "How should blueprint maintenance tasks run?"
   options:
     - label: "Prompt before running (Recommended)"
       description: "Always ask before running maintenance tasks like sync, validate"
     - label: "Auto-run safe tasks"
       description: "Read-only tasks (validate, sync, status) run automatically when due"
     - label: "Fully automatic"
       description: "All tasks run automatically on schedule, including writes like rule generation"
     - label: "Manual only"
       description: "Tasks only run when you explicitly invoke them"
   ```

   Store selection for task_registry defaults:
   - **Prompt**: all `auto_run: false`, default schedules
   - **Auto-run safe**: read-only tasks (`adr-validate`, `feature-tracker-sync`, `sync-ids`) get `auto_run: true`; write tasks get `false`
   - **Fully automatic**: all tasks get `auto_run: true`, default schedules
   - **Manual only**: all `auto_run: false`, all schedules set to `on-demand`

5. **Ask about decision detection** (use AskUserQuestion):
   ```
   question: "Would you like to enable automatic decision detection?"
   options:
     - label: "Yes - Detect decisions worth documenting"
       description: "Claude will notice when conversations contain architecture decisions, feature requirements, or implementation plans that should be captured as ADR/PRD/PRP documents"
     - label: "No - Manual commands only"
       description: "Use /blueprint:derive-prd, /blueprint:derive-adr, /blueprint:prp-create explicitly when you want to create documents"
   ```

   Set `has_document_detection` in manifest based on response.

   **If enabled:**
   Copy `document-management-rule.md` template to `.claude/rules/document-management.md`.
   This rule instructs Claude to watch for:
   - Architecture decisions being made during discussion → prompt to create ADR
   - Feature requirements being discussed or refined → prompt to create/update PRD
   - Implementation plans being formulated → prompt to create PRP

6. **Create directory structure**:

   **Blueprint structure (in docs/blueprint/):**
   ```
   docs/
   ├── blueprint/
   │   ├── manifest.json            # Version tracking and configuration
   │   ├── feature-tracker.json     # Progress tracking (if enabled)
   │   ├── work-orders/             # Task packages for subagents
   │   │   ├── completed/
   │   │   └── archived/
   │   ├── ai_docs/                 # Curated documentation (on-demand)
   │   │   ├── libraries/
   │   │   └── project/
   │   └── README.md                # Blueprint documentation
   ├── prds/                        # Product Requirements Documents
   ├── adrs/                        # Architecture Decision Records
   └── prps/                        # Product Requirement Prompts
   ```

   **Claude configuration (in .claude/):**
   ```
   .claude/
   ├── rules/                       # Modular rules (including generated)
   │   ├── development.md           # Development workflow rules
   │   ├── testing.md               # Testing requirements
   │   └── document-management.md   # Document organization rules (if detection enabled)
   └── skills/                      # Custom skill overrides (optional)
   ```

7. **Create `manifest.json`** (v3.2.0 schema):
   ```json
   {
     "format_version": "3.2.0",
     "created_at": "[ISO timestamp]",
     "updated_at": "[ISO timestamp]",
     "created_by": {
       "blueprint_plugin": "3.2.0"
     },
     "project": {
       "name": "[detected from package.json/pyproject.toml or directory name]",
       "detected_stack": []
     },
     "structure": {
       "has_prds": true,
       "has_adrs": true,
       "has_prps": true,
       "has_work_orders": true,
       "has_ai_docs": false,
       "has_modular_rules": true,
       "has_feature_tracker": "[based on user choice]",
       "has_document_detection": "[based on user choice]",
       "claude_md_mode": "both"
     },
     "feature_tracker": {
       "file": "feature-tracker.json",
       "source_document": "[auto-detected]",
       "sync_targets": ["TODO.md"]
     },
     "generated": {
       "rules": {},
       "commands": {}
     },
     "custom_overrides": {
       "skills": [],
       "commands": []
     },
     "task_registry": {
       "derive-prd": {
         "enabled": true,
         "auto_run": false,
         "last_completed_at": null,
         "last_result": null,
         "schedule": "on-demand",
         "stats": {},
         "context": {}
       },
       "derive-plans": {
         "enabled": true,
         "auto_run": false,
         "last_completed_at": null,
         "last_result": null,
         "schedule": "weekly",
         "stats": {},
         "context": {}
       },
       "derive-rules": {
         "enabled": true,
         "auto_run": false,
         "last_completed_at": null,
         "last_result": null,
         "schedule": "weekly",
         "stats": {},
         "context": {}
       },
       "generate-rules": {
         "enabled": true,
         "auto_run": false,
         "last_completed_at": null,
         "last_result": null,
         "schedule": "on-change",
         "stats": {},
         "context": {}
       },
       "adr-validate": {
         "enabled": true,
         "auto_run": "[based on maintenance task choice: true if auto-run safe, false otherwise]",
         "last_completed_at": null,
         "last_result": null,
         "schedule": "weekly",
         "stats": {},
         "context": {}
       },
       "feature-tracker-sync": {
         "enabled": true,
         "auto_run": "[based on maintenance task choice: true if auto-run safe, false otherwise]",
         "last_completed_at": null,
         "last_result": null,
         "schedule": "daily",
         "stats": {},
         "context": {}
       },
       "sync-ids": {
         "enabled": true,
         "auto_run": "[based on maintenance task choice: true if auto-run safe, false otherwise]",
         "last_completed_at": null,
         "last_result": null,
         "schedule": "on-change",
         "stats": {},
         "context": {}
       },
       "claude-md": {
         "enabled": true,
         "auto_run": false,
         "last_completed_at": null,
         "last_result": null,
         "schedule": "on-change",
         "stats": {},
         "context": {}
       },
       "curate-docs": {
         "enabled": false,
         "auto_run": false,
         "last_completed_at": null,
         "last_result": null,
         "schedule": "on-demand",
         "stats": {},
         "context": {}
       }
     }
   }
   ```

   Note: Include `feature_tracker` section only if feature tracking is enabled.
   Note: As of v3.2.0, progress tracking is consolidated into feature-tracker.json (work-overview.md removed).

8. **Create initial rules**:
   - `development.md`: TDD workflow, commit conventions
   - `testing.md`: Test requirements, coverage expectations
   - `document-management.md`: Document organization rules (if decision detection enabled)

9. **Handle `.gitignore`**:
   - Always commit `CLAUDE.md` and `.claude/rules/` (shared project instructions)
   - Add `docs/blueprint/work-orders/` to `.gitignore` (task-specific, may contain sensitive details)
   - If secrets detected in `.claude/`, warn user and suggest `.gitignore` entries

10. **Report**:
   ```
   Blueprint Development initialized! (v3.2.0)

   Blueprint structure created:
   - docs/blueprint/manifest.json
   - docs/blueprint/work-orders/
   - docs/blueprint/ai_docs/
   - docs/blueprint/README.md
   [- docs/blueprint/feature-tracker.json (if feature tracking enabled)]

   Project documentation:
   - docs/prds/           (Product Requirements Documents)
   - docs/adrs/           (Architecture Decision Records)
   - docs/prps/           (Product Requirement Prompts)

   Claude configuration:
   - .claude/rules/       (modular rules, including generated)
   - .claude/skills/      (custom skill overrides)

   Configuration:
   - Rules mode: both (CLAUDE.md + .claude/rules/)
   [- Feature tracking: enabled]
   [- Decision detection: enabled (Claude will prompt when discussions should become ADR/PRD/PRP)]
   [- Task scheduling: {prompt|auto-run safe|fully automatic|manual only}]

   [Migrated documentation:]
   [- {original} → {destination} (for each migrated file)]

   Architecture:
   - Plugin layer: Generic commands from blueprint-plugin (auto-updated)
   - Generated layer: Rules/commands regeneratable from docs/prds/
   - Custom layer: Your overrides in .claude/skills/
   ```

11. **Prompt for next action** (use AskUserQuestion):
    ```
    question: "Blueprint initialized. What would you like to do next?"
    options:
      - label: "Derive plans from git history (Recommended)"
        description: "Analyze commit history, PRs, and issues to build PRDs, ADRs, and PRPs from existing project decisions"
      - label: "Derive rules from codebase"
        description: "Analyze commit patterns and code conventions to generate .claude/rules/"
      - label: "Update CLAUDE.md"
        description: "Generate or update CLAUDE.md with project context and blueprint integration"
      - label: "I'm done for now"
        description: "Exit - you can run /blueprint:status anytime to see options"
    ```

    **Based on selection:**
    - "Derive plans from git history" → Run `/blueprint:derive-plans`
    - "Derive rules from codebase" → Run `/blueprint:derive-rules`
    - "Update CLAUDE.md" → Run `/blueprint:claude-md`
    - "I'm done for now" → Show quick reference and exit

**Quick Reference** (show if user selects "I'm done for now"):
```
Management commands:
- /blueprint:status          - Check version and configuration
- /blueprint:upgrade         - Upgrade to latest format version
- /blueprint:derive-prd      - Derive PRD from existing documentation
- /blueprint:derive-adr      - Derive ADRs from codebase analysis
- /blueprint:derive-plans    - Derive docs from git history
- /blueprint:derive-rules    - Derive rules from git commit decisions
- /blueprint:prp-create      - Create a Product Requirement Prompt
- /blueprint:generate-rules  - Generate rules from PRDs
- /blueprint:sync            - Check for stale generated content
- /blueprint:promote         - Move generated content to custom layer
- /blueprint:rules           - Manage modular rules
- /blueprint:claude-md       - Update CLAUDE.md
- /blueprint:feature-tracker-status  - View feature completion stats
- /blueprint:feature-tracker-sync    - Sync tracker with project files
```
