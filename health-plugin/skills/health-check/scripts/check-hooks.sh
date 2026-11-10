#!/usr/bin/env bash
# shellcheck disable=SC2016  # literal ${CLAUDE_*} patterns and jq programs are single-quoted on purpose
# Check Hooks Configuration
# Inventories every hook Claude Code loads for this project and validates it:
#   - settings hooks: user, project and local settings files
#   - plugin hooks: each installed plugin that is enabled here (enabledPlugins,
#     or its manifest defaultEnabled when no scope sets it), read from the one
#     install of it that loads here (installed_plugins.json), via its default
#     hooks/hooks.json and the plugin.json "hooks" field
# Each handler is checked for a documented event name, a documented `type`, a
# resolvable command (for `bash <script>`, the script must exist), and a sane
# timeout.
#
# Output keys: HOOKS_CONFIGURED, HOOK_COUNT (settings + plugin handlers),
# SETTINGS_HOOK_COUNT, PLUGIN_HOOK_COUNT, PLUGINS_ENABLED (enabled plugins with
# an install on disk, scanned for hooks; same definition as check-usage.sh),
# PLUGINS_UNRESOLVED (set to true but no install for this project), STATUS (OK|WARN|ERROR, or N_A when nothing is configured
# and nothing is wrong), REASON (WARN/ERROR only), ISSUE_COUNT, ISSUES.
# Exit 0 on OK/WARN/N_A, 1 on ERROR (jq missing).
#
# Usage: bash check-hooks.sh --home-dir <path> --project-dir <path> [--verbose]
#
# Kept bash-3.2 safe (no associative arrays, no mapfile): an agent subshell
# can start with a /usr/bin:/bin PATH, where `bash` is macOS's 3.2.

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

# Documented hook events and handler types. Source:
# https://code.claude.com/docs/en/hooks (hook events table and handler `type`
# field), read 2026-11-10 against Claude Code 2.1.322. Refresh both arrays from
# that page when Claude Code adds an event or a handler type; an event missing
# here is reported as unknown_event. Claude Code skips an unknown event name
# with a "Settings Warning" (https://code.claude.com/docs/en/settings), so
# such a hook never fires.
VALID_HOOK_EVENTS=(
  SessionStart Setup UserPromptSubmit UserPromptExpansion PreToolUse
  PermissionRequest PermissionDenied PostToolUse PostToolUseFailure
  PostToolBatch Notification MessageDisplay SubagentStart SubagentStop
  TaskCreated TaskCompleted Stop StopFailure TeammateIdle InstructionsLoaded
  ConfigChange CwdChanged DirectoryAdded FileChanged WorktreeCreate
  WorktreeRemove PreCompact PostCompact PreModelSwitch PostModelSwitch
  Elicitation ElicitationResult SessionEnd
)
VALID_HOOK_TYPES=(command http mcp_tool prompt agent)

# Hook timeouts are SECONDS (docs: "Seconds before canceling").
# - MS_TIMEOUT_MIN and above is ms_timeout: a millisecond figure written as
#   seconds (same threshold and TYPE as scripts/check-hook-timeout-units.sh,
#   which flags `value > 999`).
# - Above the event's limit is high_timeout. Hooks on per-turn and per-tool
#   events block the session while they run, so the limit is
#   HIGH_TIMEOUT_SECONDS. Events in SETUP_EVENTS run installs once per session
#   or per init, and .claude/rules/sandbox-guidance.md recommends 120-300 s for
#   multi-tool installs and full-stack setup, so their limit is
#   SETUP_HIGH_TIMEOUT_SECONDS.
HIGH_TIMEOUT_SECONDS=60
SETUP_HIGH_TIMEOUT_SECONDS=300
SETUP_EVENTS=(SessionStart Setup)
MS_TIMEOUT_MIN=1000

# Field separator for jq -> bash rows. Not whitespace, so `read` keeps empty
# fields (a tab IFS collapses consecutive separators and shifts the columns).
FS=$'\x1f'

echo "=== HOOKS CONFIGURATION ==="

