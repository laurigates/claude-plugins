# blueprint-status — Status Report Template (Step 5)

The report Step 5 renders, and a filled-in example.

## Template

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

## Example output

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
