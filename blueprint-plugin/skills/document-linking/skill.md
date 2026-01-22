---
model: haiku
created: 2026-01-20
modified: 2026-01-20
reviewed: 2026-01-20
name: document-linking
description: "Unified ID system for PRDs, ADRs, PRPs, and GitHub issues. Auto-generates IDs on document access, maintains bidirectional links, and provides traceability across all artifacts."
---

# Document Linking

Provides a unified ID system connecting PRDs, ADRs, PRPs, work-orders, GitHub issues, commits, and PRs. IDs are project-scoped, auto-generated on first access, and maintained bidirectionally.

## ID Format

| Document Type | Format | Example | Notes |
|---------------|--------|---------|-------|
| PRD | `PRD-NNN` | `PRD-001` | 3-digit, zero-padded |
| ADR | `ADR-NNNN` | `ADR-0003` | 4-digit (matches existing convention) |
| PRP | `PRP-NNN` | `PRP-007` | 3-digit, zero-padded |
| Work-Order | `WO-NNN` | `WO-042` | 3-digit, matches work-order number |

## Frontmatter Schema

All blueprint documents should include these fields:

```yaml
---
id: PRD-001                    # Unique identifier (auto-generated if missing)
relates-to:                    # Cross-document references (optional)
  - ADR-0003
  - PRP-002
github-issues:                 # Linked GitHub issues (optional)
  - 42
  - 87
implements:                    # For PRPs: source PRD (optional)
  - PRD-001
# ... existing fields (created, modified, status, etc.)
---
```

## ID Registry (manifest.json)

IDs are tracked in `docs/blueprint/manifest.json`:

```json
{
  "id_registry": {
    "last_prd": 3,
    "last_prp": 7,
    "documents": {
      "PRD-001": {
        "path": "docs/prds/user-authentication.md",
        "github_issues": [42, 87],
        "title": "User Authentication"
      },
      "ADR-0003": {
        "path": "docs/adrs/0003-database-choice.md",
        "github_issues": [],
        "title": "Database Choice"
      },
      "PRP-002": {
        "path": "docs/prps/oauth-integration.md",
        "github_issues": [45],
        "implements": ["PRD-001"],
        "title": "OAuth Integration"
      }
    },
    "github_issues": {
      "42": ["PRD-001", "PRP-002"],
      "45": ["PRP-002"],
      "87": ["PRD-001"]
    }
  }
}
```

## Auto-ID Generation

### When Triggered

IDs are automatically generated when:

1. **Creating documents** - `/blueprint:prd`, `/blueprint:adr`, `/blueprint:prp-create`
2. **Accessing documents without IDs** - Any command reading PRD/ADR/PRP files
3. **Batch sync** - `/blueprint:sync-ids` assigns IDs to all documents

### Generation Algorithm

```bash
# Get next PRD ID
get_next_prd_id() {
  local manifest="docs/blueprint/manifest.json"
  local last=$(jq -r '.id_registry.last_prd // 0' "$manifest")
  local next=$((last + 1))
  printf "PRD-%03d" "$next"
}

# Get next PRP ID
get_next_prp_id() {
  local manifest="docs/blueprint/manifest.json"
  local last=$(jq -r '.id_registry.last_prp // 0' "$manifest")
  local next=$((last + 1))
  printf "PRP-%03d" "$next"
}

# ADR IDs use existing 4-digit number from filename
get_adr_id() {
  local filename="$1"
  local num=$(basename "$filename" | grep -oE '^[0-9]{4}')
  printf "ADR-%s" "$num"
}
```

### Auto-Assignment on Access

When reading a document without an ID:

1. **Check frontmatter** for existing `id` field
2. **If missing**: Generate next available ID
3. **Update document** frontmatter with new ID
4. **Update manifest** ID registry
5. **Continue** with original operation