if ! command -v jq >/dev/null 2>&1; then
  echo "JQ_AVAILABLE=false"
  echo "STATUS=ERROR"
  echo "REASON=missing_tool: jq is required but not installed"
  echo "ISSUE_COUNT=1"
  echo "ISSUES:"
  echo "  - SEVERITY=ERROR TYPE=missing_tool MSG=jq is required but not installed"
  echo "=== END HOOKS CONFIGURATION ==="
  exit 1
fi

issue_count=0
issues_rows=""
first_reason=""
settings_hook_count=0
plugin_hook_count=0

in_list() {
  local needle="$1"; shift
  local item
  for item in "$@"; do
    [ "$item" = "$needle" ] && return 0
  done
  return 1
}

# add_issue <TYPE> <key=value fields> <MSG>. Every finding is a WARN.
add_issue() {
  local issue_type="$1" fields="$2" msg="$3"
  issues_rows="${issues_rows}  - SEVERITY=WARN TYPE=${issue_type} ${fields} MSG=${msg}"$'\n'
  issue_count=$((issue_count + 1))
  [ -z "$first_reason" ] && first_reason="${issue_type}: ${msg}"
}

# replace_all <string> <literal pattern> <replacement> (bash-3.2 safe; a
# ${s//pat/rep} replacement is quote- and &-sensitive across bash versions).
replace_all() {
  local s="$1" pat="$2" rep="$3" out=""
  while [[ "$s" == *"$pat"* ]]; do
    out="${out}${s%%"$pat"*}${rep}"
    s="${s#*"$pat"}"
  done
  printf '%s' "${out}${s}"
}

