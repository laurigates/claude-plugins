---
created: 2026-01-20
modified: 2026-07-05
reviewed: 2026-06-10
description: Scan blueprint docs and assign missing PRD/ADR/PRP/WO IDs. Use when assigning IDs to docs; --dry-run to preview, --link-issues to create GitHub issues for orphans.
args: "[--dry-run] [--link-issues]"
argument-hint: "--dry-run to preview changes, --link-issues to create GitHub issues for orphans"
allowed-tools: Read, Write, Edit, Glob, Bash, AskUserQuestion
model: sonnet
name: blueprint-sync-ids
---

Scan all PRDs, ADRs, PRPs, and work-orders, assign IDs to documents missing them, and update the manifest registry.

## When to Use This Skill

| Use this skill when... | Use blueprint-sync instead when... |
|---|---|
| You're assigning PRD-NNN / ADR-NNNN / PRP-NNN / WO-NNN to docs missing them | You want to detect modified or stale generated content (not IDs) |
| You're previewing ID assignments with `--dry-run` | You're reconciling drift between `.claude/rules/` and the manifest |
| You want to create GitHub issues for orphan docs via `--link-issues` | Use document-linking instead for runtime cross-doc traceability |

## Flags

| Flag | Description |
|------|-------------|
| `--dry-run` | Preview changes without modifying files |
| `--link-issues` | Also create GitHub issues for orphan documents |

## Interaction Mode

Before any closing `AskUserQuestion` menu, resolve the automation config:

```bash
bash "${CLAUDE_SKILL_DIR}/../../scripts/get-automation-config.sh"
```

When `EFFECTIVE_INTERACTION_MODE=quiet` **and** this invocation was
automation-initiated (autopilot, session bookend, drift-nudge follow-up — not
a slash command the user typed), skip closing navigation menus ("what next?" /
"create another?" style): apply the safe default and end with a one-line
receipt instead. Quiet mode never skips confirmation gates that guard writes —
only navigation menus. A direct user invocation always behaves fully
interactively (explicit intent overrides quiet; see ADR-0020).

## Prerequisites

- Blueprint initialized (`docs/blueprint/manifest.json` exists)
- At least one document exists in `docs/prds/`, `docs/adrs/`, `docs/prps/`, or `docs/blueprint/work-orders/`

## Steps

### Step 1: Initialize ID Registry

Check if `id_registry` exists in manifest:

```bash
jq -e '.id_registry' docs/blueprint/manifest.json >/dev/null 2>&1
```

If not, initialize it:

```json
{
  "id_registry": {
    "last_prd": 0,
    "last_prp": 0,
    "documents": {},
    "github_issues": {}
  }
}
```

### Step 2: Run the read-only ID audit

Run the helper. It owns the read-only scan: frontmatter `id:` extraction across
PRDs/ADRs/PRPs/work-orders, deriving the expected `ADR-NNNN` / `WO-NNN` from each
filename, flagging `NEEDS_ID` (no id) and `id_mismatch` (frontmatter id disagrees
with the filename-derived expectation), and building the reverse `github_issues`
index from the manifest registry:

```bash
bash "${CLAUDE_SKILL_DIR}/scripts/blueprint-sync-ids.sh" --home-dir "$HOME" --project-dir "$(pwd)"
```

Parse `STATUS=` and `ISSUES:` from the output:

- `PRD_NEEDS_ID` / `ADR_NEEDS_ID` / `PRP_NEEDS_ID` / `WO_NEEDS_ID` and the
  `needs_id` issues are the documents to assign IDs to in Step 7 (each carries
  `DOC=` and, for ADRs/WOs, the `EXPECTED=` filename-derived ID).
- `ADR_MISMATCH` / `WO_MISMATCH` and the `id_mismatch` issues (`HAS=` vs
  `EXPECTED=`) are documents whose frontmatter id disagrees with their filename
  — reconcile these in Step 7, never silently. `STATUS=ERROR` indicates at least
  one mismatch.
- `GH_ISSUE_MAPPINGS` and `MANIFEST_PRESENT` summarise the reverse-index build
  (Step 9 detail below).

The audit is read-only; it makes no edits. Surface its counts as the Step 6
report and proceed to the mutating steps.

### Step 7: Assign IDs (unless `--dry-run`)

For each document needing an ID:

**PRDs**:
1. Get next PRD number: `jq '.id_registry.last_prd' manifest.json` + 1
2. Generate ID: `PRD-NNN` (zero-padded)
3. Insert into frontmatter after first `---`:
   ```yaml
   id: PRD-001
   ```
4. Update manifest: increment `last_prd`, add to `documents`

**ADRs**:
1. Derive ID from filename: `0003-title.md` → `ADR-0003`
2. Insert into frontmatter
3. Add to manifest `documents`