```bash
# Check if document has ID
ensure_document_id() {
  local file="$1"
  local type="$2"  # PRD, ADR, PRP

  # Extract existing ID from frontmatter
  local existing_id=$(head -50 "$file" | grep -m1 "^id:" | sed 's/^id:[[:space:]]*//')

  if [ -z "$existing_id" ]; then
    # Generate and assign new ID
    case "$type" in
      PRD) new_id=$(get_next_prd_id) ;;
      PRP) new_id=$(get_next_prp_id) ;;
      ADR) new_id=$(get_adr_id "$file") ;;
    esac

    # Insert ID into frontmatter (after first ---)
    # Update manifest registry
    # Return new ID
  fi

  echo "${existing_id:-$new_id}"
}
```

## GitHub Integration

### Issue Title Format

When creating GitHub issues from documents:

```
[PRD-001] User authentication feature
[PRP-002] Implement OAuth integration
[WO-042] Add JWT token generation
```

### Issue Body Format

```markdown
## Related Documents
- PRD-001: User Authentication
- ADR-0003: Database Choice

## Traceability
- **Implements**: PRD-001
- **Related ADRs**: ADR-0003, ADR-0005
- **Work Orders**: WO-042, WO-043

---
*Auto-linked by Blueprint. Update document frontmatter to modify links.*
```

### Commit Message Format

```
feat(PRD-001): add login form component

Implements requirement FR-003 from PRD-001.
Related: ADR-0003 (session storage decision)
```

### PR Title/Body Format

**Title**: `[PRD-001] Implement user authentication`

**Body**:
```markdown
## Summary
Implements user authentication as specified in PRD-001.

## Related Documents
- PRD-001: User Authentication
- ADR-0003: Database Choice
- PRP-002: OAuth Integration

## Closes
- Fixes #42
- Fixes #87
```

## Bidirectional Link Maintenance

### When Creating Links

1. **Document → GitHub Issue**
   - Add issue number to document's `github-issues` array
   - Add document ID to issue body (comment or edit)
   - Update manifest registry

2. **Document → Document**
   - Add target ID to source's `relates-to` array
   - Add source ID to target's `relates-to` array (bidirectional)
   - Update manifest registry

3. **PRP → PRD (implements)**
   - Add PRD ID to PRP's `implements` field
   - Add PRP ID to PRD's `implemented-by` tracking in manifest

### Link Validation

Check for broken links during `/blueprint:status`:

```bash
# Validate all links in manifest
validate_links() {
  local manifest="docs/blueprint/manifest.json"

  # Check each document exists
  jq -r '.id_registry.documents | to_entries[] | "\(.key) \(.value.path)"' "$manifest" | \
  while read id path; do
    if [ ! -f "$path" ]; then
      echo "BROKEN: $id -> $path (file missing)"
    fi
  done

  # Check GitHub issues exist (if gh available)
  if command -v gh &>/dev/null; then
    jq -r '.id_registry.github_issues | keys[]' "$manifest" | \
    while read issue; do
      if ! gh issue view "$issue" &>/dev/null; then
        echo "BROKEN: GitHub issue #$issue (not found or closed)"
      fi
    done
  fi
}
```

## Traceability Queries

### Find All Related Documents

```bash
# Get all documents related to a specific ID
get_related() {
  local id="$1"
  local manifest="docs/blueprint/manifest.json"

  # Direct relations from document
  jq -r --arg id "$id" '
    .id_registry.documents[$id].relates_to // [] | .[]
  ' "$manifest"

  # Documents that reference this one
  jq -r --arg id "$id" '
    .id_registry.documents | to_entries[] |
    select(.value.relates_to // [] | contains([$id])) | .key
  ' "$manifest"
}
```

### Find Implementation Chain

