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

   Every consumer of the manifest degrades gracefully on bad input, which is
   correct at runtime but makes a **typo indistinguishable from an intentional
   omission** — `autonomy_levle: 3` reads as level 0, `adr_dris: [...]` reads as
   unconfigured, and nothing says a word. Status is the read-only diagnostic
   that already parses the whole manifest, so the schema check belongs here:

   ```bash
   uv run --quiet --script "${CLAUDE_SKILL_DIR}/../../scripts/check-manifest-schema.py" --project-dir "$(pwd)"
   ```

   It validates against
   [`blueprint-plugin/schemas/manifest.schema.json`](../../schemas/manifest.schema.json)
   and emits the structured `STATUS=` / `ISSUE_COUNT=` convention. Blocks with a
   fixed key set (`automation`, `validation`, `structure`, `project`,
   `workspaces`, `id_registry`, and the root) are closed, so an unknown key is an
   error naming the typo and its JSON pointer; `task_registry`,
   `custom_overrides`, and the `generated` / `documents` / `github_issues` maps
   stay open because their keys are user or registry data.

   Read the emitted keys:

   | Key | Meaning |
   |-----|---------|
   | `STATUS=OK` | Manifest matches the schema (or there is nothing to validate) |
   | `STATUS=ERROR` + `schema_violation` issues | Each issue names an `AT=<json-pointer>` and the offending key — surface all of them in the Step 5 report |
   | `STATUS=WARN` + `format_version_below_schema` | The manifest predates the schema's format version; recommend `/blueprint:upgrade` rather than reporting schema findings |
   | `SOURCE=…:no_validator` | Neither `uv` nor an installed `jsonschema` is available — the check is skipped, not failed. Say so instead of claiming the manifest is clean |

