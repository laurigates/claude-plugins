---
created: 2025-12-16
modified: 2026-06-21
reviewed: 2026-06-21
description: Initialize Blueprint Development structure. Use when bootstrapping docs/blueprint/ with manifest, PRD/ADR/PRP directories, and feature tracking for the first time.
allowed-tools: Bash, Write, Read, AskUserQuestion, Glob
name: blueprint-init
---

Initialize Blueprint Development in this project.

## When to Use This Skill

| Use this skill when... | Use blueprint-upgrade instead when... |
|---|---|
| The project has no `docs/blueprint/manifest.json` yet | The project already has a manifest at an older format version |
| You're bootstrapping a new project's PRD/ADR/PRP directories | You're migrating v1.x→v2, v2→v3, or v3.x→v3.y |
| You want to enable feature tracking and decision detection from scratch | Use blueprint-derive-plans to populate PRDs/ADRs/PRPs after init |
| You're configuring task scheduling for the first time | Use blueprint-execute instead when you want auto-detection of next step |

## Steps

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

1a. **Detect monorepo context** (format_version 3.3.0+):
   - Walk upward from the current directory looking for an ancestor
     `docs/blueprint/manifest.json` (stop at the repo root or `$HOME`).
   - If an ancestor root manifest exists, this init is creating a **child**
     workspace. Capture the relative path from the child back to the root.
   - Additionally scan descendants (max depth 4, skipping `node_modules`,
     `.git`, `dist`, `build`, `target`, `.venv`) for existing
     `docs/blueprint/manifest.json`. If any are found, this init is creating a
     **root** that will own existing children.
   - Otherwise this is a **standalone** blueprint (no `workspaces` block written).

   ```
   Use AskUserQuestion (only when ancestor root detected):
   question: "Found a parent blueprint at {parent_path}. Register this as a child workspace?"
   options:
     - label: "Yes - register as child"
       description: "Writes workspaces.role=child + root_relative_path; root picks it up on next /blueprint:workspace-scan"
     - label: "No - treat as standalone"
       description: "No workspaces block written; this project is independent"
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

   **Before recommending migration, measure cross-reference density.** Migrating
   a doc into `docs/{prds,adrs,prps}/` rewrites its path, breaking every
   reference to it. For each candidate doc, grep the repo for references to its
   path **from outside `docs/`** (README, scripts, CI, `.rulesync/`) and inter-doc
   links:

   ```bash
   # Count references to each candidate doc path (skip the doc itself)
   for doc in $candidate_docs; do
     base=$(basename "$doc")
     refs=$(grep -rIl --exclude-dir=.git --exclude-dir=node_modules "$base" . | grep -v "^./$doc$" | wc -l | tr -d ' ')
     ext=$(grep -rIl --exclude-dir=.git --exclude-dir=node_modules --exclude-dir=docs "$base" . | wc -l | tr -d ' ')
     echo "$doc total=$refs outside_docs=$ext"
   done
   ```

   A doc whose path is **referenced outside `docs/`** (build scripts, CI, README,
   `.rulesync/`) is expensive to migrate — every reference must be rewritten,
   including build-critical files. Blueprint only needs the **empty**
   `docs/{prds,adrs,prps}/` for *future* derived docs, so "leave in place" is a
   safe default when migration is expensive.

   **If documentation files found** (e.g., REQUIREMENTS.md, ARCHITECTURE.md, DESIGN.md, docs in non-standard locations):

   - **Default to recommending migration** (`label: "Yes, migrate documents (Recommended)"`) **only when no candidate doc is referenced outside `docs/`**.
   - **When one or more candidate docs are referenced outside `docs/`**, DROP the "(Recommended)" marker from the migrate option and surface the reference count so the user judges the cost. Prefer steering toward "leave in place".

   ```
   Use AskUserQuestion:
   question: "Found existing documentation: {file_list}. {N} of these are referenced outside docs/ ({ref_summary}). Migrate to Blueprint-managed paths?"
   options:
     # When NO candidate is referenced outside docs/: keep "(Recommended)" on migrate.
     # When ANY candidate IS referenced outside docs/: drop "(Recommended)" and show counts.
     - label: "Yes, migrate documents"
       description: "Move docs into docs/prds/, docs/adrs/, docs/prps/ based on content type. Rewrites all {total_refs} references — including build-critical files when referenced outside docs/."
     - label: "No, leave them in place"
       description: "Blueprint creates new docs under docs/{prds,adrs,prps}/; existing docs stay where build tooling and READMEs already point. Safe default when docs are referenced outside docs/."
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

