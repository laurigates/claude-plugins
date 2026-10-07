---
created: 2025-12-16
modified: 2026-08-09
reviewed: 2026-08-09
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
     Ask with the Step 1 prompt in [references/prompts.md](references/prompts.md) (upgrade → `/blueprint:upgrade`, reinitialize → step 2, cancel → exit).

1a. **Detect monorepo context** (format_version 3.3.0+):
   - Ancestor manifest found → **child**; descendant manifests found → **root**; neither → **standalone** (no `workspaces` block). Walk/scan rules are in [references/monorepo-workspaces.md](references/monorepo-workspaces.md).

   When an ancestor root is detected, ask whether to register as a child workspace using the prompt in [references/monorepo-workspaces.md](references/monorepo-workspaces.md).

2. **Ask about feature tracking** (use AskUserQuestion):
   Ask with the Step 2 prompt in [references/prompts.md](references/prompts.md).

   **If "Yes" selected:**
   a. Search for markdown files in the project that contain requirements, features, or user stories
   b. Auto-detect the most likely source document based on content analysis
   c. Create `docs/blueprint/feature-tracker.json` from template using the detected source
   d. Set `has_feature_tracker: true` in manifest

3. **Ask about document migration** (use AskUserQuestion):
   Search for existing markdown documentation files across the project (excluding standard files like README.md, CHANGELOG.md, CONTRIBUTING.md, LICENSE.md, CODE_OF_CONDUCT.md, SECURITY.md).

   The find command is in [references/document-migration.md](references/document-migration.md).

   **Before recommending migration, measure cross-reference density.** Migrating
   a doc into `docs/{prds,adrs,prps}/` rewrites its path, breaking every
   reference to it. For each candidate doc, grep the repo for references to its
   path **from outside `docs/`** (README, scripts, CI, `.rulesync/`) and inter-doc
   links:

   Run the per-doc reference-count loop in [references/document-migration.md](references/document-migration.md).

   A doc whose path is **referenced outside `docs/`** (build scripts, CI, README,
   `.rulesync/`) is expensive to migrate — every reference must be rewritten,
   including build-critical files. Blueprint only needs the **empty**
   `docs/{prds,adrs,prps}/` for *future* derived docs, so "leave in place" is a
   safe default when migration is expensive.

   **If documentation files found** (e.g., REQUIREMENTS.md, ARCHITECTURE.md, DESIGN.md, docs in non-standard locations):

   - **Default to recommending migration** (`label: "Yes, migrate documents (Recommended)"`) **only when no candidate doc is referenced outside `docs/`**.
   - **When one or more candidate docs are referenced outside `docs/`**, DROP the "(Recommended)" marker from the migrate option and surface the reference count so the user judges the cost. Prefer steering toward "leave in place".

   Ask with the migration prompt in [references/document-migration.md](references/document-migration.md).

   **If "Yes" selected:** classify, move, rename, and report each doc per [references/document-migration.md](references/document-migration.md).

   **If no documentation files found:** Skip this step silently.

4. **Ask about maintenance task scheduling** (use AskUserQuestion):
   Ask with the Step 4 prompt in [references/prompts.md](references/prompts.md) (Prompt / Auto-run safe / Fully automatic / Manual only).

   Store selection for task_registry defaults:
   - **Prompt**: all `auto_run: false`, default schedules
   - **Auto-run safe**: read-only tasks (`adr-validate`, `feature-tracker-sync`, `sync-ids`) get `auto_run: true`; write tasks get `false`
   - **Fully automatic**: all tasks get `auto_run: true`, default schedules
   - **Manual only**: all `auto_run: false`, all schedules set to `on-demand`

   The same selection sets `automation.autonomy_level` (the ADR-0020 level
   model — what actually *executes* the auto_run contract):
   - **Prompt** / **Manual only** → `autonomy_level: 0` (nothing runs unattended)
   - **Auto-run safe** → `autonomy_level: 1` (deterministic due tasks run via
     the SessionStart probe; due agent tasks surface as drift findings)
   - **Fully automatic** → `autonomy_level: 2` (quiet autopilot also runs due
     agent tasks in-session; `interaction_mode` defaults to `quiet`)

