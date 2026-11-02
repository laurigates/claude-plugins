#!/usr/bin/env bash
# Check Plugin Scope Lag
# Flags project-scope plugin installs whose version is below the user-scope
# version of the same plugin. Such a project keeps loading the old build after
# a user-scope update, so a fix that shipped never reaches it (issue #3220).
# There is no allowlist: every lagging project-scope entry is a WARN.
# Read-only. Exits 0 on OK/WARN, and on a missing registry or missing jq.
# Usage: bash check-plugin-scope-lag.sh --home-dir <path> --project-dir <path> [--verbose]

set -uo pipefail

home_dir=""
project_dir=""

while [ $# -gt 0 ]; do
  case "$1" in
    --home-dir) home_dir="$2"; shift 2 ;;
    --project-dir) project_dir="$2"; shift 2 ;;
    --verbose) shift ;;
    *) shift ;;
  esac
done

: "${home_dir:=$HOME}"
: "${project_dir:=$(pwd)}"

echo "=== PLUGIN SCOPE LAG ==="

registry_file="${home_dir}/.claude/plugins/installed_plugins.json"

finish_ok() {
  echo "STATUS=OK"
  echo "ISSUE_COUNT=0"
  echo "=== END PLUGIN SCOPE LAG ==="
  exit 0
}

if ! command -v jq >/dev/null 2>&1; then
  echo "JQ_AVAILABLE=false"
  finish_ok
fi

if [ ! -f "$registry_file" ]; then
  echo "REGISTRY_EXISTS=false"
  echo "REGISTRY_PATH=${registry_file}"
  finish_ok
fi

echo "REGISTRY_EXISTS=true"
echo "REGISTRY_PATH=${registry_file}"

# One TSV row per project-scope entry that has a user-scope sibling:
# plugin, projectPath, project version, user version.
# tr -d '\r' strips CR line endings jq emits on Windows.
pairs=$(jq -r '
  (.plugins // {}) | to_entries[]
  | .key as $plugin
  | (.value | map(select(.scope == "user")) | .[0].version // empty) as $user_version
  | .value[]
  | select(.scope == "project" and (.version // "") != "")
  | [$plugin, (.projectPath // ""), .version, $user_version] | @tsv
' "$registry_file" 2>/dev/null | tr -d '\r')

compared=0
issue_count=0
issues_list=""
first_reason=""

while IFS=$'\t' read -r plugin_key proj_path proj_version user_version; do
  [ -z "$plugin_key" ] && continue
  compared=$((compared + 1))
  [ "$proj_version" = "$user_version" ] && continue
  # sort -V orders 2.9.0 before 2.10.0; the lower of the two sorts first.
  lowest=$(printf '%s\n%s\n' "$proj_version" "$user_version" | sort -V | head -n1)
  [ "$lowest" = "$proj_version" ] || continue
  issue_count=$((issue_count + 1))
  issues_list="${issues_list}  - SEVERITY=WARN TYPE=scope_lag PLUGIN=${plugin_key} PROJECT=${proj_path} PROJECT_VERSION=${proj_version} USER_VERSION=${user_version} MSG=project-scope install lags user scope\n"
  if [ -z "$first_reason" ]; then
    first_reason="scope_lag: ${plugin_key} at ${proj_version} in ${proj_path}, user scope ${user_version}"
  fi
done <<< "$pairs"

echo "PROJECT_ENTRIES_COMPARED=${compared}"

if [ "$issue_count" -eq 0 ]; then
  finish_ok
fi

reason="${first_reason:0:180}"
[ "$issue_count" -gt 1 ] && reason="${reason} (+$((issue_count - 1)) more)"

echo "STATUS=WARN"
echo "REASON=${reason}"
echo "ISSUE_COUNT=${issue_count}"
echo "ISSUES:"
printf '%b' "$issues_list"
echo "=== END PLUGIN SCOPE LAG ==="
exit 0
