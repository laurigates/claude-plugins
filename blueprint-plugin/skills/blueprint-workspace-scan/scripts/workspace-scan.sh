#!/usr/bin/env bash
#
# workspace-scan.sh — Discover child blueprint workspaces under a root and
# refresh the root manifest's workspaces.children registry + cached stats.
#
# Usage:
#   workspace-scan.sh --project-dir <path> [--max-depth N] [--dry-run]
#
# Output:
#   Structured KEY=value pairs with === SECTION === headers.
#
# Exit codes:
#   0 on success, 1 on invocation/filesystem error, 2 if no root manifest found.

set -uo pipefail

project_dir=""
max_depth=4
dry_run=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --project-dir) project_dir="$2"; shift 2 ;;
    --max-depth)   max_depth="$2";   shift 2 ;;
    --dry-run)     dry_run=1;        shift   ;;
    *) echo "Unknown arg: $1" >&2; exit 1 ;;
  esac
done

if [[ -z "$project_dir" ]]; then
  echo "Usage: workspace-scan.sh --project-dir <path> [--max-depth N] [--dry-run]" >&2
  exit 1
fi

if ! command -v jq >/dev/null 2>&1; then
  echo "jq is required but not installed" >&2
  exit 1
fi

root_manifest="$project_dir/docs/blueprint/manifest.json"
if [[ ! -f "$root_manifest" ]]; then
  echo "=== ERROR ==="
  echo "ROOT_MANIFEST_MISSING=$root_manifest"
  exit 2
fi

# Verify this manifest is a root (or has no workspaces.role yet — treat as candidate root)
scan_role=$(jq -r '.workspaces.role // "unset"' "$root_manifest")
if [[ "$scan_role" == "child" ]]; then
  echo "=== ERROR ==="
  echo "NOT_A_ROOT=true"
  echo "ROLE=$scan_role"
  echo "HINT=Run this from the repository root that owns this workspace, or update workspaces.role."
  exit 1
fi

timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
tmp_children=$(mktemp)
trap 'rm -f "$tmp_children"' EXIT

# Discover child manifests — skip the root itself.
# Respect .gitignore by filtering out common vendor dirs; the `-prune` pattern
# avoids descending into them entirely.
root_abs=$(cd "$project_dir" && pwd)

echo "=== DISCOVERED ==="
echo "ROOT=$root_abs"
echo "MAX_DEPTH=$max_depth"
echo "SCANNED_AT=$timestamp"

children_json='[]'
count=0

while IFS= read -r -d '' child_manifest; do
  # Skip the root manifest itself.
  child_abs=$(cd "$(dirname "$child_manifest")" && pwd)/manifest.json
  if [[ "$child_abs" == "$root_abs/docs/blueprint/manifest.json" ]]; then
    continue
  fi

  # Workspace path = dirname of "docs/blueprint/manifest.json" relative to root.
  ws_dir=$(dirname "$(dirname "$(dirname "$child_manifest")")")
  ws_rel=$(realpath --relative-to="$root_abs" "$ws_dir" 2>/dev/null || python3 -c "import os,sys; print(os.path.relpath(sys.argv[1], sys.argv[2]))" "$ws_dir" "$root_abs")

  child_fmt=$(jq -r '.format_version // "unknown"' "$child_manifest")
  child_project=$(jq -r '.project.name // ""' "$child_manifest")

  # Feature tracker cached stats (if present)
  child_ft="$ws_dir/docs/blueprint/feature-tracker.json"
  if [[ -f "$child_ft" ]]; then
    stats=$(jq -c '{
      total: (.statistics.total_features // 0),
      complete: (.statistics.complete // 0),
      completion_percentage: (.statistics.completion_percentage // 0),
      current_phase: (.current_phase // null),
      last_synced_at: "'"$timestamp"'"
    }' "$child_ft" 2>/dev/null || echo 'null')
    has_ft=true
  else
    stats='null'
    has_ft=false
  fi

  entry=$(jq -n \
    --arg path "$ws_rel" \
    --arg project "$child_project" \
    --arg fmt "$child_fmt" \
    --argjson has_ft "$has_ft" \
    --argjson stats "$stats" \
    --arg ts "$timestamp" \
    '{
      path: $path,
      project_name: $project,
      manifest_format_version: $fmt,
      has_feature_tracker: $has_ft,
      last_synced_at: $ts,
      cached_stats: $stats
    }')

  children_json=$(jq -c ". + [$entry]" <<< "$children_json")
  count=$((count + 1))
  echo "CHILD=$ws_rel fmt=$child_fmt ft=$has_ft"

done < <(find "$root_abs" -maxdepth $((max_depth + 3)) \
  -type d \( -name node_modules -o -name .git -o -name dist -o -name build -o -name target -o -name .venv \) -prune \
  -o -type f -name manifest.json -path '*/docs/blueprint/manifest.json' -print0)

echo "=== SUMMARY ==="
echo "CHILDREN_COUNT=$count"

if [[ "$dry_run" -eq 1 ]]; then
  echo "DRY_RUN=true"
  echo "=== CHILDREN_JSON ==="
  echo "$children_json" | jq .
  exit 0
fi

# Write back to root manifest: set workspaces.role=root (if unset), update children + scan time.
updated=$(jq \
  --argjson children "$children_json" \
  --arg ts "$timestamp" \
  '
    .workspaces = (.workspaces // {}) |
    .workspaces.role = (.workspaces.role // "root") |
    .workspaces.discovery_strategy = (.workspaces.discovery_strategy // "auto-cache") |
    .workspaces.last_scanned_at = $ts |
    .workspaces.children = $children |
    .updated_at = $ts
  ' "$root_manifest")

echo "$updated" > "$root_manifest"
echo "WROTE=$root_manifest"
exit 0
