---
model: haiku
created: 2025-12-16
modified: 2026-01-17
reviewed: 2026-01-17
description: "Initialize Blueprint Development structure in current project"
allowed_tools: [Bash, Write, Read, AskUserQuestion, Glob]
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

2. **Ask about modular rules**:
   ```
   question: "How would you like to organize project instructions?"
   options:
     - "Single CLAUDE.md file" → traditional approach
     - "Modular rules (.claude/rules/)" → create rules directory structure
     - "Both" → CLAUDE.md for overview, rules/ for specifics
   allowMultiSelect: false
   ```

3. **Ask about feature tracking** (use AskUserQuestion):
   ```
   question: "Would you like to enable feature tracking?"
   options:
     - label: "Yes - Track implementation against requirements"
       description: "Creates feature-tracker.json to track FR codes from a requirements document"
     - label: "No - Skip feature tracking"
       description: "Can be added later with /blueprint-feature-tracker-sync"
   ```

   **If "Yes" selected:**
   a. Ask for source document:
      ```
      question: "Which document contains your feature requirements?"
      options:
        - label: "REQUIREMENTS.md"
          description: "Standard requirements document (most common)"
        - label: "README.md"
          description: "Use README as requirements source"
        - label: "Other"
          description: "Specify a different document"
      ```
   b. Create `docs/blueprint/feature-tracker.json` from template
   c. Set `has_feature_tracker: true` in manifest

4. **Ask about document detection** (use AskUserQuestion):
   ```
   question: "Would you like to enable automatic document detection?"
   options:
     - label: "Yes - Detect PRD/ADR/PRP opportunities"
       description: "Claude will prompt when conversations should become documents"
     - label: "No - Manual commands only"
       description: "Use /blueprint:derive-prd, /blueprint:derive-adr, /blueprint:prp-create explicitly"
   ```

   Set `has_document_detection` in manifest based on response.

   **If modular rules enabled and document detection enabled:**
   Copy `document-management-rule.md` template to `.claude/rules/document-management.md`

5. **Check for root documentation to migrate**:
   ```bash
   # Find markdown files in root that look like documentation (not standard files)
   fd -d 1 -e md . | grep -viE '^\./(README|CHANGELOG|CONTRIBUTING|LICENSE|CODE_OF_CONDUCT|SECURITY)'
   ```

   **If documentation files found in root** (e.g., REQUIREMENTS.md, ARCHITECTURE.md, DESIGN.md):
   ```
   Use AskUserQuestion:
   question: "Found documentation files in root directory: {file_list}. Would you like to organize them?"
   options:
     - label: "Yes, move to docs/"
       description: "Migrate existing docs to proper structure (recommended)"
     - label: "No, leave them"
       description: "Keep files in current location"
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
   ├── skills/                      # Custom skill overrides (optional)
   └── commands/                    # Custom command overrides (optional)
   ```

7. **Create `manifest.json`** (v3.1.0 schema):
   ```json
   {
     "format_version": "3.1.0",
     "created_at": "[ISO timestamp]",
     "updated_at": "[ISO timestamp]",
     "created_by": {
       "blueprint_plugin": "3.1.0"
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
       "has_modular_rules": "[based on user choice]",
       "has_feature_tracker": "[based on user choice]",
       "has_document_detection": "[based on user choice]",
       "claude_md_mode": "[single|modular|both]"
     },
     "feature_tracker": {
       "file": "feature-tracker.json",
       "source_document": "[user selection]",
       "sync_targets": ["TODO.md"]
     },
     "generated": {
       "rules": {},
       "commands": {}
     },
     "custom_overrides": {
       "skills": [],
       "commands": []
     }
   }
   ```

   Note: Include `feature_tracker` section only if feature tracking is enabled.
   Note: As of v3.1.0, progress tracking is consolidated into feature-tracker.json (work-overview.md removed).

8. **Create initial rules** (if modular rules selected):
   - `development.md`: TDD workflow, commit conventions
   - `testing.md`: Test requirements, coverage expectations
   - `document-management.md`: Document organization rules (if document detection enabled)

9. **Handle `.gitignore`**:
   - Always commit `CLAUDE.md` and `.claude/rules/` (shared project instructions)
   - Add `docs/blueprint/work-orders/` to `.gitignore` (task-specific, may contain sensitive details)
   - If secrets detected in `.claude/`, warn user and suggest `.gitignore` entries

10. **Report**:
   ```
   Blueprint Development initialized! (v3.1.0)

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
   - .claude/commands/    (custom command overrides)

   Configuration:
   - Rules mode: [single|modular|both]
   [- Feature tracking: enabled (source: {source_document})]
   [- Document detection: enabled (Claude will prompt for PRD/ADR/PRP creation)]

   [Migrated documentation:]
   [- {original} → {destination} (for each migrated file)]

   Architecture:
   - Plugin layer: Generic commands from blueprint-plugin (auto-updated)
   - Generated layer: Rules/commands regeneratable from docs/prds/
   - Custom layer: Your overrides in .claude/skills/ and .claude/commands/
   ```

11. **Prompt for next action** (use AskUserQuestion):
    ```
    question: "Blueprint initialized. What would you like to do next?"
    options:
      - label: "Create a PRD"
        description: "Write requirements for a feature (recommended first step)"
      - label: "Generate project commands"
        description: "Detect project type and create /project:continue, /project:test-loop"
      - label: "Add modular rules"
        description: "Create .claude/rules/ for domain-specific guidelines"
      - label: "I'm done for now"
        description: "Exit - you can run /blueprint:status anytime to see options"
    ```

    **Based on selection:**
    - "Create a PRD" → Run `/blueprint:derive-prd`
    - "Generate project commands" → Run `/blueprint:generate-commands`
    - "Add modular rules" → Run `/blueprint:rules`
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
- /blueprint:generate-skills - Generate skills from PRDs
- /blueprint:generate-commands - Create workflow commands
- /blueprint:sync            - Check for stale generated content
- /blueprint:promote         - Move generated content to custom layer
- /blueprint:rules           - Manage modular rules
- /blueprint:claude-md       - Update CLAUDE.md
- /blueprint:feature-tracker-status  - View feature completion stats
- /blueprint:feature-tracker-sync    - Sync tracker with project files
```
