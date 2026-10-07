---
created: 2025-12-17
modified: 2026-07-27
reviewed: 2026-07-27
description: Show blueprint version, config, PRD/ADR/PRP counts, and feature tracker progress. Use when auditing traceability, orphan docs, or stale generated content.
args: "[--report-only]"
argument-hint: "--report-only to display status without interactive prompts"
allowed-tools: Read, Bash, Glob, AskUserQuestion
model: sonnet
name: blueprint-status
---

Display the current blueprint configuration status with three-layer architecture breakdown.

## When to Use This Skill

| Use this skill when... | Use blueprint-execute instead when... |
|---|---|
| You want a read-only status report (PRD/ADR/PRP counts, traceability) | You want auto-detection that takes the next action, not just reports |
| You want the three-layer architecture breakdown | Use blueprint-feature-tracker-status instead for FR/phase progress |
| You want to audit orphan docs and stale generated content | Use blueprint-sync instead for an actionable drift reconcile |
| You run with `--report-only` for non-interactive auditing | Use blueprint-upgrade instead when you've already spotted an upgrade |

## Flags

| Flag | Description |
|------|-------------|
| `--report-only` | Display status report and exit without prompting for next action |

## Steps

1. **Check if blueprint is initialized**:
   - Look for `docs/blueprint/manifest.json`
   - If not found, report:
     ```
     Blueprint not initialized in this project.
     Run `/blueprint:init` to get started.
     ```

2. **Read manifest and gather information**:
   - Parse `manifest.json` for version and configuration
   - Parse `id_registry` for traceability metrics
   - Count PRDs in `docs/prds/`
   - Count ADRs in `docs/adrs/`
   - Count PRPs in `docs/prps/`
   - For ADRs, also count:
     - With domain tags (`grep -l "^domain:" docs/adrs/*.md | wc -l`)
     - With relationship declarations (supersedes, extends, related)
     - By status (Accepted, Superseded, Deprecated)
   - Count work-orders (pending, completed, archived)
   - Resolve the configured rules path: `jq -r '.structure.generated_rules_path // ".claude/rules/"' docs/blueprint/manifest.json`
   - Count generated rules in the configured path (default `.claude/rules/`)
   - Count custom skills in `.claude/skills/`
   - Count custom commands in `.claude/commands/`
   - Check for `.claude/rules/` directory
   - Check for `CLAUDE.md` file
   - Check for `docs/blueprint/feature-tracker.json`
   - If feature tracker exists, read statistics and last_updated
   - Read `task_registry` from manifest (if present)
   - For each task, calculate schedule status:
     - `ok`: Not yet due based on schedule
     - `due`: Due for execution based on schedule
     - `overdue`: Past due by more than 1 schedule period (e.g., daily task not run in 2+ days)
     - `disabled`: `enabled: false`
     - `never`: `last_completed_at` is null (never tracked)

2a. **Validate the manifest against its schema** (issue #2136):

   Run the manifest schema check (background: [references/schema-validation.md](references/schema-validation.md)):

   ```bash
   uv run --quiet --script "${CLAUDE_SKILL_DIR}/../../scripts/check-manifest-schema.py" --project-dir "$(pwd)"
   ```

   Read the emitted keys:

   | Key | Meaning |
   |-----|---------|
   | `STATUS=OK` | Manifest matches the schema (or there is nothing to validate) |
   | `STATUS=ERROR` + `schema_violation` issues | Each issue names an `AT=<json-pointer>` and the offending key — surface all of them in the Step 5 report |
   | `STATUS=WARN` + `format_version_below_schema` | The manifest predates the schema's format version; recommend `/blueprint:upgrade` rather than reporting schema findings |
   | `SOURCE=…:no_validator` | Neither `uv` nor an installed `jsonschema` is available — the check is skipped, not failed. Say so instead of claiming the manifest is clean |

2b. **Validate the feature tracker against its schema** (if one exists):

   Run the tracker schema check (background: [references/schema-validation.md](references/schema-validation.md)):

   ```bash
   uv run --quiet --script "${CLAUDE_SKILL_DIR}/../../scripts/check-schema.py" --schema "${CLAUDE_SKILL_DIR}/../../schemas/feature-tracker.schema.json" --json-file docs/blueprint/feature-tracker.json
   ```

   Same output contract as Step 2a. A missing tracker is `STATUS=OK` — most
   repos have none, and a check that errors on an absent optional file gets
   turned off.

   This covers the tracker's **shape**. `blueprint-tracker-check.sh` (run by
   `/blueprint:feature-tracker-sync` and `-status`) covers what a schema cannot
   express: the `statistics` block agreeing with the features collection it
   caches, `tasks.*[]` membership, and FR ids cited in `docs/**` but never
   minted. Run both; neither subsumes the other.

