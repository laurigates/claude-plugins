# document-linking — Orphan and Duplicate Detection

Registry queries for unlinked documents and issues, and the pre-issue duplicate check.

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
