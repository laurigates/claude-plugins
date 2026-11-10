#!/usr/bin/env bash
# Read or edit the enabledPlugins setting for the health-audit skill
# (user entry point: /health:check --scope=stack).
#
# enabledPlugins is an OBJECT mapping "plugin-name@marketplace-name" to a
# boolean (true = enabled, false = explicitly disabled), not an array of
# names. Iterating its values with jq's `[]` yields the bare booleans, so
# every read and write here goes through to_entries.
# Source: https://code.claude.com/docs/en/settings-reference#enabledplugins
#
# Usage:
#   enabled-plugins.sh list  [--home-dir <path>] [--project-dir <path>]
#   enabled-plugins.sh apply --settings <file> [--enable <id>]... [--remove <id>]...
#
# list   Reads user (~/.claude/settings.json), project (.claude/settings.json)
#        and local (.claude/settings.local.json) settings and prints the
#        enabled and disabled IDs per scope, plus EFFECTIVE_ENABLED: the IDs
#        whose highest-precedence entry is true (local > project > user).
#        Managed settings are not read.
# apply  Sets each --enable ID to true and deletes each --remove ID from one
#        settings file, keeping every other key. Backs the file up to
#        <file>.backup first; creates the file when it does not exist.
#
# Output follows .claude/rules/structured-script-output.md. Exit 0 on OK/WARN,
# 1 on ERROR, 2 on a usage error.

set -uo pipefail

# Read filters. The regression test extracts these assignments verbatim and
# runs them against a fixture, so keep each on one line.
FILTER_ENABLED='(.enabledPlugins // {}) | to_entries[] | select(.value == true) | .key'
FILTER_DISABLED='(.enabledPlugins // {}) | to_entries[] | select(.value == false) | .key'
FILTER_TYPE='.enabledPlugins | type'

ep_usage() {
  echo "usage: enabled-plugins.sh list [--home-dir <path>] [--project-dir <path>]" >&2
  echo "       enabled-plugins.sh apply --settings <file> [--enable <id>]... [--remove <id>]..." >&2
  exit 2
}

ep_mode="${1:-}"
[ -n "$ep_mode" ] || ep_usage
shift

ep_home_dir=""
ep_project_dir=""
ep_settings=""
ep_enable=()
ep_remove=()

while [ $# -gt 0 ]; do
  case "$1" in
    --home-dir) [ $# -ge 2 ] || ep_usage; ep_home_dir="$2"; shift 2 ;;
    --project-dir) [ $# -ge 2 ] || ep_usage; ep_project_dir="$2"; shift 2 ;;
    --settings) [ $# -ge 2 ] || ep_usage; ep_settings="$2"; shift 2 ;;
    --enable) [ $# -ge 2 ] || ep_usage; ep_enable+=("$2"); shift 2 ;;
    --remove) [ $# -ge 2 ] || ep_usage; ep_remove+=("$2"); shift 2 ;;
    *) echo "unknown argument: $1" >&2; ep_usage ;;
  esac
done

: "${ep_home_dir:=${HOME:-}}"
: "${ep_project_dir:=.}"

ep_issue_count=0
ep_status="OK"
ep_reason=""
ep_issues=""

# ep_add_issue SEVERITY TYPE MSG [EXTRA]
ep_add_issue() {
  ep_issue_count=$((ep_issue_count + 1))
  ep_issues="${ep_issues}  - SEVERITY=$1 TYPE=$2${4:+ $4} MSG=$3"$'\n'
  if [ "$1" = "ERROR" ] && [ "$ep_status" != "ERROR" ]; then
    ep_status="ERROR"
    ep_reason="$2: $3"
  elif [ "$1" = "WARN" ] && [ "$ep_status" = "OK" ]; then
    ep_status="WARN"
    ep_reason="$2: $3"
  fi
}