```bash
# PRD -> PRP -> Work-Orders -> GitHub Issues
get_implementation_chain() {
  local prd_id="$1"
  local manifest="docs/blueprint/manifest.json"

  echo "=== Implementation Chain for $prd_id ==="

  # Find PRPs implementing this PRD
  echo "PRPs:"
  jq -r --arg id "$prd_id" '
    .id_registry.documents | to_entries[] |
    select(.value.implements // [] | contains([$id])) |
    "  - \(.key): \(.value.title)"
  ' "$manifest"

  # Find work-orders for those PRPs
  echo "Work-Orders:"
  # ... similar query

  # Find GitHub issues
  echo "GitHub Issues:"
  jq -r --arg id "$prd_id" '
    .id_registry.documents[$id].github_issues // [] | .[] | "  - #\(.)"
  ' "$manifest"
}
```

## Orphan Detection

### Documents Without GitHub Issues

```bash
find_orphan_documents() {
  local manifest="docs/blueprint/manifest.json"

  echo "Documents without GitHub issues:"
  jq -r '
    .id_registry.documents | to_entries[] |
    select((.value.github_issues // []) | length == 0) |
    "  - \(.key): \(.value.title)"
  ' "$manifest"
}
```

### GitHub Issues Without Documents

```bash
find_orphan_issues() {
  # List recent open issues
  gh issue list --json number,title --limit 50 | jq -r '.[] | "\(.number) \(.title)"' | \
  while read num title; do
    # Check if issue is in registry
    if ! jq -e --arg n "$num" '.id_registry.github_issues[$n]' docs/blueprint/manifest.json &>/dev/null; then
      # Check if title contains document ID
      if ! echo "$title" | grep -qE '\[(PRD|ADR|PRP|WO)-[0-9]+\]'; then
        echo "  - #$num: $title"
      fi
    fi
  done
}
```

## Duplicate Detection

### Before Creating GitHub Issue

```bash
check_for_duplicates() {
  local feature_name="$1"
  local manifest="docs/blueprint/manifest.json"

  # Search for similar document titles
  echo "Checking for existing documents..."

  # Fuzzy match against PRD titles
  jq -r '.id_registry.documents | to_entries[] |
    select(.key | startswith("PRD")) |
    "\(.key): \(.value.title)"
  ' "$manifest" | grep -i "$feature_name" || true

  # Search existing GitHub issues
  gh issue list --search "$feature_name" --json number,title --limit 5 | \
  jq -r '.[] | "#\(.number): \(.title)"'
}
```

## Integration Points

### /blueprint:prd

After creating PRD:
1. Generate `PRD-NNN` ID
2. Add to frontmatter
3. Update manifest registry
4. Prompt: "Create GitHub issue for tracking?"

### /blueprint:adr

After creating ADR:
1. Extract `ADR-NNNN` from filename
2. Add to frontmatter (if missing)
3. Update manifest registry
4. Link to related PRDs if applicable

### /blueprint:prp-create

After creating PRP:
1. Generate `PRP-NNN` ID
2. Prompt: "Which PRD does this implement?"
3. Add `implements` field
4. Update manifest registry with bidirectional link

### /blueprint:work-order

After creating work-order:
1. Assign `WO-NNN` ID
2. Auto-link to source PRP/PRD
3. Create GitHub issue with ID in title
4. Update manifest registry

### /blueprint:status

Show traceability section:
```
Traceability:
- Documents: 15 total (3 PRDs, 5 ADRs, 7 PRPs)
- Linked to GitHub: 12/15 (80%)
- Orphan documents: 3 (PRD-002, ADR-0004, PRP-006)
- Orphan issues: 2 (#23, #45)
- Broken links: 0
```

## Quick Reference

| Operation | Command |
|-----------|---------|
| Assign IDs to all docs | `/blueprint:sync-ids` |
| Link doc to issue | Update `github-issues` in frontmatter |
| Link doc to doc | Update `relates-to` in frontmatter |
| View traceability | `/blueprint:status` |
| Find orphans | `/blueprint:status` (included) |

| GitHub Format | Example |
|---------------|---------|
| Issue title | `[PRD-001] Feature name` |
| Commit scope | `feat(PRD-001): description` |
| PR reference | `Implements PRD-001, Fixes #42` |
