#!/usr/bin/env bash
# Diagnose Claude Code plugin registry
# Detects orphaned projectPath entries, scope conflicts, and invalid entries
# in ~/.claude/plugins/installed_plugins.json.
# Usage:
#   bash check-registry.sh --home-dir <path> --project-dir <path> [--plugin <name>] [--verbose]

set -uo pipefail

home_dir=""
project_dir=""
target_plugin=""
verbose_mode=false

while [ $# -gt 0 ]; do
  case "$1" in
    --home-dir) home_dir="$2"; shift 2 ;;
    --project-dir) project_dir="$2"; shift 2 ;;
    --plugin) target_plugin="$2"; shift 2 ;;
    --verbose) verbose_mode=true; shift ;;
    *) shift ;;
  esac
done

: "${home_dir:=$HOME}"
: "${project_dir:=$(pwd)}"

echo "=== PLUGIN REGISTRY DIAGNOSTIC ==="
echo "HOME_DIR=${home_dir}"
echo "PROJECT_DIR=${project_dir}"

registry_file="${home_dir}/.claude/plugins/installed_plugins.json"
user_settings="${home_dir}/.claude/settings.json"

if ! command -v jq >/dev/null 2>&1; then
  echo "JQ_AVAILABLE=false"
  echo "STATUS=ERROR"
  echo "ISSUE_COUNT=1"
  echo "ISSUES:"
  echo "  - SEVERITY=ERROR TYPE=missing_tool MSG=jq is required but not installed"
  echo "=== END PLUGIN REGISTRY DIAGNOSTIC ==="
  exit 1
fi

if [ ! -f "$registry_file" ]; then
  echo "REGISTRY_EXISTS=false"
  echo "REGISTRY_PATH=${registry_file}"
  echo "STATUS=WARN"
  echo "ISSUE_COUNT=1"
  echo "ISSUES:"
  echo "  - SEVERITY=WARN TYPE=missing_registry MSG=Plugin registry file not found"
  echo "=== END PLUGIN REGISTRY DIAGNOSTIC ==="
  exit 0
fi

echo "REGISTRY_EXISTS=true"
echo "REGISTRY_PATH=${registry_file}"

json_error=$(jq empty "$registry_file" 2>&1)
json_rc=$?
if [ $json_rc -ne 0 ]; then
  echo "REGISTRY_VALID=false"
  echo "STATUS=ERROR"
  echo "ISSUE_COUNT=1"
  echo "ISSUES:"
  echo "  - SEVERITY=ERROR TYPE=invalid_json MSG=${json_error}"
  echo "=== END PLUGIN REGISTRY DIAGNOSTIC ==="
  exit 1
fi

echo "REGISTRY_VALID=true"

plugin_count=$(jq '.plugins | length' "$registry_file" 2>/dev/null || echo "0")
echo "PLUGIN_COUNT=${plugin_count}"

issue_count=0
check_status="OK"
issues_list=""
project_scoped=0
global_scoped=0
orphaned_count=0
other_project_count=0

if [ -n "$target_plugin" ]; then
  plugin_keys=$(jq -r --arg k "$target_plugin" '.plugins | keys[] | select(. == $k or startswith($k + "@"))' "$registry_file" 2>/dev/null)
else
  plugin_keys=$(jq -r '.plugins | keys[]' "$registry_file" 2>/dev/null)
fi

