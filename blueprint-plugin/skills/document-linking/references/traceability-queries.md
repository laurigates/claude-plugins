# document-linking — Traceability Queries

Registry queries for related documents and PRD → PRP → work-order → issue chains.

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