# One row per event key (E) and per handler (H) of an event map.
EXTRACT_JQ='
  def clean: tostring | gsub("[\n\r\u001f]"; " ");
  if type != "object" then empty else
    (keys_unsorted[] | ["E", .] | join("\u001f")),
    (to_entries[] | .key as $ev
      | (.value | if type == "array" then .[] else empty end)
      | select(type == "object")
      | ((.matcher // "*") | clean) as $m
      | (.hooks // [] | if type == "array" then .[] else empty end)
      | select(type == "object")
      | ["H", $ev, $m,
         ((.type // "") | clean),
         ((.command // "") | clean),
         (if has("timeout") and .timeout != null then (.timeout | clean) else "default" end)]
      | join("\u001f"))
  end'

# check_command <command> <plugin_root>: warn when the command's first word is
# neither on PATH nor an existing file. ${CLAUDE_PLUGIN_ROOT} and
# ${CLAUDE_PROJECT_DIR} are expanded first (Claude Code substitutes them in hook
# commands); a word still holding `$` cannot be resolved here, so skip it.
# When the first word is an interpreter (bash, sh, zsh), the script it runs is
# the thing that can go missing, so the first non-flag argument is checked
# instead: an absolute path must exist. `-c` runs an inline script, and a
# relative path resolves against a cwd this check cannot know, so both skip.
check_command() {
  local hook_command="$1" plugin_root="$2" event_name="$3" file_label="$4" source_label="$5"
  local expanded="$hook_command" base_tool script_arg word
  local -a words
  if [ -n "$plugin_root" ]; then
    expanded=$(replace_all "$expanded" '${CLAUDE_PLUGIN_ROOT}' "$plugin_root")
    expanded=$(replace_all "$expanded" '$CLAUDE_PLUGIN_ROOT' "$plugin_root")
  fi
  expanded=$(replace_all "$expanded" '${CLAUDE_PROJECT_DIR}' "$project_dir")
  expanded=$(replace_all "$expanded" '$CLAUDE_PROJECT_DIR' "$project_dir")
  read -r -a words <<<"$(tr -d "\"'" <<<"$expanded")"
  [ "${#words[@]}" -eq 0 ] && return 0
  base_tool="${words[0]}"
  [[ "$base_tool" == *'$'* ]] && return 0
  case "$base_tool" in
    bash|sh|zsh|*/bash|*/sh|*/zsh)
      script_arg=""
      for word in "${words[@]:1}"; do
        case "$word" in
          -c) return 0 ;;
          -*) continue ;;
          *) script_arg="$word"; break ;;
        esac
      done
      [ -z "$script_arg" ] && return 0
      [[ "$script_arg" == *'$'* ]] && return 0
      [[ "$script_arg" == /* ]] || return 0
      [ -f "$script_arg" ] && return 0
      add_issue missing_command "EVENT=${event_name} COMMAND=${script_arg} FILE=${file_label} SOURCE=${source_label}" "hook script not found on disk"
      return 0
      ;;
  esac
  command -v "$base_tool" >/dev/null 2>&1 && return 0
  [ -f "$base_tool" ] && return 0
  add_issue missing_command "EVENT=${event_name} COMMAND=${base_tool} FILE=${file_label} SOURCE=${source_label}" "hook command not found on PATH or disk"
}

check_timeout() {
  local hook_timeout="$1" event_name="$2" file_label="$3" source_label="$4"
  local limit="$HIGH_TIMEOUT_SECONDS"
  in_list "$event_name" "${SETUP_EVENTS[@]}" && limit="$SETUP_HIGH_TIMEOUT_SECONDS"
  # Non-integer values fail the -ge/-gt tests silently and are skipped.
  if [ "$hook_timeout" -ge "$MS_TIMEOUT_MIN" ] 2>/dev/null; then
    add_issue ms_timeout "EVENT=${event_name} TIMEOUT=${hook_timeout}s FILE=${file_label} SOURCE=${source_label}" "hook timeouts are seconds; this reads as milliseconds, divide by 1000"
  elif [ "$hook_timeout" -gt "$limit" ] 2>/dev/null; then
    add_issue high_timeout "EVENT=${event_name} TIMEOUT=${hook_timeout}s LIMIT=${limit}s FILE=${file_label} SOURCE=${source_label}" "timeout above the ${limit}s limit for ${event_name} hooks"
  fi
}

# scan_event_map <source_label> <file_label> <plugin_root> <event-map JSON>
# source_label is `settings` or `plugin:<name@marketplace>`.
scan_event_map() {
  local source_label="$1" file_label="$2" plugin_root="$3" map_json="$4"
  local rows kind event_name hook_matcher hook_type hook_command hook_timeout
  rows=$(jq -r "$EXTRACT_JQ" <<<"$map_json" 2>/dev/null | tr -d '\r')
  [ -z "$rows" ] && return 0
  while IFS="$FS" read -r kind event_name hook_matcher hook_type hook_command hook_timeout; do
    case "$kind" in
      E)
        if ! in_list "$event_name" "${VALID_HOOK_EVENTS[@]}"; then
          add_issue unknown_event "EVENT=${event_name} FILE=${file_label} SOURCE=${source_label}" "not a documented hook event; Claude Code skips it, so its hooks never fire"
        fi
        ;;
      H)
        if [ "$source_label" = "settings" ]; then
          settings_hook_count=$((settings_hook_count + 1))
        else
          plugin_hook_count=$((plugin_hook_count + 1))
        fi
        if [ "$verbose_mode" = true ]; then
          echo "HOOK: event=${event_name} matcher=${hook_matcher} type=${hook_type:-<missing>} timeout=${hook_timeout} source=${source_label} file=${file_label}"
          [ -n "$hook_command" ] && echo "  COMMAND=${hook_command}"
        fi
        if ! in_list "$hook_type" "${VALID_HOOK_TYPES[@]}"; then
          add_issue unknown_hook_type "EVENT=${event_name} HOOK_TYPE=${hook_type:-<missing>} FILE=${file_label} SOURCE=${source_label}" "hook type is not one of: ${VALID_HOOK_TYPES[*]}"
        fi
        if [ "$hook_type" = "command" ] && [ -n "$hook_command" ]; then
          check_command "$hook_command" "$plugin_root" "$event_name" "$file_label" "$source_label"
        fi
        [ "$hook_timeout" != "default" ] && check_timeout "$hook_timeout" "$event_name" "$file_label" "$source_label"
        ;;
    esac
  done <<<"$rows"
}

# scan_hooks_file <source_label> <file> <plugin_root>: a hooks file wraps the
# event map in a top-level "hooks" key (plugins reference: a file holding only
# the event map fails to load).
scan_hooks_file() {
  local source_label="$1" hooks_file="$2" plugin_root="$3" map_json
  if ! map_json=$(jq -ce 'if type == "object" and (.hooks | type) == "object" then .hooks else error("unwrapped") end' "$hooks_file" 2>/dev/null); then
    add_issue invalid_hooks_file "FILE=${hooks_file} SOURCE=${source_label}" "not valid JSON with a top-level \"hooks\" object, so Claude Code cannot load it"
    return 0
  fi
  scan_event_map "$source_label" "$hooks_file" "$plugin_root" "$map_json"
}

# --- Settings hooks ---------------------------------------------------------
# ~/.claude/settings.local.json is local scope for the home directory, so Claude
# Code reads it only in a session started in the home directory itself
# (https://code.claude.com/docs/en/permissions, "When your local settings file
# needs trust"). With --project-dir == --home-dir it is the project local file.
settings_files=(
  "${home_dir}/.claude/settings.json"
  "${project_dir}/.claude/settings.json"
  "${project_dir}/.claude/settings.local.json"
)

for settings_file in "${settings_files[@]}"; do
  [ -f "$settings_file" ] || continue
  settings_map=$(jq -c '.hooks // empty' "$settings_file" 2>/dev/null)
  [ -z "$settings_map" ] && continue
  scan_event_map "settings" "$settings_file" "" "$settings_map"
done

# --- Plugin hooks -----------------------------------------------------------
# enabledPlugins merges by settings precedence (local > project > user,
# https://code.claude.com/docs/en/settings), so a later file's value for a
# plugin overrides an earlier one. Every installed plugin is a candidate
# (installed_plugins.json); it is dropped when the merged value is `false`, or
# when it has no entry at any scope and its manifest sets
# `defaultEnabled: false` (settings reference § enabledPlugins: a plugin with no
# entry falls back to its defaultEnabled value, default true). This is the same
# rule check-usage.sh applies, so both report the same PLUGINS_ENABLED.
enabled_sources=(
  "${home_dir}/.claude/settings.json"
  "${project_dir}/.claude/settings.json"
  "${project_dir}/.claude/settings.local.json"
)
enabled_objects=""
for settings_file in "${enabled_sources[@]}"; do
  [ -f "$settings_file" ] || continue
  obj=$(jq -c '(.enabledPlugins // {}) | if type == "object" then . else {} end' "$settings_file" 2>/dev/null)
  [ -n "$obj" ] && enabled_objects="${enabled_objects}${obj}"$'\n'
done
merged_enabled='{}'
if [ -n "$enabled_objects" ]; then
  merged_enabled=$(jq -cs 'reduce .[] as $o ({}; . + $o)' <<<"$enabled_objects" 2>/dev/null)
  [ -n "$merged_enabled" ] || merged_enabled='{}'
fi

plugins_enabled=0
plugins_unresolved=0
registry_file="${home_dir}/.claude/plugins/installed_plugins.json"
proj_logical=$(cd "$project_dir" 2>/dev/null && pwd -L || printf '%s' "$project_dir")
proj_physical=$(cd "$project_dir" 2>/dev/null && pwd -P || printf '%s' "$project_dir")

# Rows: P<FS>id<FS>installPath<FS>explicit|default for each installed plugin
# not set to false, and U<FS>id for a plugin set to true with no install record.
# One install per plugin, so a plugin with several versions installed is counted
# once: the project/local-scope entry for this project wins over the user-scope
# entry (a project-scope install is what that project loads).
registry_json='{}'
[ -f "$registry_file" ] && registry_json=$(jq -c '.' "$registry_file" 2>/dev/null)
[ -n "$registry_json" ] || registry_json='{}'
plugin_rows=$(jq -r --argjson en "$merged_enabled" --arg p1 "$proj_logical" --arg p2 "$proj_physical" '
  ((.plugins // {}) | if type == "object" then . else {} end) as $reg
  | [ $reg | to_entries[]
      | .key as $id
      | (.value | if type == "array" then . else [.] end | map(select(type == "object"))) as $e
      | ( [ $e[] | select((.scope == "project" or .scope == "local")
                          and ((.projectPath // "") as $pp | $pp == $p1 or $pp == $p2)) ][0]
          // [ $e[] | select(.scope == "user") ][0] ) as $rec
      | select($rec != null)
      | ($en[$id]) as $state
      | select($state != false)
      | {id: $id, path: (($rec.installPath // "") | tostring),
         state: (if $state == true then "explicit" else "default" end)} ] as $found
  | ($found | map(.id)) as $found_ids
  | ($found[] | ["P", .id, .path, .state] | join("\u001f")),
    ( $en | to_entries[] | select(.value == true) | .key
      | . as $k | select(($found_ids | index($k)) == null) | ["U", $k] | join("\u001f") )
' <<<"$registry_json" 2>/dev/null | tr -d '\r')

while IFS="$FS" read -r row_kind plugin_key install_path enable_state; do
  [ -z "$plugin_key" ] && continue
  if [ "$row_kind" = "U" ] || [ -z "$install_path" ] || [ ! -d "$install_path" ]; then
    # A default-enabled record with no directory is registry debris, not an
    # enabled plugin; only an explicit `true` is reported as unresolved.
    if [ "$row_kind" = "U" ] || [ "$enable_state" = "explicit" ]; then
      plugins_unresolved=$((plugins_unresolved + 1))
      [ "$verbose_mode" = true ] && echo "PLUGIN_UNRESOLVED: ${plugin_key}"
    fi
    continue
  fi
  manifest="${install_path}/.claude-plugin/plugin.json"
  if [ "$enable_state" = "default" ] && [ -f "$manifest" ] \
     && [ "$(jq -r '.defaultEnabled == false' "$manifest" 2>/dev/null)" = "true" ]; then
    continue
  fi
  plugins_enabled=$((plugins_enabled + 1))
  source_label="plugin:${plugin_key}"
  default_hooks="${install_path}/hooks/hooks.json"

  # Default location, loaded whenever it exists.
  [ -f "$default_hooks" ] && scan_hooks_file "$source_label" "$default_hooks" "$install_path"

  # plugin.json "hooks": a path, an inline event map, or an array of either,
  # merged with hooks/hooks.json.
  [ -f "$manifest" ] || continue
  hook_items=$(jq -r '
    (.hooks // empty) | (if type == "array" then .[] else . end)
    | if type == "string" then "S\u001f" + .
      elif type == "object" then "O\u001f" + tojson
      else empty end' "$manifest" 2>/dev/null | tr -d '\r')
  while IFS="$FS" read -r item_kind item_value; do
    case "$item_kind" in
      S)
        ref_path="${install_path}/${item_value#./}"
        # A reference to hooks/hooks.json is the file already scanned.
        [ "$ref_path" = "$default_hooks" ] && continue
        if [ ! -f "$ref_path" ]; then
          add_issue missing_hooks_file "FILE=${ref_path} SOURCE=${source_label}" "plugin.json hooks path does not exist"
          continue
        fi
        scan_hooks_file "$source_label" "$ref_path" "$install_path"
        ;;
      O)
        scan_event_map "$source_label" "$manifest" "$install_path" "$item_value"
        ;;
    esac
  done <<<"$hook_items"
done <<<"$plugin_rows"

# --- Summary ----------------------------------------------------------------
total_hooks=$((settings_hook_count + plugin_hook_count))

if [ "$issue_count" -gt 0 ]; then
  check_status="WARN"
elif [ "$total_hooks" -eq 0 ]; then
  check_status="N_A"
else
  check_status="OK"
fi

if [ "$total_hooks" -eq 0 ]; then
  echo "HOOKS_CONFIGURED=false"
else
  echo "HOOKS_CONFIGURED=true"
fi
echo "HOOK_COUNT=${total_hooks}"
echo "SETTINGS_HOOK_COUNT=${settings_hook_count}"
echo "PLUGIN_HOOK_COUNT=${plugin_hook_count}"
echo "PLUGINS_ENABLED=${plugins_enabled}"
echo "PLUGINS_UNRESOLVED=${plugins_unresolved}"
echo "STATUS=${check_status}"
if [ "$check_status" = "WARN" ]; then
  reason=$(tr -s '[:space:]' ' ' <<<"$first_reason")
  reason="${reason% }"
  reason="${reason:0:180}"
  [ "$issue_count" -gt 1 ] && reason="${reason} (+$((issue_count - 1)) more)"
  echo "REASON=${reason}"
fi
echo "ISSUE_COUNT=${issue_count}"
if [ -n "$issues_rows" ]; then
  echo "ISSUES:"
  printf '%s' "$issues_rows"
fi
echo "=== END HOOKS CONFIGURATION ==="
exit 0