4a. **Ask about generated-rules output path** (use AskUserQuestion):

   Only prompt when `.claude/rules/` already exists and contains files (i.e., hand-authored rules that pre-date blueprint). Skip silently in fresh repos and use the default.

   Detect existing content and ask with the Step 4a prompt in [references/prompts.md](references/prompts.md).

   Store the chosen path in `structure.generated_rules_path` in the manifest (defaults to `.claude/rules/` when unset). This keeps `blueprint-generate-rules` and `blueprint-derive-rules` from clobbering hand-curated rule files (issue #1043).

5. **Ask about decision detection** (use AskUserQuestion):
   Ask with the Step 5 prompt in [references/prompts.md](references/prompts.md).

   Set `has_document_detection` in manifest based on response.

   **If enabled:** resolve `$RULES_DIR` and copy the document-management rule per [references/rules-setup.md](references/rules-setup.md).

6. **Create directory structure**:

   Execute the creation explicitly so the directories exist even when no document migration happened in Step 3:

   ```bash
   mkdir -p docs/blueprint/work-orders/completed
   mkdir -p docs/blueprint/work-orders/archived
   mkdir -p docs/adrs
   mkdir -p docs/prds
   mkdir -p docs/prps
   ```

   Documents live at top-level `docs/`, not `docs/blueprint/` — why, plus the resulting trees: [references/directory-layout.md](references/directory-layout.md).

7. **Create `manifest.json`** (v3.4.0 schema — canonical filename is `docs/blueprint/manifest.json`, no dot prefix):
   Write the template in [references/manifest-template.md](references/manifest-template.md), filling each `[...]` placeholder from the answers above.

   Note: Include `feature_tracker` section only if feature tracking is enabled.

   For a monorepo child or root (Step 1a), append the `workspaces` block from [references/monorepo-workspaces.md](references/monorepo-workspaces.md); a standalone blueprint omits it.

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

8a. **Register the rules just written in `generated.rules`** — this step is not
   optional. `/blueprint:sync` and the SessionStart drift probe detect staleness
   by comparing a **registered** record's `content_hash` against the file on
   disk, so a rule written here but never registered is invisible to both: a
   local edit is undetectable, a revised template never propagates, and sync
   reports clean over a set it cannot see. Nothing surfaces as an error
   (issue #2331).

   Register every rule Step 8 actually wrote — pass only the filenames that
   exist (`document-management.md` only when decision detection was enabled in
   Step 5):

   ```bash
   bash "${CLAUDE_SKILL_DIR}/../../scripts/register-generated-rules.sh" \
     --source "blueprint-init" \
     --plugin-version "3.4.0" \
     development.md testing.md document-management.md
   ```

   Check `REGISTERED=` and `STATUS=OK` in the script's output before continuing. The record shape and manifest key form are in [references/rules-setup.md](references/rules-setup.md).

9. **Handle `.gitignore`**:
   - Always commit `CLAUDE.md` and `.claude/rules/` (shared project instructions)
   - Add `docs/blueprint/work-orders/` to `.gitignore` (task-specific, may contain sensitive details)
   - If secrets detected in `.claude/`, warn user and suggest `.gitignore` entries

10. **Report**:
    Print the initialization report in [references/report-templates.md](references/report-templates.md).

11. **Prompt for next action** (use AskUserQuestion):
    Ask with the Step 11 prompt in [references/prompts.md](references/prompts.md).

    **Based on selection:**
    - "Derive plans from git history" → Run `/blueprint:derive-plans`
    - "Derive rules from codebase" → Run `/blueprint:derive-rules`
    - "Update CLAUDE.md" → Run `/blueprint:claude-md`
    - "I'm done for now" → Show quick reference and exit

Show the Quick Reference command list in [references/report-templates.md](references/report-templates.md) when the user selects "I'm done for now".
