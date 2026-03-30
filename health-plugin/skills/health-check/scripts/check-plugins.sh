#!/usr/bin/env bash
# Check Plugin Registry
# Validates installed_plugins.json for orphaned entries, scope conflicts,
# and mismatches between installed and enabled plugins.
# Usage: bash check-plugins.sh --home-dir <path> --project-dir <path> [--fix] [--verbose]

set -uo pipefail

home_dir=""
project_dir=""
fix_mode=false
verbose_mode=false

while [ $# -gt 0 ]; do
  case "$1" in
    --home-dir) home_dir="$2"; shift 2 ;;
    --project-dir) project_dir="$2"; shift 2 ;;
    --fix) fix_mode=true; shift ;;
    --verbose) verbose_mode=true; shift ;;
    *) shift ;;
  esac
done

: "${home_dir:=$HOME}"
: "${project_dir:=$(pwd)}"

echo "=== PLUGIN REGISTRY ==="

registry_file="${home_dir}/.claude/plugins/installed_plugins.json"
user_settings="${home_dir}/.claude/settings.json"

issue_count=0
check_status="OK"
issues_list=""

# Check jq availability
if ! command -v jq >/dev/null 2>&1; then
  echo "JQ_AVAILABLE=false"
  echo "STATUS=ERROR"
  echo "ISSUE_COUNT=1"
  echo "ISSUES:"
  echo "  - SEVERITY=ERROR TYPE=missing_tool MSG=jq is required but not installed"
  echo "=== END PLUGIN REGISTRY ==="
  exit 1
fi

# Check registry exists
if [ ! -f "$registry_file" ]; then
  echo "REGISTRY_EXISTS=false"
  echo "REGISTRY_PATH=${registry_file}"
  echo "STATUS=WARN"
  echo "ISSUE_COUNT=1"
  echo "ISSUES:"
  echo "  - SEVERITY=WARN TYPE=missing_registry MSG=Plugin registry file not found"
  echo "=== END PLUGIN REGISTRY ==="
  exit 0
fi

echo "REGISTRY_EXISTS=true"
echo "REGISTRY_PATH=${registry_file}"

# Validate JSON syntax
json_error=$(jq empty "$registry_file" 2>&1)
if [ $? -ne 0 ]; then
  echo "REGISTRY_VALID=false"
  echo "STATUS=ERROR"
  echo "ISSUE_COUNT=1"
  echo "ISSUES:"
  echo "  - SEVERITY=ERROR TYPE=invalid_json MSG=${json_error}"
  echo "=== END PLUGIN REGISTRY ==="
  exit 1
fi

echo "REGISTRY_VALID=true"

# Count plugins
plugin_count=$(jq '.plugins | length' "$registry_file" 2>/dev/null || echo "0")
echo "PLUGIN_COUNT=${plugin_count}"

# Count by scope
project_scoped=0
global_scoped=0
orphaned_count=0

# Extract plugin entries with project paths
plugin_keys=$(jq -r '.plugins | keys[]' "$registry_file" 2>/dev/null)

while IFS= read -r plugin_key; do
  [ -z "$plugin_key" ] && continue

  plugin_path=$(jq -r ".plugins[\"${plugin_key}\"][0].projectPath // \"\"" "$registry_file" 2>/dev/null)

  if [ -n "$plugin_path" ]; then
    project_scoped=$((project_scoped + 1))

    # Check if project path exists
    if [ ! -d "$plugin_path" ]; then
      orphaned_count=$((orphaned_count + 1))
      issues_list="${issues_list}  - SEVERITY=WARN TYPE=orphaned PLUGIN=${plugin_key} PATH=${plugin_path}\n"
      issue_count=$((issue_count + 1))
      [ "$check_status" = "OK" ] && check_status="WARN"
    fi
  else
    global_scoped=$((global_scoped + 1))
  fi

  if [ "$verbose_mode" = true ]; then
    plugin_source=$(jq -r ".plugins[\"${plugin_key}\"][0].source // \"unknown\"" "$registry_file" 2>/dev/null)
    plugin_scope=$(jq -r ".plugins[\"${plugin_key}\"][0].scope // \"user\"" "$registry_file" 2>/dev/null)
    echo "PLUGIN: name=${plugin_key} scope=${plugin_scope} source=${plugin_source}"
  fi
done <<< "$plugin_keys"

echo "PROJECT_SCOPED=${project_scoped}"
echo "GLOBAL_SCOPED=${global_scoped}"
echo "ORPHANED_ENTRIES=${orphaned_count}"

# Check enabled plugins vs installed plugins
if [ -f "$user_settings" ]; then
  enabled_count=$(jq '.enabledPlugins // {} | length' "$user_settings" 2>/dev/null || echo "0")
  echo "ENABLED_IN_SETTINGS=${enabled_count}"

  # Find enabled but not installed
  enabled_keys=$(jq -r '.enabledPlugins // {} | keys[]' "$user_settings" 2>/dev/null)
  while IFS= read -r enabled_key; do
    [ -z "$enabled_key" ] && continue
    if ! jq -e ".plugins[\"${enabled_key}\"]" "$registry_file" >/dev/null 2>&1; then
      issues_list="${issues_list}  - SEVERITY=WARN TYPE=enabled_not_installed PLUGIN=${enabled_key}\n"
      issue_count=$((issue_count + 1))
      [ "$check_status" = "OK" ] && check_status="WARN"
    fi
  done <<< "$enabled_keys"

  # Find disabled plugins
  disabled_count=$(jq '[.enabledPlugins // {} | to_entries[] | select(.value == false)] | length' "$user_settings" 2>/dev/null || echo "0")
  if [ "$disabled_count" -gt 0 ]; then
    echo "DISABLED_PLUGINS=${disabled_count}"
    if [ "$verbose_mode" = true ]; then
      jq -r '.enabledPlugins // {} | to_entries[] | select(.value == false) | .key' "$user_settings" 2>/dev/null | while IFS= read -r disabled_name; do
        echo "  DISABLED: ${disabled_name}"
      done
    fi
  fi
fi

# Fix mode: remove orphaned entries
if [ "$fix_mode" = true ] && [ "$orphaned_count" -gt 0 ]; then
  echo "FIX_MODE=true"

  # Create backup
  backup_file="${registry_file}.backup.$(date -u +%Y%m%dT%H%M%SZ)"
  cp "$registry_file" "$backup_file"
  echo "BACKUP_CREATED=${backup_file}"

  # Build jq filter to remove orphaned entries
  jq_filter='.plugins'
  while IFS= read -r plugin_key; do
    [ -z "$plugin_key" ] && continue
    plugin_path=$(jq -r ".plugins[\"${plugin_key}\"][0].projectPath // \"\"" "$registry_file" 2>/dev/null)
    if [ -n "$plugin_path" ] && [ ! -d "$plugin_path" ]; then
      jq_filter="${jq_filter} | del(.\"${plugin_key}\")"
      echo "FIX_REMOVED=${plugin_key}"
    fi
  done <<< "$plugin_keys"

  # Apply fix
  jq ".plugins = (${jq_filter})" "$registry_file" > "${registry_file}.tmp" && mv "${registry_file}.tmp" "$registry_file"
  echo "FIX_APPLIED=true"
  echo "FIX_ORPHANS_REMOVED=${orphaned_count}"
fi

echo "STATUS=${check_status}"
echo "ISSUE_COUNT=${issue_count}"
if [ -n "$issues_list" ]; then
  echo "ISSUES:"
  echo -e "$issues_list" | sed '/^$/d'
fi
echo "FIX_SUPPORTED=true"
echo "=== END PLUGIN REGISTRY ==="
