#!/usr/bin/env bash
# Check Marketplace Enrollment (health-check 1e)
# Finds the extraKnownMarketplaces entry in <project>/.claude/settings.json whose
# source.repo equals --repo (default laurigates/claude-plugins). The local key is
# user-chosen (`laurigates-claude-plugins`, `claude-plugins`, ...), so the entry
# is matched by repo, never by key. Then counts enabledPlugins keys ending in
# @<that key> whose value is true.
#   ERROR not_enrolled       no entry names the repo (or no settings file)
#   ERROR invalid_settings   the settings file is not valid JSON
#   WARN  no_enabled_plugins enrolled, but no plugin under it is enabled
# Read-only. Exits 0 on OK/WARN, 1 on ERROR (issue #3579).
# Usage: bash check-marketplace-enrollment.sh --home-dir <path> --project-dir <path> [--repo <owner/name>] [--verbose]

set -uo pipefail

home_dir=""
project_dir=""
marketplace_repo="laurigates/claude-plugins"

while [ $# -gt 0 ]; do
  case "$1" in
    --home-dir) home_dir="$2"; shift 2 ;;
    --project-dir) project_dir="$2"; shift 2 ;;
    --repo) marketplace_repo="$2"; shift 2 ;;
    --verbose) shift ;;
    *) shift ;;
  esac
done

: "${home_dir:=$HOME}"
: "${project_dir:=$(pwd)}"

remedy="run /configure:claude-plugins --fix to add it"

echo "=== MARKETPLACE ENROLLMENT ==="

# finish <status> <type> <msg>: print the summary and the single issue row, exit.
finish() {
  local result_status="$1" issue_type="$2" issue_msg="$3"
  echo "STATUS=${result_status}"
  echo "REASON=${issue_type}: ${issue_msg:0:180}"
  echo "ISSUE_COUNT=1"
  echo "ISSUES:"
  echo "  - SEVERITY=${result_status} TYPE=${issue_type} MSG=${issue_msg}"
  echo "=== END MARKETPLACE ENROLLMENT ==="
  [ "$result_status" = "ERROR" ] && exit 1
  exit 0
}

if ! command -v jq >/dev/null 2>&1; then
  echo "JQ_AVAILABLE=false"
  finish ERROR missing_tool "jq is required but not installed"
fi
echo "JQ_AVAILABLE=true"
echo "MARKETPLACE_REPO=${marketplace_repo}"

settings_file="${project_dir}/.claude/settings.json"
echo "SETTINGS_FILE=${settings_file}"

if [ ! -f "$settings_file" ]; then
  echo "PROJECT_SETTINGS=MISSING"
  finish ERROR not_enrolled "no ${settings_file}, so no extraKnownMarketplaces entry with source.repo=${marketplace_repo}; ${remedy}"
fi

if ! jq -e . "$settings_file" >/dev/null 2>&1; then
  echo "PROJECT_SETTINGS=INVALID"
  finish ERROR invalid_settings "${settings_file} is not valid JSON"
fi
echo "PROJECT_SETTINGS=OK"

# tr -d '\r' strips CR line endings jq emits on Windows. `objects` skips an
# entry whose value (or source) is not an object: indexing a string errors, and
# that error used to hide a valid entry naming the repo (not_enrolled).
mp_key=$(jq -r --arg repo "$marketplace_repo" '
  (.extraKnownMarketplaces // {}) | to_entries
  | map(select((.value | objects | .source | objects | .repo) == $repo)) | .[0].key // empty
' "$settings_file" 2>/dev/null | tr -d '\r')

if [ -z "$mp_key" ]; then
  finish ERROR not_enrolled "no extraKnownMarketplaces entry with source.repo=${marketplace_repo}; ${remedy}"
fi
echo "MARKETPLACE_KEY=${mp_key}"

enabled_count=$(jq -r --arg suffix "@${mp_key}" '
  (.enabledPlugins // {}) | to_entries
  | map(select((.key | endswith($suffix)) and .value == true)) | length
' "$settings_file" 2>/dev/null | tr -d '\r')
enabled_count="${enabled_count:-0}"
echo "ENABLED_PLUGIN_COUNT=${enabled_count}"

if [ "$enabled_count" -eq 0 ]; then
  finish WARN no_enabled_plugins "marketplace ${mp_key} is enrolled but no enabledPlugins key ending in @${mp_key} is true"
fi

echo "STATUS=OK"
echo "ISSUE_COUNT=0"
echo "=== END MARKETPLACE ENROLLMENT ==="
exit 0