2b. **Validate the feature tracker against its schema** (if one exists):

   `schemas/feature-tracker.schema.json` describes the tracker's shape, but
   until the schema reconciliation nothing applied it — the file was consulted
   by humans and by `get-validation-config.sh`'s enum read, and no run ever
   validated a tracker against it. The same engine as Step 2a does both:

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
   ```
   Blueprint Status

   Version: v{format_version} {upgrade_indicator}
   Initialized: {created_at}
   Last Updated: {updated_at}

   Project Configuration:
   - Name: {project.name}
   - Type: {project.type}
   - Stack: {project.detected_stack}
   - Rules Mode: {structure.claude_md_mode}

   Project Documentation (docs/):
   - PRDs: {count} in docs/prds/
   - ADRs: {count} in docs/adrs/
     - With domain tags: {count}/{total} ({percent}%)
     - With relationships: {count}
     - Status: {accepted} Accepted, {superseded} Superseded, {deprecated} Deprecated
   - PRPs: {count} in docs/prps/

   Work Orders (docs/blueprint/work-orders/):
   - Pending: {count}
   - Completed: {count}
   - Archived: {count}

   Three-Layer Architecture:

   Layer 1: Plugin (blueprint-plugin)
   - Commands: /blueprint:* (auto-updated with plugin)
   - Skills: blueprint-development, blueprint-migration, confidence-scoring
   - Agents: requirements-documentation, architecture-decisions, prp-preparation

   Layer 2: Generated ({structure.generated_rules_path or .claude/rules/})
   - Path: {structure.generated_rules_path} (default: .claude/rules/)
   - Rules: {count} ({status_summary})
     {list each with status indicator: ✅ current, ⚠️ modified, 🔄 stale}

   Layer 3: Custom (.claude/skills/, .claude/commands/)
   - Skills: {count} (user-maintained)
   - Commands: {count} (user-maintained)

   {If feature_tracker enabled:}
   Feature Tracker:
   - Status: Enabled
   - Source: {feature_tracker.source_document}
   - Progress: {statistics.complete}/{statistics.total_features} ({statistics.completion_percentage}%)
   - Last Sync: {last_updated}
   - Phases: {count in_progress} active, {count complete} complete

   {If workspaces.role == "root":}
   Monorepo Portfolio ({workspaces.children|length} workspaces, scanned {last_scanned_at}):
   | Workspace | Format | Progress | Phase |
   |-----------|--------|----------|-------|
   {for each child:}
   | {child.path} | v{child.manifest_format_version} | {child.cached_stats.complete}/{child.cached_stats.total} ({child.cached_stats.completion_percentage}%) | {child.cached_stats.current_phase or "—"} |

   {If workspaces.role == "child":}
   Workspace: child of blueprint at {workspaces.root_relative_path}

   {If task_registry exists:}
   Task Health:
   - derive-plans        last: {age}  schedule: {schedule}  status: {status}
   - derive-rules        last: {age}  schedule: {schedule}  status: {status}
   - generate-rules      last: {age}  schedule: {schedule}  status: {status}
   - adr-validate        last: {age}  schedule: {schedule}  status: {status}
   - feature-tracker-sync last: {age}  schedule: {schedule}  status: {status}
   - sync-ids            last: {age}  schedule: {schedule}  status: {status}
   - claude-md           last: {age}  schedule: {schedule}  status: {status}
   - curate-docs         disabled

   Traceability (ID Registry):
   - Total documents: {count} ({x} PRDs, {y} ADRs, {z} PRPs, {w} WOs)
   - With IDs: {count}/{total} ({percent}%)
   - Linked to GitHub: {count}/{total} ({percent}%)
   - Orphan documents: {count} (docs without GitHub issues)
   - Orphan issues: {count} (issues without linked docs)
   - Broken links: {count}

   {If orphans exist:}
   Orphan Documents (no GitHub issues):
   - {PRD-001}: {title}
   - {PRP-003}: {title}

   Orphan GitHub Issues (no linked docs):
   - #{N}: {title}
   - #{M}: {title}

   {If Step 2a reported schema_violation issues:}
   Manifest schema: {N} violation(s) in docs/blueprint/manifest.json
   - {AT=/automation}: {Additional properties are not allowed ('autonomy_levle' was unexpected)}
      A misspelled key reads as unconfigured — the consumer silently uses its default.

   {If Step 2a reported SOURCE=…:no_validator:}
   Manifest schema: not checked (no uv / jsonschema available)

   Structure:
   ✅ docs/blueprint/manifest.json
   {✅|❌} docs/prds/
   {✅|❌} docs/adrs/
   {✅|❌} docs/prps/
   {✅|❌} docs/blueprint/work-orders/
   {✅|❌} docs/blueprint/feature-tracker.json
   {✅|❌} .claude/rules/
   {✅|❌} CLAUDE.md

   {If upgrade available:}
   Upgrade available: v{current} → v{latest}
      Run `/blueprint:upgrade` to upgrade.

   {If modified generated content:}
   Modified content detected: {count} files
      Run `/blueprint:sync` to review changes.
      Run `/blueprint:promote [name]` to move to custom layer.

   {If stale generated content:}
   Stale content detected: {count} files (PRDs changed since generation)
      Run `/blueprint:generate-skills` to regenerate.

   {If up to date:}
   Blueprint is up to date.
   ```

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

   ```
   question: "What would you like to do?"
   options:
     # Dynamic - include based on state detected above
     - label: "Upgrade to v{latest}" (if upgrade available)
       description: "Upgrade blueprint format to latest version"
     - label: "Sync generated content" (if modified)
       description: "Review changes to generated skills/commands"
     - label: "Regenerate from PRDs" (if stale)
       description: "Update generated content from changed PRDs"
     - label: "Generate rules from PRDs" (if PRDs exist, no rules)
       description: "Extract project-specific rules from your PRDs"
     - label: "Update CLAUDE.md" (if stale or missing)
       description: "Regenerate project overview document"
     - label: "Sync feature tracker" (if feature tracker stale)
       description: "Synchronize tracker with TODO.md"
     - label: "Validate ADRs" (if ADR issues detected)
       description: "Check ADR relationships, conflicts, and missing links"
     - label: "Sync document IDs" (if documents without IDs)
       description: "Assign IDs to all documents missing them"
     - label: "Link documents to GitHub" (if orphans exist)
       description: "Create/link GitHub issues for orphan documents"
     - label: "Run overdue tasks ({N} due)" (if overdue tasks exist)
       description: "Execute overdue maintenance tasks"
     # Always include these:
     - label: "Continue development"
       description: "Run /project:continue to work on next task"
     - label: "I'm done for now"
       description: "Exit status check"
   ```

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