# ep_finish SECTION — print the status block and exit with the matching code.
ep_finish() {
  echo "STATUS=${ep_status}"
  if [ "$ep_status" != "OK" ]; then
    local ep_more=""
    [ "$ep_issue_count" -gt 1 ] && ep_more=" (+$((ep_issue_count - 1)) more)"
    echo "REASON=${ep_reason:0:180}${ep_more}"
  fi
  echo "ISSUE_COUNT=${ep_issue_count}"
  if [ "$ep_issue_count" -gt 0 ]; then
    echo "ISSUES:"
    printf '%s' "$ep_issues"
  fi
  echo "=== END $1 ==="
  [ "$ep_status" = "ERROR" ] && exit 1
  exit 0
}

ep_require_jq() {
  if ! command -v jq >/dev/null 2>&1; then
    echo "JQ_AVAILABLE=false"
    ep_add_issue ERROR missing_tool "jq is required but not installed"
    ep_finish "$1"
  fi
  echo "JQ_AVAILABLE=true"
}

# ep_valid_id ID — "plugin-name@marketplace-name", one @, no whitespace.
ep_valid_id() {
  [[ "$1" =~ ^[^@[:space:]]+@[^@[:space:]]+$ ]]
}

ep_list() {
  local ep_section="ENABLED PLUGINS"
  echo "=== ${ep_section} ==="
  ep_require_jq "$ep_section"

  local ep_scope ep_file ep_type ep_label ep_id
  local ep_effective_inputs=()
  for ep_scope in user project local; do
    case "$ep_scope" in
      user) ep_file="${ep_home_dir}/.claude/settings.json" ;;
      project) ep_file="${ep_project_dir}/.claude/settings.json" ;;
      local) ep_file="${ep_project_dir}/.claude/settings.local.json" ;;
    esac
    ep_label=$(printf '%s' "$ep_scope" | tr '[:lower:]' '[:upper:]')

    if [ ! -f "$ep_file" ]; then
      echo "${ep_label}_SETTINGS=MISSING"
      ep_effective_inputs+=('{}')
      continue
    fi
    if ! jq -e 'type == "object"' "$ep_file" >/dev/null 2>&1; then
      echo "${ep_label}_SETTINGS=INVALID"
      ep_add_issue ERROR invalid_json "${ep_scope} settings is not a JSON object" "FILE=${ep_file}"
      ep_effective_inputs+=('{}')
      continue
    fi
    echo "${ep_label}_SETTINGS=OK"

    ep_type=$(jq -r "$FILTER_TYPE" "$ep_file")
    case "$ep_type" in
      null)
        ep_effective_inputs+=('{}')
        continue
        ;;
      object) ;;
      *)
        ep_add_issue WARN not_object "${ep_scope} enabledPlugins is a ${ep_type}, expected an object of id to boolean" "FILE=${ep_file}"
        ep_effective_inputs+=('{}')
        continue
        ;;
    esac

    if jq -e '.enabledPlugins | to_entries | any(.value | type != "boolean")' "$ep_file" >/dev/null 2>&1; then
      ep_add_issue WARN non_boolean_value "${ep_scope} enabledPlugins has a non-boolean value; ignored" "FILE=${ep_file}"
    fi

    while IFS= read -r ep_id; do
      [ -n "$ep_id" ] && echo "${ep_label}_ENABLED=${ep_id}"
    done < <(jq -r "$FILTER_ENABLED" "$ep_file")
    while IFS= read -r ep_id; do
      [ -n "$ep_id" ] && echo "${ep_label}_DISABLED=${ep_id}"
    done < <(jq -r "$FILTER_DISABLED" "$ep_file")

    ep_effective_inputs+=("$(jq -c '.enabledPlugins | with_entries(select(.value | type == "boolean"))' "$ep_file")")
  done

  # Later objects win on a shared key: user, then project, then local.
  while IFS= read -r ep_id; do
    [ -n "$ep_id" ] && echo "EFFECTIVE_ENABLED=${ep_id}"
  done < <(printf '%s\n' "${ep_effective_inputs[@]}" \
    | jq -rs 'add | to_entries[] | select(.value == true) | .key')

  ep_finish "$ep_section"
}