**PRPs**:
1. Get next PRP number: `jq '.id_registry.last_prp' manifest.json` + 1
2. Generate ID: `PRP-NNN`
3. Insert into frontmatter
4. Update manifest: increment `last_prp`, add to `documents`

**Work-Orders**:
1. Derive ID from filename: `003-task.md` → `WO-003`
2. Insert into frontmatter
3. Add to manifest `documents`

### Step 8: Extract Titles and Links

For each document, also extract:
- **Title**: First `# ` heading or frontmatter `name`/`title` field
- **Existing links**: `relates-to`, `implements`, `github-issues` from frontmatter
- **Status**: From frontmatter

Store in manifest registry:

```json
{
  "documents": {
    "PRD-001": {
      "path": "docs/prds/user-auth.md",
      "title": "User Authentication",
      "status": "Active",
      "relates_to": ["ADR-0003"],
      "github_issues": [42],
      "created": "2026-01-15"
    }
  }
}
```

### Step 9: Build GitHub Issue Index

The Step 2 audit already groups the manifest's per-document `github_issues`
arrays into the reverse index (`GH_ISSUE_MAPPINGS=` reports how many distinct
issue numbers map to documents). Write that reverse index into the manifest:

```json
{
  "github_issues": {
    "42": ["PRD-001", "PRP-002"],
    "45": ["WO-003"]
  }
}
```

### Step 10: Create Issues for Orphans (if `--link-issues`)

For each document without `github-issues`:

```
question: "Create GitHub issue for {ID}: {title}?"
options:
  - label: "Yes, create issue"
    description: "Creates [{ID}] {title} issue"
  - label: "Skip this one"
    description: "Leave unlinked for now"
  - label: "Skip all remaining"
    description: "Don't prompt for more orphans"
```

If yes:
```bash
gh issue create \
  --title "[{ID}] {title}" \
  --body "## {Document Type}

**ID**: {ID}
**Document**: \`{path}\`

{Brief description from document}

---
*Auto-generated by /blueprint:sync-ids*" \
  --label "{type-label}"
```

Update document frontmatter and manifest with new issue number.

### Step 11: Update task registry

Update the task registry entry in `docs/blueprint/manifest.json`:

```bash
jq --arg now "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  --argjson processed "${DOCS_CHECKED:-0}" \
  --argjson created "${IDS_ASSIGNED:-0}" \
  '.task_registry["sync-ids"].last_completed_at = $now |
   .task_registry["sync-ids"].last_result = "success" |
   .task_registry["sync-ids"].stats.runs_total = ((.task_registry["sync-ids"].stats.runs_total // 0) + 1) |
   .task_registry["sync-ids"].stats.items_processed = $processed |
   .task_registry["sync-ids"].stats.items_created = $created' \
  docs/blueprint/manifest.json > tmp.json && mv tmp.json docs/blueprint/manifest.json
```

### Step 12: Final Report

```
ID Sync Complete

Assigned IDs:
- PRD-003: docs/prds/payment-flow.md
- PRD-004: docs/prds/notifications.md
- PRP-005: docs/prps/stripe-integration.md

Updated Manifest:
- last_prd: 4
- last_prp: 5
- documents: 22 entries
- github_issues: 18 mappings

{If --link-issues:}
Created GitHub Issues:
- #52: [PRD-003] Payment Flow
- #53: [PRP-005] Stripe Integration

Still orphaned (no GitHub issues):
- ADR-0004: Database Migration Strategy
- WO-008: Add error handling

Run `/blueprint:status` to see full traceability report.
```

## Error Handling

| Condition | Action |
|-----------|--------|
| No manifest | Error: Run `/blueprint:init` first |
| No documents found | Warning: No documents to scan |
| Frontmatter parse error | Warning: Skip file, report for manual fix |
| `gh` not available | Skip issue creation, warn user |
| Write permission denied | Error: Check file permissions |

## Manifest Schema

After sync, manifest includes:

```json
{
  "id_registry": {
    "last_prd": 4,
    "last_prp": 5,
    "documents": {
      "PRD-001": {
        "path": "docs/prds/user-auth.md",
        "title": "User Authentication",
        "status": "Active",
        "relates_to": ["ADR-0003"],
        "implements": [],
        "github_issues": [42],
        "created": "2026-01-10"
      },
      "ADR-0003": {
        "path": "docs/adrs/0003-session-storage.md",
        "title": "Session Storage Strategy",
        "status": "Accepted",
        "domain": "authentication",
        "relates_to": ["PRD-001"],
        "github_issues": [],
        "created": "2026-01-12"
      }
    },
    "github_issues": {
      "42": ["PRD-001", "PRP-002"],
      "45": ["WO-003"]
    }
  }
}
```
