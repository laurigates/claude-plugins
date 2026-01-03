---
created: 2025-12-16
modified: 2025-12-22
reviewed: 2025-12-22
description: "Initialize Blueprint Development structure in current project"
allowed_tools: [Bash, Write, Read, AskUserQuestion]
---

Initialize Blueprint Development in this project.

**Steps**:

1. **Check if already initialized**:
   - Look for `.claude/blueprints/.manifest.json`
   - If exists, read version and ask user:
     ```
     Use AskUserQuestion:
     question: "Blueprint already initialized (v{version}). What would you like to do?"
     options:
       - "Check for upgrades" → run /blueprint:upgrade
       - "Reinitialize (will reset manifest)" → continue with step 2
       - "Cancel" → exit
     ```

2. **Gather project context** (use AskUserQuestion):
   ```
   question: "What type of project is this?"
   options:
     - "Personal/Solo project" → recommend .gitignore for .claude/
     - "Team project" → recommend committing .claude/ for sharing
     - "Open source" → recommend .claude/rules/ for contributor guidelines
   ```

3. **Ask about modular rules**:
   ```
   question: "How would you like to organize project instructions?"
   options:
     - "Single CLAUDE.md file" → traditional approach
     - "Modular rules (.claude/rules/)" → create rules directory structure
     - "Both" → CLAUDE.md for overview, rules/ for specifics
   allowMultiSelect: false
   ```

4. **Ask about feature tracking** (use AskUserQuestion):
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
   b. Create `.claude/blueprints/feature-tracker.json` from template
   c. Set `has_feature_tracker: true` in manifest

5. **Create directory structure**:

   **Project documentation (in docs/):**
   ```
   docs/
   ├── prds/                        # Product Requirements Documents
   ├── adrs/                        # Architecture Decision Records
   └── prps/                        # Product Requirement Prompts
   ```

   **Claude configuration (in .claude/):**
   ```
   .claude/
   ├── blueprints/
   │   ├── .manifest.json           # Version tracking
   │   ├── work-orders/             # Task packages for subagents
   │   │   ├── completed/
   │   │   └── archived/
   │   ├── ai_docs/                 # Curated documentation (on-demand)
   │   │   ├── libraries/
   │   │   └── project/
   │   ├── generated/               # Auto-generated content (regeneratable)
   │   │   ├── skills/              # Skills from PRDs
   │   │   └── commands/            # Commands from project detection
   │   └── work-overview.md         # Progress tracking
   ├── skills/                      # Custom skill overrides (optional)
   └── commands/                    # Custom command overrides (optional)
   ```

   **With modular rules (if selected):**
   ```
   .claude/
   └── rules/                       # Modular rules
       ├── development.md           # Development workflow rules
       └── testing.md               # Testing requirements
   ```

6. **Create `.manifest.json`** (v2.0.0 schema):
   ```json
   {
     "format_version": "2.0.0",
     "created_at": "[ISO timestamp]",
     "updated_at": "[ISO timestamp]",
     "created_by": {
       "blueprint_plugin": "2.0.0"
     },
     "project": {
       "name": "[detected or asked]",
       "type": "[personal|team|opensource]",
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
       "claude_md_mode": "[single|modular|both]"
     },
     "feature_tracker": {
       "file": "feature-tracker.json",
       "source_document": "[user selection]",
       "sync_targets": ["work-overview.md", "TODO.md"]
     },
     "generated": {
       "skills": {},
       "commands": {}
     },
     "custom_overrides": {
       "skills": [],
       "commands": []
     }
   }
   ```

   Note: Include `feature_tracker` section only if feature tracking is enabled.

7. **Create `work-overview.md`**:
   ```markdown
   # Work Overview: [Project Name]

   ## Current Phase: [Phase name - e.g., "Planning", "Phase 1", "MVP"]

   ### Completed
   - (none yet)

   ### In Progress
   - (none yet)

   ### Pending
   - (none yet)

   ## Next Steps
   1. Create a PRD to define project requirements
   2. Generate project-specific skills from PRDs
   3. Generate workflow commands for your stack
   ```

8. **Create initial rules** (if modular rules selected):
   - `development.md`: TDD workflow, commit conventions
   - `testing.md`: Test requirements, coverage expectations

9. **Handle `.gitignore`** based on project type:
   - Personal: Add `.claude/` to `.gitignore`
   - Team: Commit `.claude/` (ask about secrets)
   - Open source: Commit `docs/`, `.claude/rules/`, gitignore `.claude/blueprints/work-orders/`

10. **Report**:
   ```
   Blueprint Development initialized! (v2.0.0)

   Project documentation created:
   - docs/prds/           (Product Requirements Documents)
   - docs/adrs/           (Architecture Decision Records)
   - docs/prps/           (Product Requirement Prompts)

   Claude configuration created:
   - .claude/blueprints/.manifest.json
   - .claude/blueprints/work-orders/
   - .claude/blueprints/ai_docs/
   - .claude/blueprints/generated/
   - .claude/blueprints/work-overview.md
   [- .claude/rules/ (if modular rules enabled)]
   [- .claude/blueprints/feature-tracker.json (if feature tracking enabled)]

   Configuration:
   - Project type: [personal|team|opensource]
   - Rules mode: [single|modular|both]
   [- Feature tracking: enabled (source: {source_document})]

   Architecture:
   - Plugin layer: Generic commands from blueprint-plugin (auto-updated)
   - Generated layer: Skills/commands regeneratable from docs/prds/
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
    - "Create a PRD" → Run `/blueprint:prd`
    - "Generate project commands" → Run `/blueprint:generate-commands`
    - "Add modular rules" → Run `/blueprint:rules`
    - "I'm done for now" → Show quick reference and exit

**Quick Reference** (show if user selects "I'm done for now"):
```
Management commands:
- /blueprint:status          - Check version and configuration
- /blueprint:upgrade         - Upgrade to latest format version
- /blueprint:prd             - Create a Product Requirements Document
- /blueprint:adr             - Create an Architecture Decision Record
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