ep_apply() {
  local ep_section="APPLY ENABLED PLUGINS"
  echo "=== ${ep_section} ==="
  [ -n "$ep_settings" ] || ep_usage
  ep_require_jq "$ep_section"
  echo "SETTINGS_FILE=${ep_settings}"

  local ep_id
  for ep_id in "${ep_enable[@]+"${ep_enable[@]}"}" "${ep_remove[@]+"${ep_remove[@]}"}"; do
    if ! ep_valid_id "$ep_id"; then
      ep_add_issue ERROR invalid_id "'${ep_id}' is not plugin-name@marketplace-name"
    fi
  done
  [ "$ep_status" = "ERROR" ] && ep_finish "$ep_section"

  if [ -f "$ep_settings" ]; then
    if ! jq -e 'type == "object"' "$ep_settings" >/dev/null 2>&1; then
      ep_add_issue ERROR invalid_json "settings file is not a JSON object; left unchanged"
      ep_finish "$ep_section"
    fi
    if ! jq -e '(.enabledPlugins // {}) | type == "object"' "$ep_settings" >/dev/null 2>&1; then
      ep_add_issue ERROR not_object "enabledPlugins is not an object; fix it by hand before --fix"
      ep_finish "$ep_section"
    fi
    if ! cp "$ep_settings" "${ep_settings}.backup"; then
      ep_add_issue ERROR backup_failed "could not write ${ep_settings}.backup"
      ep_finish "$ep_section"
    fi
    echo "BACKUP=${ep_settings}.backup"
    echo "CREATED=false"
  else
    if ! mkdir -p "$(dirname "$ep_settings")" || ! printf '{}\n' >"$ep_settings"; then
      ep_add_issue ERROR create_failed "could not create ${ep_settings}"
      ep_finish "$ep_section"
    fi
    echo "CREATED=true"
  fi

  for ep_id in "${ep_remove[@]+"${ep_remove[@]}"}"; do
    if ! jq -e --arg id "$ep_id" '(.enabledPlugins // {}) | has($id)' "$ep_settings" >/dev/null 2>&1; then
      ep_add_issue WARN not_present "${ep_id} has no entry to remove" "ID=${ep_id}"
    fi
  done

  local ep_enable_json ep_remove_json ep_tmp
  ep_enable_json=$(printf '%s\n' "${ep_enable[@]+"${ep_enable[@]}"}" | jq -Rsc 'split("\n") | map(select(length > 0))')
  ep_remove_json=$(printf '%s\n' "${ep_remove[@]+"${ep_remove[@]}"}" | jq -Rsc 'split("\n") | map(select(length > 0))')

  ep_tmp=$(mktemp "${ep_settings}.XXXXXX") || {
    ep_add_issue ERROR write_failed "could not create a temp file beside ${ep_settings}"
    ep_finish "$ep_section"
  }
  if ! jq --argjson en "$ep_enable_json" --argjson rm "$ep_remove_json" '
      .enabledPlugins = ((.enabledPlugins // {})
        + ($en | map({key: ., value: true}) | from_entries)
        | with_entries(select(.key as $k | $rm | index($k) | not)))
      | if .enabledPlugins == {} then del(.enabledPlugins) else . end
    ' "$ep_settings" >"$ep_tmp" || ! jq -e 'type == "object"' "$ep_tmp" >/dev/null 2>&1; then
    rm -f "$ep_tmp"
    ep_add_issue ERROR write_failed "jq could not produce valid JSON; settings left unchanged"
    ep_finish "$ep_section"
  fi
  mv "$ep_tmp" "$ep_settings"

  for ep_id in "${ep_enable[@]+"${ep_enable[@]}"}"; do echo "ENABLED=${ep_id}"; done
  for ep_id in "${ep_remove[@]+"${ep_remove[@]}"}"; do echo "REMOVED=${ep_id}"; done
  ep_finish "$ep_section"
}

case "$ep_mode" in
  list) ep_list ;;
  apply) ep_apply ;;
  -h|--help) ep_usage ;;
  *) echo "unknown mode: ${ep_mode}" >&2; ep_usage ;;
esac
