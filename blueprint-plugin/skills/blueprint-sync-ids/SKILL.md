---
model: sonnet
created: 2026-01-20
modified: 2026-02-17
reviewed: 2026-01-20
description: "Scan all blueprint documents and assign IDs to those missing them, update manifest registry"
args: "[--dry-run] [--link-issues]"
argument-hint: "--dry-run to preview changes, --link-issues to create GitHub issues for orphans"
allowed-tools: Read, Write, Edit, Glob, Bash, AskUserQuestion
name: blueprint-sync-ids
---

Scan all PRDs, ADRs, PRPs, and work-orders, assign IDs to documents missing them, and update the manifest registry.

## Flags

| Flag | Description |
|------|-------------|
| `--dry-run` | Preview changes without modifying files |
| `--link-issues` | Also create GitHub issues for orphan documents |

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

### Step 2: Scan PRDs

```bash
for prd in docs/prds/*.md; do
  [ -f "$prd" ] || continue

  # Check for existing ID in frontmatter
  existing_id=$(head -50 "$prd" | grep -m1 "^id:" | sed 's/^id:[[:space:]]*//')

  if [ -z "$existing_id" ]; then
    echo "NEEDS_ID: $prd"
  else
    echo "HAS_ID: $prd ($existing_id)"
  fi
done
```

### Step 3: Scan ADRs

```bash
for adr in docs/adrs/*.md; do
  [ -f "$adr" ] || continue

  # ADR ID derived from filename (0001-title.md → ADR-0001)
  filename=$(basename "$adr")
  num=$(echo "$filename" | grep -oE '^[0-9]{4}')

  if [ -n "$num" ]; then
    expected_id="ADR-$num"
    existing_id=$(head -50 "$adr" | grep -m1 "^id:" | sed 's/^id:[[:space:]]*//')

    if [ -z "$existing_id" ]; then
      echo "NEEDS_ID: $adr (should be $expected_id)"
    elif [ "$existing_id" != "$expected_id" ]; then
      echo "MISMATCH: $adr (has $existing_id, should be $expected_id)"
    else
      echo "HAS_ID: $adr ($existing_id)"
    fi
  fi
done
```

### Step 4: Scan PRPs

```bash
for prp in docs/prps/*.md; do
  [ -f "$prp" ] || continue

  existing_id=$(head -50 "$prp" | grep -m1 "^id:" | sed 's/^id:[[:space:]]*//')

  if [ -z "$existing_id" ]; then
    echo "NEEDS_ID: $prp"
  else
    echo "HAS_ID: $prp ($existing_id)"
  fi
done
```

### Step 5: Scan Work-Orders

```bash
for wo in docs/blueprint/work-orders/*.md; do
  [ -f "$wo" ] || continue

  # WO ID derived from filename (003-task.md → WO-003)
  filename=$(basename "$wo")
  num=$(echo "$filename" | grep -oE '^[0-9]{3}')

  if [ -n "$num" ]; then
    expected_id="WO-$num"
    existing_id=$(head -50 "$wo" | grep -m1 "^id:" | sed 's/^id:[[:space:]]*//')

    if [ -z "$existing_id" ]; then
      echo "NEEDS_ID: $wo (should be $expected_id)"
    else
      echo "HAS_ID: $wo ($existing_id)"
    fi
  fi
done
```

### Step 6: Report Findings

```
Document ID Scan Results

PRDs:
- With IDs: X
- Missing IDs: Y
  - docs/prds/feature-a.md
  - docs/prds/feature-b.md

ADRs:
- With IDs: X
- Missing IDs: Y
- Mismatched IDs: Z

PRPs:
- With IDs: X
- Missing IDs: Y

Work-Orders:
- With IDs: X
- Missing IDs: Y

Total: X documents, Y need IDs
```

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

Scan all documents for `github-issues` field and build reverse index:

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