echo "=== PLUGINS ==="
while IFS= read -r plugin_key; do
  [ -z "$plugin_key" ] && continue

  plugin_path=$(jq -r --arg k "$plugin_key" '.plugins[$k][0].projectPath // ""' "$registry_file" 2>/dev/null)
  plugin_source=$(jq -r --arg k "$plugin_key" '.plugins[$k][0].source // "unknown"' "$registry_file" 2>/dev/null)
  plugin_scope=$(jq -r --arg k "$plugin_key" '.plugins[$k][0].scope // "user"' "$registry_file" 2>/dev/null)
  plugin_version=$(jq -r --arg k "$plugin_key" '.plugins[$k][0].version // "unknown"' "$registry_file" 2>/dev/null)

  if [ -n "$plugin_path" ]; then
    project_scoped=$((project_scoped + 1))
    if [ ! -d "$plugin_path" ]; then
      orphaned_count=$((orphaned_count + 1))
      issues_list="${issues_list}  - SEVERITY=WARN TYPE=orphaned PLUGIN=${plugin_key} PATH=${plugin_path} FIX=remove_entry\n"
      issue_count=$((issue_count + 1))
      [ "$check_status" = "OK" ] && check_status="WARN"
    elif [ "$plugin_path" != "$project_dir" ]; then
      other_project_count=$((other_project_count + 1))
      if [ "$verbose_mode" = true ]; then
        issues_list="${issues_list}  - SEVERITY=INFO TYPE=different_project PLUGIN=${plugin_key} PATH=${plugin_path}\n"
      fi
    fi
  else
    global_scoped=$((global_scoped + 1))
  fi

  echo "PLUGIN: name=${plugin_key} scope=${plugin_scope} version=${plugin_version} source=${plugin_source} projectPath=${plugin_path:-none}"
done <<< "$plugin_keys"
echo "=== END PLUGINS ==="

echo "PROJECT_SCOPED=${project_scoped}"
echo "GLOBAL_SCOPED=${global_scoped}"
echo "ORPHANED_ENTRIES=${orphaned_count}"
echo "OTHER_PROJECT_ENTRIES=${other_project_count}"

stale_enabled_count=0
if [ -f "$user_settings" ]; then
  enabled_count=$(jq '.enabledPlugins // {} | length' "$user_settings" 2>/dev/null || echo "0")
  echo "ENABLED_IN_SETTINGS=${enabled_count}"

  # Collect marketplace plugin names (if any marketplaces are configured).
  marketplace_names=""
  marketplaces_dir="${home_dir}/.claude/plugins/marketplaces"
  if [ -d "$marketplaces_dir" ]; then
    while IFS= read -r mp_file; do
      [ -z "$mp_file" ] && continue
      mp_plugins=$(jq -r '.plugins[]?.name // empty' "$mp_file" 2>/dev/null)
      marketplace_names="${marketplace_names}
${mp_plugins}"
    done < <(find "$marketplaces_dir" -maxdepth 3 -name '*.json' -type f 2>/dev/null)
  fi

  enabled_keys=$(jq -r '.enabledPlugins // {} | keys[]' "$user_settings" 2>/dev/null)
  while IFS= read -r enabled_key; do
    [ -z "$enabled_key" ] && continue

    # enabledPlugins keys are of the form "<plugin>@<marketplace>"; the registry
    # is keyed the same way but older Claude Code versions left stale entries
    # behind when the plugin or marketplace was removed.
    plugin_name="${enabled_key%@*}"

    # Present in registry?
    if jq -e --arg k "$enabled_key" '.plugins[$k]' "$registry_file" >/dev/null 2>&1; then
      continue
    fi

    # Present in any known marketplace?
    if [ -n "$marketplace_names" ] && printf '%s\n' "$marketplace_names" | grep -Fxq "$plugin_name"; then
      issues_list="${issues_list}  - SEVERITY=WARN TYPE=enabled_not_installed PLUGIN=${enabled_key}\n"
      issue_count=$((issue_count + 1))
      [ "$check_status" = "OK" ] && check_status="WARN"
      continue
    fi

    # Neither installed nor in any marketplace -- fully stale.
    stale_enabled_count=$((stale_enabled_count + 1))
    issues_list="${issues_list}  - SEVERITY=WARN TYPE=stale_enabled PLUGIN=${enabled_key} FIX=remove_enabled_key\n"
    issue_count=$((issue_count + 1))
    [ "$check_status" = "OK" ] && check_status="WARN"
  done <<< "$enabled_keys"
fi
echo "STALE_ENABLED_ENTRIES=${stale_enabled_count}"

echo "STATUS=${check_status}"
echo "ISSUE_COUNT=${issue_count}"
if [ -n "$issues_list" ]; then
  echo "ISSUES:"
  echo -e "$issues_list" | sed '/^$/d'
fi
echo "FIX_SUPPORTED=true"
echo "=== END PLUGIN REGISTRY DIAGNOSTIC ==="
