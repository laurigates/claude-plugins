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

# Allow tests/tools to point the script at alternative file paths without
# having to construct a full fake $HOME. When these env vars are set they
# override the defaults derived from --home-dir.
registry_file="${FIX_REGISTRY_FILE:-${home_dir}/.claude/plugins/installed_plugins.json}"
settings_file="${FIX_SETTINGS_FILE:-${home_dir}/.claude/settings.json}"
marketplaces_dir="${FIX_MARKETPLACES_DIR:-${home_dir}/.claude/plugins/marketplaces}"
backup_dir="$(dirname "$registry_file")"

echo "=== PLUGIN REGISTRY FIX ==="
echo "HOME_DIR=${home_dir}"
echo "DRY_RUN=${dry_run}"
echo "REGISTRY_FILE=${registry_file}"
echo "SETTINGS_FILE=${settings_file}"

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

# Identify stale enabledPlugins entries: keys in settings.json whose plugin
# name is not installed AND not in any configured marketplace.
stale_enabled_keys=()
if [ -f "$settings_file" ] && jq empty "$settings_file" >/dev/null 2>&1; then
  marketplace_names=""
  if [ -d "$marketplaces_dir" ]; then
    while IFS= read -r mp_file; do
      [ -z "$mp_file" ] && continue
      mp_plugins=$(jq -r '.plugins[]?.name // empty' "$mp_file" 2>/dev/null)
      marketplace_names="${marketplace_names}
${mp_plugins}"
    done < <(find "$marketplaces_dir" -maxdepth 3 -name '*.json' -type f 2>/dev/null)
  fi

  enabled_keys_raw=$(jq -r '.enabledPlugins // {} | keys[]' "$settings_file" 2>/dev/null)
  while IFS= read -r enabled_key; do
    [ -z "$enabled_key" ] && continue
    plugin_name="${enabled_key%@*}"
    # Keep if installed in registry.
    if jq -e --arg k "$enabled_key" '.plugins[$k]' "$registry_file" >/dev/null 2>&1; then
      continue
    fi
    # Keep if present in any known marketplace (still installable).
    if [ -n "$marketplace_names" ] && printf '%s\n' "$marketplace_names" | grep -Fxq "$plugin_name"; then
      continue
    fi
    stale_enabled_keys+=("$enabled_key")
    echo "STALE_ENABLED: key=${enabled_key}"
  done <<< "$enabled_keys_raw"
fi

echo "STALE_ENABLED_COUNT=${#stale_enabled_keys[@]}"

if [ "${#orphaned_keys[@]}" -eq 0 ] && [ "${#stale_enabled_keys[@]}" -eq 0 ]; then
  echo "STATUS=OK"
  echo "MESSAGE=No orphaned entries to fix"
  echo "=== END PLUGIN REGISTRY FIX ==="
  exit 0
fi

if [ "$dry_run" = true ]; then
  echo "STATUS=DRY_RUN"
  echo "WOULD_REMOVE=${#orphaned_keys[@]}"
  echo "WOULD_REMOVE_ENABLED=${#stale_enabled_keys[@]}"
  if [ "${#stale_enabled_keys[@]}" -gt 0 ]; then
    echo "MESSAGE=Would remove ${#stale_enabled_keys[@]} stale enabledPlugins entries"
    echo "RESTART_REQUIRED=true"
  fi
  echo "=== END PLUGIN REGISTRY FIX ==="
  exit 0
fi

mkdir -p "$backup_dir"
timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
backup_file=""
settings_backup_file=""
restart_required=false

# Stage 1: Remove orphaned entries from installed_plugins.json
if [ "${#orphaned_keys[@]}" -gt 0 ]; then
  backup_file="${registry_file}.backup.${timestamp}"
  if ! cp "$registry_file" "$backup_file"; then
    echo "STATUS=ERROR"
    echo "ERROR=Failed to create registry backup"
    echo "=== END PLUGIN REGISTRY FIX ==="
    exit 1
  fi
  echo "BACKUP_CREATED=${backup_file}"

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

  if ! jq empty "$tmp_file" >/dev/null 2>&1; then
    echo "STATUS=ERROR"
    echo "ERROR=Resulting registry JSON is invalid; no changes applied"
    rm -f "$tmp_file"
    echo "=== END PLUGIN REGISTRY FIX ==="
    exit 1
  fi

  mv "$tmp_file" "$registry_file"

  for plugin_key in "${orphaned_keys[@]}"; do
    echo "REMOVED=${plugin_key}"
  done
  restart_required=true
fi

# Stage 2: Remove stale enabledPlugins entries from settings.json
if [ "${#stale_enabled_keys[@]}" -gt 0 ] && [ -f "$settings_file" ]; then
  settings_backup_file="${settings_file}.backup.${timestamp}"
  if ! cp "$settings_file" "$settings_backup_file"; then
    echo "STATUS=ERROR"
    echo "ERROR=Failed to create settings backup"
    echo "=== END PLUGIN REGISTRY FIX ==="
    exit 1
  fi
  echo "SETTINGS_BACKUP_CREATED=${settings_backup_file}"

  settings_filter='.'
  for enabled_key in "${stale_enabled_keys[@]}"; do
    settings_filter="${settings_filter} | del(.enabledPlugins[\"${enabled_key}\"])"
  done

  settings_tmp="${settings_file}.tmp.$$"
  if ! jq "$settings_filter" "$settings_file" > "$settings_tmp"; then
    echo "STATUS=ERROR"
    echo "ERROR=jq transformation of settings.json failed"
    rm -f "$settings_tmp"
    echo "=== END PLUGIN REGISTRY FIX ==="
    exit 1
  fi

  if ! jq empty "$settings_tmp" >/dev/null 2>&1; then
    echo "STATUS=ERROR"
    echo "ERROR=Resulting settings JSON is invalid; no changes applied"
    rm -f "$settings_tmp"
    echo "=== END PLUGIN REGISTRY FIX ==="
    exit 1
  fi

  mv "$settings_tmp" "$settings_file"

  for enabled_key in "${stale_enabled_keys[@]}"; do
    echo "REMOVED_ENABLED=${enabled_key}"
  done
  echo "MESSAGE=Removed ${#stale_enabled_keys[@]} stale enabledPlugins entries"
  restart_required=true
fi

echo "STATUS=FIXED"
echo "REMOVED_COUNT=${#orphaned_keys[@]}"
echo "REMOVED_ENABLED_COUNT=${#stale_enabled_keys[@]}"
[ -n "$backup_file" ] && echo "BACKUP_PATH=${backup_file}"
[ -n "$settings_backup_file" ] && echo "SETTINGS_BACKUP_PATH=${settings_backup_file}"
if [ "$restart_required" = true ]; then
  echo "RESTART_REQUIRED=true"
fi
echo "=== END PLUGIN REGISTRY FIX ==="