**Example Output**:
```
Blueprint Status

Version: v3.0.0
Initialized: 2024-01-10T09:00:00Z
Last Updated: 2024-01-15T14:30:00Z

Project Configuration:
- Name: my-awesome-project
- Type: team
- Stack: typescript, bun, react
- Rules Mode: modular

Project Documentation (docs/):
- PRDs: 3 in docs/prds/
- ADRs: 5 in docs/adrs/
  - With domain tags: 4/5 (80%)
  - With relationships: 2
  - Status: 3 Accepted, 2 Superseded
- PRPs: 2 in docs/prps/

Work Orders (docs/blueprint/work-orders/):
- Pending: 5
- Completed: 12
- Archived: 2

Three-Layer Architecture:

Layer 1: Plugin (blueprint-plugin)
- Commands: 13 /blueprint:* commands (auto-updated)
- Skills: 3 (blueprint-development, blueprint-migration, confidence-scoring)
- Agents: 3 (requirements-documentation, architecture-decisions, prp-preparation)

Layer 2: Generated (.claude/rules/blueprint/)
- Path: .claude/rules/blueprint/ (configured; default is .claude/rules/)
- Rules: 4 (3 current, 1 modified)
  - ✅ architecture-patterns.md (current)
  - ⚠️ testing-strategies.md (modified locally)
  - ✅ implementation-guides.md (current)
  - ✅ quality-standards.md (current)

Layer 3: Custom (.claude/skills/, .claude/commands/, .claude/rules/)
- Skills: 1 (my-custom-skill)
- Commands: 0
- Rules: 0 (user-maintained)

Feature Tracker:
- Status: Enabled
- Source: REQUIREMENTS.md
- Progress: 22/42 (52.4%)
- Last Sync: 2024-01-14
- Phases: 1 active, 2 complete

Task Health:
  derive-plans        last: 5d ago   schedule: weekly      status: due
  derive-rules        last: 3d ago   schedule: weekly      status: ok
  generate-rules      last: 1d ago   schedule: on-change   status: ok
  adr-validate        last: 4d ago   schedule: weekly      status: ok
  feature-tracker-sync last: 3d ago  schedule: daily       status: overdue
  sync-ids            last: 3d ago   schedule: on-change   status: ok
  claude-md           last: 2d ago   schedule: on-change   status: ok
  curate-docs         disabled

Traceability (ID Registry):
- Total documents: 22 (3 PRDs, 5 ADRs, 2 PRPs, 12 WOs)
- With IDs: 22/22 (100%)
- Linked to GitHub: 18/22 (82%)
- Orphan documents: 4 (PRD-002, ADR-0004, PRP-001, WO-008)
- Orphan issues: 2 (#23, #45)
- Broken links: 0

Structure:
✅ docs/blueprint/manifest.json
✅ docs/prds/
✅ docs/adrs/
✅ docs/prps/
✅ docs/blueprint/work-orders/
✅ docs/blueprint/feature-tracker.json
✅ .claude/rules/
✅ CLAUDE.md

Modified content detected: 1 file
   Run `/blueprint:sync` to review or `/blueprint:promote testing-strategies` to preserve.

Blueprint is up to date.
```
