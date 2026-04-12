#!/usr/bin/env bash
# Fix Claude Code plugin registry issues
# Creates a timestamped backup, then removes orphaned projectPath entries.
# Validates JSON before and after modifications.
# Usage:
#   bash fix-registry.sh --home-dir <path> --project-dir <path> [--plugin <name>] [--dry-run]

set -uo pipefail

home_dir=""
project_dir=""
target_plugin=""
dry_run=false

while [ $# -gt 0 ]; do
  case "$1" in
    --home-dir) home_dir="$2"; shift 2 ;;
    --project-dir) project_dir="$2"; shift 2 ;;
    --plugin) target_plugin="$2"; shift 2 ;;
    --dry-run) dry_run=true; shift ;;
    *) shift ;;
  esac
done

: "${home_dir:=$HOME}"
: "${project_dir:=$(pwd)}"

echo "=== PLUGIN REGISTRY FIX ==="
echo "HOME_DIR=${home_dir}"
echo "DRY_RUN=${dry_run}"

registry_file="${home_dir}/.claude/plugins/installed_plugins.json"
backup_dir="${home_dir}/.claude/plugins"

if ! command -v jq >/dev/null 2>&1; then
  echo "STATUS=ERROR"
  echo "ERROR=jq is required but not installed"
  echo "=== END PLUGIN REGISTRY FIX ==="
  exit 1
fi

if [ ! -f "$registry_file" ]; then
  echo "STATUS=ERROR"
  echo "ERROR=Registry file not found at ${registry_file}"
  echo "=== END PLUGIN REGISTRY FIX ==="
  exit 1
fi

if ! jq empty "$registry_file" >/dev/null 2>&1; then
  echo "STATUS=ERROR"
  echo "ERROR=Registry file contains invalid JSON"
  echo "=== END PLUGIN REGISTRY FIX ==="
  exit 1
fi

# Identify orphaned entries
if [ -n "$target_plugin" ]; then
  plugin_keys=$(jq -r --arg k "$target_plugin" '.plugins | keys[] | select(. == $k or startswith($k + "@"))' "$registry_file" 2>/dev/null)
else
  plugin_keys=$(jq -r '.plugins | keys[]' "$registry_file" 2>/dev/null)
fi

orphaned_keys=()
while IFS= read -r plugin_key; do
  [ -z "$plugin_key" ] && continue
  plugin_path=$(jq -r --arg k "$plugin_key" '.plugins[$k][0].projectPath // ""' "$registry_file" 2>/dev/null)
  if [ -n "$plugin_path" ] && [ ! -d "$plugin_path" ]; then
    orphaned_keys+=("$plugin_key")
    echo "ORPHANED: plugin=${plugin_key} path=${plugin_path}"
  fi
done <<< "$plugin_keys"

echo "ORPHANED_COUNT=${#orphaned_keys[@]}"

if [ "${#orphaned_keys[@]}" -eq 0 ]; then
  echo "STATUS=OK"
  echo "MESSAGE=No orphaned entries to fix"
  echo "=== END PLUGIN REGISTRY FIX ==="
  exit 0
fi

if [ "$dry_run" = true ]; then
  echo "STATUS=DRY_RUN"
  echo "WOULD_REMOVE=${#orphaned_keys[@]}"
  echo "=== END PLUGIN REGISTRY FIX ==="
  exit 0
fi

# Create backup
mkdir -p "$backup_dir"
backup_file="${registry_file}.backup.$(date -u +%Y%m%dT%H%M%SZ)"
if ! cp "$registry_file" "$backup_file"; then
  echo "STATUS=ERROR"
  echo "ERROR=Failed to create backup"
  echo "=== END PLUGIN REGISTRY FIX ==="
  exit 1
fi
echo "BACKUP_CREATED=${backup_file}"

# Build jq filter to delete orphaned keys
jq_filter='.'
for plugin_key in "${orphaned_keys[@]}"; do
  jq_filter="${jq_filter} | del(.plugins[\"${plugin_key}\"])"
done

tmp_file="${registry_file}.tmp.$$"
if ! jq "$jq_filter" "$registry_file" > "$tmp_file"; then
  echo "STATUS=ERROR"
  echo "ERROR=jq transformation failed"
  rm -f "$tmp_file"
  echo "=== END PLUGIN REGISTRY FIX ==="
  exit 1
fi

# Validate result
if ! jq empty "$tmp_file" >/dev/null 2>&1; then
  echo "STATUS=ERROR"
  echo "ERROR=Resulting JSON is invalid; no changes applied"
  rm -f "$tmp_file"
  echo "=== END PLUGIN REGISTRY FIX ==="
  exit 1
fi

mv "$tmp_file" "$registry_file"

for plugin_key in "${orphaned_keys[@]}"; do
  echo "REMOVED=${plugin_key}"
done

echo "STATUS=FIXED"
echo "REMOVED_COUNT=${#orphaned_keys[@]}"
echo "BACKUP_PATH=${backup_file}"
echo "=== END PLUGIN REGISTRY FIX ==="