4a. **Ask about generated-rules output path** (use AskUserQuestion):

   Only prompt when `.claude/rules/` already exists and contains files (i.e., hand-authored rules that pre-date blueprint). Skip silently in fresh repos and use the default.

   ```bash
   # Only prompt if .claude/rules/ has any content not created by blueprint
   find .claude/rules -maxdepth 1 -type f -name '*.md'
   ```

   ```
   Use AskUserQuestion (only when .claude/rules/ has existing content):
   question: "Detected existing content in .claude/rules/. Where should blueprint write generated rules?"
   options:
     - label: ".claude/rules/blueprint/ (Recommended)"
       description: "Isolated subdirectory — keeps blueprint-managed and hand-authored rules separate, prevents collisions on regenerate"
     - label: ".claude/rules/ (flat)"
       description: "Write generated rules alongside hand-authored ones; risk of overwrite when filenames collide"
   ```

   Store the chosen path in `structure.generated_rules_path` in the manifest (defaults to `.claude/rules/` when unset). This keeps `blueprint-generate-rules` and `blueprint-derive-rules` from clobbering hand-curated rule files (issue #1043).

5. **Ask about decision detection** (use AskUserQuestion):
   ```
   question: "Would you like to enable automatic decision detection?"
   options:
     - label: "Yes - Detect decisions worth documenting"
       description: "Claude will notice when conversations contain architecture decisions, feature requirements, or implementation plans that should be captured as ADR/PRD/PRP documents"
     - label: "No - Manual commands only"
       description: "Use /blueprint:derive-plans, /blueprint:prp-create explicitly when you want to create documents"
   ```

   Set `has_document_detection` in manifest based on response.

   **If enabled:**
   Resolve the rules output directory before writing — honour the path chosen in
   Step 4a (default `.claude/rules/`) rather than hardcoding it, so blueprint
   does not collide with rulesync-managed or hand-authored rules (issue #1675):

   ```bash
   RULES_DIR=$(jq -r '.structure.generated_rules_path // ".claude/rules/"' docs/blueprint/manifest.json)
   mkdir -p "$RULES_DIR"
   ```

   When the manifest is not yet written, use the Step 4a selection directly
   (default `.claude/rules/`).

   Copy `document-management-rule.md` template to `$RULES_DIR/document-management.md`.
   This rule instructs Claude to watch for:
   - Architecture decisions being made during discussion → prompt to create ADR
   - Feature requirements being discussed or refined → prompt to create/update PRD
   - Implementation plans being formulated → prompt to create PRP

6. **Create directory structure**:

   **Canonical document paths** are at the **top level** of `docs/`, not under `docs/blueprint/`. `docs/blueprint/` holds blueprint machinery only (manifest, feature-tracker, work-orders); `docs/{adrs,prds,prps,trps}/` hold the documents themselves. Every `/blueprint:derive-*` skill writes to the top-level paths — keeping them consistent prevents the dual-corpus bug where init creates one layout and derive-* writes to another.

   Execute the creation explicitly so the directories exist even when no document migration happened in Step 3:

   ```bash
   mkdir -p docs/blueprint/work-orders/completed
   mkdir -p docs/blueprint/work-orders/archived
   mkdir -p docs/adrs
   mkdir -p docs/prds
   mkdir -p docs/prps
   ```

   Note: `docs/trps/` is created on-demand by `/blueprint:derive-tests` only — init does not pre-create it.

   The resulting tree:
   ```
   docs/
   ├── blueprint/
   │   ├── manifest.json            # Version tracking and configuration
   │   ├── feature-tracker.json     # Progress tracking (if enabled)
   │   ├── work-orders/             # Task packages for subagents
   │   │   ├── completed/
   │   │   └── archived/
   │   └── README.md                # Blueprint documentation
   ├── prds/                        # Product Requirements Documents (canonical)
   ├── adrs/                        # Architecture Decision Records (canonical)
   ├── prps/                        # Product Requirement Prompts (canonical)
   └── trps/                        # Test Regression Plans (created on-demand by /blueprint:derive-tests)
   ```

   **Claude configuration (in .claude/):** — initial rules are written under
   `structure.generated_rules_path` (default `.claude/rules/`; an isolated
   subdirectory like `.claude/rules/blueprint/` when Step 4a detected existing
   content), shown here at the default location:
   ```
   .claude/
   ├── rules/                       # $RULES_DIR — generated_rules_path (default .claude/rules/)
   │   ├── development.md           # Development workflow rules
   │   ├── testing.md               # Testing requirements
   │   └── document-management.md   # Document organization rules (if detection enabled)
   └── skills/                      # Custom skill overrides (optional)
   ```

7. **Create `manifest.json`** (v3.3.0 schema — canonical filename is `docs/blueprint/manifest.json`, no dot prefix):
   ```json
   {
     "format_version": "3.3.0",
     "created_at": "[ISO timestamp]",
     "updated_at": "[ISO timestamp]",
     "created_by": {
       "blueprint_plugin": "3.3.0"
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
       "has_modular_rules": true,
       "has_feature_tracker": "[based on user choice]",
       "has_document_detection": "[based on user choice]",
       "claude_md_mode": "both",
       "generated_rules_path": "[based on Step 4a; defaults to .claude/rules/ when prompt skipped]"
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

   **Monorepo `workspaces` block (v3.3.0+)**, appended to the manifest based on the
   detection from Step 1a:

   - **Child** (ancestor blueprint found and user opted in):
     ```json
     "workspaces": {
       "role": "child",
       "root_relative_path": "[relative path from this dir to the root]"
     }
     ```
   - **Root** (descendant blueprints found):
     ```json
     "workspaces": {
       "role": "root",
       "discovery_strategy": "auto-cache",
       "last_scanned_at": null,
       "children": []
     }
     ```
     After writing the manifest, run `/blueprint:workspace-scan` once to
     populate `children[]`.
   - **Standalone**: omit the `workspaces` block entirely.

8. **Create initial rules** under the resolved `$RULES_DIR` (the Step 4a
   `generated_rules_path`, default `.claude/rules/`) — never a hardcoded
   `.claude/rules/` — so they sit alongside, not on top of, rulesync-managed or
   hand-authored rules (issue #1675):

   ```bash
   RULES_DIR=$(jq -r '.structure.generated_rules_path // ".claude/rules/"' docs/blueprint/manifest.json)
   mkdir -p "$RULES_DIR"
   ```

   - `$RULES_DIR/development.md`: TDD workflow, commit conventions
   - `$RULES_DIR/testing.md`: Test requirements, coverage expectations
   - `$RULES_DIR/document-management.md`: Document organization rules (if decision detection enabled)

9. **Handle `.gitignore`**:
   - Always commit `CLAUDE.md` and `.claude/rules/` (shared project instructions)
   - Add `docs/blueprint/work-orders/` to `.gitignore` (task-specific, may contain sensitive details)
   - If secrets detected in `.claude/`, warn user and suggest `.gitignore` entries

10. **Report**:
   ```
   Blueprint Development initialized! (v3.3.0)

   Blueprint structure created:
   - docs/blueprint/manifest.json
   - docs/blueprint/work-orders/
   - docs/blueprint/README.md
   [- docs/blueprint/feature-tracker.json (if feature tracking enabled)]

   Project documentation (top-level — derive-* skills write here):
   - docs/prds/           (Product Requirements Documents)
   - docs/adrs/           (Architecture Decision Records)
   - docs/prps/           (Product Requirement Prompts)
   - docs/trps/           (Test Regression Plans — created on first /blueprint:derive-tests run)

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
- /blueprint:derive-plans    - Derive PRDs, ADRs, and PRPs from git history
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