3. **Check for upgrade availability**:
   - Compare `format_version` in manifest with current plugin version
   - Current format version: **3.4.0**
   - If manifest version < current → upgrade available

3a. **Monorepo portfolio refresh (v3.3.0+)**:
   - If `workspaces.role == "root"`, invoke `/blueprint:workspace-scan` to
     refresh `workspaces.children` and cached stats before rendering. Skip if
     scanned within the last hour (`last_scanned_at`).
   - If `workspaces.role == "child"`, resolve `workspaces.root_relative_path`
     and mention the parent in the status report but do NOT trigger a scan.

4. **Check generated content status**:
   - For each generated rule in manifest:
     - Hash current file content
     - Compare with stored `content_hash`
     - Status: `current` (unchanged), `modified` (user edited), `stale` (source PRDs changed)

5. **Display status report**:
   Render the report from the template in [references/report-template.md](references/report-template.md).

6. **Additional checks**:
   - Report every `schema_violation` from Step 2a with its `AT=` pointer — a
     misspelled key is silently ignored by its consumer, so the schema check is
     the only place it surfaces
   - Warn if Step 2a reported `format_version_below_schema` (recommend `/blueprint:upgrade`)
   - Warn if any tasks are overdue (e.g., "3 maintenance tasks overdue - run `/blueprint:execute` to catch up")
   - Warn if feature-tracker.json is stale (> 1 day since last update)
   - Warn if PRDs exist but no generated rules
   - Warn if modular rules enabled but `.claude/rules/` is empty
   - Warn if generated content is modified or stale
   - Warn if feature-tracker.json is older than 7 days (needs sync)
   - Warn if TODO.md has been modified since last sync
   - Warn if ADRs have potential issues:
     - Multiple "Accepted" ADRs in same domain (potential conflict)
     - ADRs without domain tags (harder to detect conflicts)
     - Missing bidirectional links (e.g., supersedes without corresponding superseded-by)
   - **Traceability checks**:
     - Warn if documents exist without IDs (run `/blueprint:sync-ids`)
     - Warn if orphan documents exist (docs without GitHub issues)
     - Warn if orphan issues exist (GitHub issues without linked docs)
     - Warn if broken links detected (referenced docs/issues don't exist)

7. **If `--report-only`**: Output the status report from Steps 5-6 and exit. Skip the interactive prompt below.

8. **Prompt for next action** (use AskUserQuestion):

   **Build options dynamically based on state:**
   - If upgrade available → Include "Upgrade to v{latest}"
   - If modified content → Include "Sync generated content"
   - If stale content → Include "Regenerate skills"
   - If PRDs exist but no generated skills → Include "Generate skills from PRDs"
   - If skills exist but no commands → Include "Generate workflow commands"
   - If CLAUDE.md stale → Include "Update CLAUDE.md"
   - If feature tracker exists but stale → Include "Sync feature tracker"
   - If ADRs have potential issues → Include "Validate ADRs"
   - If documents without IDs → Include "Sync document IDs"
   - If orphan documents/issues → Include "Link documents to GitHub"
   - If overdue tasks exist → Include "Run overdue maintenance tasks"
   - Always include "Continue development" and "I'm done"

   Ask with the option list in [references/next-action-prompt.md](references/next-action-prompt.md).

   **Based on selection:**
   - "Upgrade" → Run `/blueprint:upgrade`
   - "Sync" → Run `/blueprint:sync`
   - "Regenerate" → Run `/blueprint:generate-rules`
   - "Generate rules" → Run `/blueprint:generate-rules`
   - "Update CLAUDE.md" → Run `/blueprint:claude-md`
   - "Sync feature tracker" → Run `/blueprint:feature-tracker-sync`
   - "Validate ADRs" → Run `/blueprint:adr-validate`
   - "Sync document IDs" → Run `/blueprint:sync-ids`
   - "Link documents to GitHub" → For each orphan, prompt to create/link issue
   - "Run overdue tasks" → Run `/blueprint:execute` for overdue tasks
   - "Continue development" → Run `/project:continue`
   - "I'm done" → Exit

A filled-in example report is in [references/report-template.md](references/report-template.md).
