---
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
       - "Check for upgrades" → run /blueprint-upgrade
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

4. **Create directory structure**:
   ```
   .claude/
   ├── blueprints/
   │   ├── .manifest.json          # Version tracking (NEW)
   │   ├── prds/                   # Product Requirements Documents
   │   ├── work-orders/            # Task packages for subagents
   │   │   ├── completed/          # Completed work-orders
   │   │   └── archived/           # Obsolete work-orders
   │   └── templates/              # Custom templates (optional)
   └── rules/                      # Modular rules (if selected)
       ├── development.md          # Development workflow rules
       └── testing.md              # Testing requirements
   ```

5. **Create `.manifest.json`**:
   ```json
   {
     "format_version": "1.1.0",
     "created_at": "[ISO timestamp]",
     "updated_at": "[ISO timestamp]",
     "created_by": {
       "blueprint_plugin": "1.0.0"
     },
     "project": {
       "name": "[detected or asked]",
       "type": "[personal|team|opensource]"
     },
     "structure": {
       "has_prds": true,
       "has_work_orders": true,
       "has_ai_docs": false,
       "has_templates": false,
       "has_modular_rules": "[based on user choice]",
       "claude_md_mode": "[single|modular|both]"
     },
     "generated_artifacts": {
       "commands": [],
       "skills": [],
       "rules": []
     }
   }
   ```

6. **Create `work-overview.md`**:
   ```markdown
   # Work Overview: [Project Name]

   ## Current Phase: [Phase name - e.g., "Planning", "Phase 1", "MVP"]

   ### Completed
   - ✅ [Completed task 1]

   ### In Progress
   - ⏳ [Current task]

   ### Pending
   - ⏹️ [Pending task 1]
   - ⏹️ [Pending task 2]

   ## Next Steps
   1. [Next step 1]
   2. [Next step 2]
   ```

7. **Create initial rules** (if modular rules selected):
   - `development.md`: TDD workflow, commit conventions
   - `testing.md`: Test requirements, coverage expectations

8. **Handle `.gitignore`** based on project type:
   - Personal: Add `.claude/` to `.gitignore`
   - Team: Commit `.claude/` (ask about secrets)
   - Open source: Commit `.claude/rules/`, gitignore `.claude/blueprints/work-orders/`

9. **Report**:
   ```
   ✅ Blueprint Development initialized! (v1.1.0)

   Created:
   - .claude/blueprints/.manifest.json (version tracking)
   - .claude/blueprints/prds/
   - .claude/blueprints/work-orders/
   - .claude/blueprints/work-overview.md
   [- .claude/rules/ (if modular rules enabled)]

   Configuration:
   - Project type: [personal|team|opensource]
   - Rules mode: [single|modular|both]

   Next steps:
   1. Write PRDs in `.claude/blueprints/prds/`
   2. Run `/blueprint-generate-skills` to create project-specific skills
   3. Run `/blueprint-generate-commands` to create workflow commands
   4. Run `/blueprint-rules` to add domain-specific rules
   5. Start development with `/project:continue`

   Management commands:
   - `/blueprint-status` - Check version and configuration
   - `/blueprint-upgrade` - Upgrade to latest format
   - `/blueprint-rules` - Manage modular rules
   - `/blueprint-claude-md` - Update CLAUDE.md
   ```
