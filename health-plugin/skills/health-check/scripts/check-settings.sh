#!/usr/bin/env bash
# Check Settings Files
# Validates JSON syntax and structure of all Claude Code settings files.
# Usage: bash check-settings.sh --home-dir <path> --project-dir <path> [--verbose]

set -uo pipefail

home_dir=""
project_dir=""
verbose_mode=false

while [ $# -gt 0 ]; do
  case "$1" in
    --home-dir) home_dir="$2"; shift 2 ;;
    --project-dir) project_dir="$2"; shift 2 ;;
    --verbose) verbose_mode=true; shift ;;
    *) shift ;;
  esac
done

: "${home_dir:=$HOME}"
: "${project_dir:=$(pwd)}"

echo "=== SETTINGS FILES ==="

issue_count=0
check_status="OK"

# Check jq availability
if ! command -v jq >/dev/null 2>&1; then
  echo "JQ_AVAILABLE=false"
  echo "STATUS=ERROR"
  echo "ISSUE_COUNT=1"
  echo "ISSUES:"
  echo "  - SEVERITY=ERROR TYPE=missing_tool MSG=jq is required but not installed"
  echo "=== END SETTINGS FILES ==="
  exit 1
fi

echo "JQ_AVAILABLE=true"

# Define settings files to check
declare -A settings_files=(
  ["USER_SETTINGS"]="${home_dir}/.claude/settings.json"
  ["USER_LOCAL_SETTINGS"]="${home_dir}/.claude/settings.local.json"
  ["PROJECT_SETTINGS"]="${project_dir}/.claude/settings.json"
  ["PROJECT_LOCAL_SETTINGS"]="${project_dir}/.claude/settings.local.json"
)

issues_list=""

for settings_key in USER_SETTINGS USER_LOCAL_SETTINGS PROJECT_SETTINGS PROJECT_LOCAL_SETTINGS; do
  settings_file="${settings_files[$settings_key]}"

  if [ ! -f "$settings_file" ]; then
    echo "${settings_key}=MISSING"
    if [ "$verbose_mode" = true ]; then
      echo "${settings_key}_PATH=${settings_file}"
    fi
    continue
  fi

  # Validate JSON syntax
  json_error=$(jq empty "$settings_file" 2>&1)
  if [ $? -ne 0 ]; then
    echo "${settings_key}=INVALID"
    echo "${settings_key}_ERROR=${json_error}"
    issues_list="${issues_list}  - SEVERITY=ERROR TYPE=invalid_json FILE=${settings_file} MSG=${json_error}\n"
    issue_count=$((issue_count + 1))
    check_status="ERROR"
    continue
  fi

  echo "${settings_key}=OK"

  if [ "$verbose_mode" = true ]; then
    echo "${settings_key}_PATH=${settings_file}"

    # Count permission patterns if present
    allow_count=$(jq -r '.permissions.allow // [] | length' "$settings_file" 2>/dev/null || echo "0")
    deny_count=$(jq -r '.permissions.deny // [] | length' "$settings_file" 2>/dev/null || echo "0")
    echo "${settings_key}_ALLOW_PATTERNS=${allow_count}"
    echo "${settings_key}_DENY_PATTERNS=${deny_count}"

    # Count hooks if present
    hook_count=$(jq -r '.hooks // {} | length' "$settings_file" 2>/dev/null || echo "0")
    echo "${settings_key}_HOOKS=${hook_count}"

    # Count enabled plugins if present
    plugin_count=$(jq -r '.enabledPlugins // {} | length' "$settings_file" 2>/dev/null || echo "0")
    echo "${settings_key}_ENABLED_PLUGINS=${plugin_count}"
  fi
done

# Check for permission conflicts (allow and deny same pattern)
user_settings="${home_dir}/.claude/settings.json"
project_settings="${project_dir}/.claude/settings.json"

for sf in "$user_settings" "$project_settings"; do
  if [ -f "$sf" ]; then
    allow_patterns=$(jq -r '.permissions.allow // [] | .[]' "$sf" 2>/dev/null)
    deny_patterns=$(jq -r '.permissions.deny // [] | .[]' "$sf" 2>/dev/null)

    if [ -n "$allow_patterns" ] && [ -n "$deny_patterns" ]; then
      while IFS= read -r pattern; do
        if echo "$deny_patterns" | grep -qxF "$pattern"; then
          issues_list="${issues_list}  - SEVERITY=WARN TYPE=permission_conflict FILE=${sf} PATTERN=${pattern}\n"
          issue_count=$((issue_count + 1))
          [ "$check_status" = "OK" ] && check_status="WARN"
        fi
      done <<< "$allow_patterns"
    fi
  fi
done

# Aggregate permission counts across all files
total_allow=0
total_deny=0
for sf in "$user_settings" "${home_dir}/.claude/settings.local.json" "$project_settings" "${project_dir}/.claude/settings.local.json"; do
  if [ -f "$sf" ]; then
    ac=$(jq -r '.permissions.allow // [] | length' "$sf" 2>/dev/null || echo "0")
    dc=$(jq -r '.permissions.deny // [] | length' "$sf" 2>/dev/null || echo "0")
    total_allow=$((total_allow + ac))
    total_deny=$((total_deny + dc))
  fi
done
echo "TOTAL_ALLOW_PATTERNS=${total_allow}"
echo "TOTAL_DENY_PATTERNS=${total_deny}"

echo "STATUS=${check_status}"
echo "ISSUE_COUNT=${issue_count}"
if [ -n "$issues_list" ]; then
  echo "ISSUES:"
  echo -e "$issues_list" | sed '/^$/d'
fi
echo "=== END SETTINGS FILES ==="
