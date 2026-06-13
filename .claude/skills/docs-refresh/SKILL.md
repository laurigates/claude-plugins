---
name: docs-refresh
description: Refresh plugin catalog docs (README, PLUGIN-MAP, d2 diagram) so per-plugin skill/agent counts match disk. Use when fixing count drift or after adding skills.
allowed-tools: Bash(bash scripts/check-docs-index.sh *), Bash(d2 *), Bash(git log *), Bash(git rev-parse *), Read, Edit, Grep, Glob, TodoWrite
argument-hint: (no args)
created: 2026-06-13
modified: 2026-06-13
reviewed: 2026-06-13
---

# /docs-refresh

Refresh this repo's top-level catalog docs so the stated plugin/skill/agent
counts and the plugin set match what is actually on disk. The detector is
`scripts/check-docs-index.sh`; this skill is the *fixer* that consumes its
report.

## When to Use This Skill

| Use this skill when... | Use something else when... |
|------------------------|----------------------------|
| Per-plugin counts in README / PLUGIN-MAP / the d2 diagram drifted | A plugin needs adding/removing — follow CLAUDE.md § Plugin Lifecycle first, then run this |
| `check-docs-index.sh` reports `doc_count_drift` / `diagram_count_drift` | You need a generic project's docs synced — that's `documentation-plugin:docs-sync` (wrong layout for this repo) |
| The PR gate `Check docs-index drift` failed in CI | Editing rule-index or marketplace set — the audit reports those, but fix them at their source |

## Context

- Audit: !`bash scripts/check-docs-index.sh`
- README last touched: !`git log --max-count=1 --format='%h %ci' -- README.md`

## Execution

Execute this refresh:

### Step 1: Read the drift

Run `bash scripts/check-docs-index.sh` (shown in Context). Each `ISSUES:` line
names the exact file, line, and the disk-vs-stated count. `STATUS=OK` with
`ISSUE_COUNT=0` means nothing to do — stop and report clean.

### Step 2: Apply count fixes

For every `doc_count_drift` / `diagram_count_drift` issue, Edit the stated count
to the disk count:

- `README.md` — the `| **<plugin>** | N | ... |` category-table rows. Preserve any
  `+ M agents` suffix.
- `docs/PLUGIN-MAP.md` — the `| <plugin> | N | ... |` tier-table rows.
- `docs/diagrams/plugin-relationships.d2` — the `label: "<name>\nN skills"` node
  labels (the `.svg` is generated, never hand-edited).

### Step 3: Light content pass

1. `git log --oneline <README-last-touched-sha>..HEAD -- '*/.claude-plugin/plugin.json'`
   — if any **new** `*-plugin` directory landed, it must be added to README's
   category tables, PLUGIN-MAP, marketplace.json, and release config (see
   CLAUDE.md § Plugin Lifecycle). Surface this rather than guessing a category.
2. Update the rounded total in README's intro line (`NNN+ skills`) to the next
   round number at or below `TOTAL_SKILLS` from the audit.

### Step 4: Re-render the diagram

If the d2 changed: `d2 docs/diagrams/plugin-relationships.d2 docs/diagrams/plugin-relationships.svg`.
Commit the `.d2` and `.svg` together.

### Step 5: Verify and commit

1. `bash scripts/check-docs-index.sh --strict` must exit 0 (`STATUS=OK`).
2. Commit as `docs: refresh plugin catalog counts` (the `docs:` type triggers no
   release bump). Stage only the catalog files you touched — never `git add -A`.

## Post-actions

Report the before/after counts and confirm the audit is clean. The PR gate
(`Check docs-index drift` in `plugin-pr-checks.yml`) will re-verify on push.
