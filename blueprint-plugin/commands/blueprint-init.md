---
description: "Initialize Blueprint Development structure in current project"
allowed_tools: [Bash, Write, Read]
---

Initialize Blueprint Development in this project.

**Steps**:

1. **Check if already initialized**:
   - Look for `.claude/blueprints/` directory
   - If exists, report and ask if user wants to reinitialize

2. **Create directory structure**:
   ```
   .claude/blueprints/
   ├── prds/                     # Product Requirements Documents
   ├── work-orders/              # Task packages for subagents
   │   ├── completed/            # Completed work-orders
   │   └── archived/             # Obsolete work-orders
   └── templates/                # Custom templates (optional)
   ```

3. **Create `work-overview.md`**:
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

4. **Ask about `.gitignore`**:
   - Ask user if they want to add `.claude/` to `.gitignore`
   - If personal project → recommend `.gitignore`
   - If team project → recommend committing `.claude/` for sharing

5. **Report**:
   ```
   ✅ Blueprint Development initialized!

   Created:
   - .claude/blueprints/prds/
   - .claude/blueprints/work-orders/
   - .claude/blueprints/work-overview.md

   Next steps:
   1. Write PRDs in `.claude/blueprints/prds/`
   2. Run `/blueprint:generate-skills` to create project-specific skills
   3. Run `/blueprint:generate-commands` to create workflow commands
   4. Start development with `/project:continue`

   See `.claude/docs/blueprint-development/` for complete documentation.
   ```
