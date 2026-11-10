#!/usr/bin/env bash
# shellcheck disable=SC2016  # fixtures hold literal ${CLAUDE_PLUGIN_ROOT} for the script to expand
# Regression tests for check-hooks.sh.
#
# Timeout units (issue #3091): Claude Code hook `timeout` values are SECONDS.
# The script used to read them as milliseconds (warn only above 60000, print an
# `ms` suffix), so a 300 s budget passed silently and a 5000 "ms" typo (83
# minutes) was never caught. >= 1000 is ms_timeout, the same threshold and TYPE
# as scripts/check-hook-timeout-units.sh (#3088).
#
# Plugin inventory and validation: the script used to read only the four
# settings files, so on a machine whose hooks mostly come from enabled plugins
# it reported HOOK_COUNT=9 STATUS=OK while 62 plugin hooks went unchecked. It
# never validated event names or handler types, and flagged a 300 s SessionStart
# install hook although .claude/rules/sandbox-guidance.md recommends 120-300 s.
# Cases 5-10 fail against the pre-fix script.
#
# Default-enabled plugins, interpreter scripts, local scope: the first plugin
# inventory counted only plugins with an explicit `true`, so an installed plugin
# with no enabledPlugins entry (enabled through its manifest defaultEnabled,
# default true) had its hooks skipped (case 11). check_command returned early
# for any `bash <script>` command, so a deleted hook script was never reported
# (case 12). ~/.claude/settings.local.json was read for every project, though it
# is local scope for the home directory only (case 13). Cases 11-14 fail against
# that version. Run any case set against any copy with
#   CHECK_HOOKS_SCRIPT=/path/to/check-hooks.sh bash test-check-hooks.sh
#
# Hermetic: every run gets scratch --home-dir/--project-dir; the real HOME is
# never read. Exit 0 on success, non-zero on failure.

set -uo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
check_script="${CHECK_HOOKS_SCRIPT:-${script_dir}/../check-hooks.sh}"
contract_script="${script_dir}/../../../../../scripts/check-structured-output-contract.sh"

fail() {
  printf 'FAIL: %b\n' "$1" >&2
  exit 1
}

pass() {
  echo "PASS: $1"
}

if ! command -v jq >/dev/null 2>&1; then
  echo "SKIP: jq not installed; cannot run check-hooks tests"
  exit 0
fi

[ -f "$check_script" ] || fail "check-hooks.sh not found at $check_script"

scratch="$(mktemp -d)" || fail "mktemp failed"
{ [ -n "$scratch" ] && [ -d "$scratch" ]; } || fail "mktemp returned no directory"
trap 'rm -rf "$scratch"' EXIT
home_dir="${scratch}/home"
proj_dir="${scratch}/proj"

reset_sandbox() {
  rm -rf "$home_dir" "$proj_dir"
  mkdir -p "${home_dir}/.claude/plugins" "${proj_dir}/.claude"
}
reset_sandbox

run_check() {
  bash "$check_script" --home-dir "$home_dir" --project-dir "$proj_dir"
}

# run_with_timeout <timeout-json-fragment> [event]
# Writes a single hook (command `true`, always on PATH) to the scratch user
# settings and prints the script output.
run_with_timeout() {
  local fragment="$1" event="${2:-PreToolUse}"
  printf '{"hooks":{"%s":[{"matcher":"Bash","hooks":[{"type":"command","command":"true"%s}]}]}}' \
    "$event" "$fragment" > "${home_dir}/.claude/settings.json"
  run_check
}

assert_has() {
  local label="$1" pattern="$2" out="$3"
  grep -qE -- "$pattern" <<<"$out" || fail "${label}: expected /${pattern}/, got:\n$out"
}

assert_lacks() {
  local label="$1" pattern="$2" out="$3"
  grep -qE -- "$pattern" <<<"$out" && fail "${label}: unexpected /${pattern}/ in:\n$out"
  return 0
}

assert_no_timeout_issue() {
  local label="$1" out="$2"
  assert_lacks "$label" "TYPE=(high_timeout|ms_timeout)" "$out"
  assert_has "$label" "^STATUS=OK$" "$out"
  assert_has "$label" "^ISSUE_COUNT=0$" "$out"
}

# assert_contract <label> <output>: ISSUE_COUNT equals the ISSUES rows, and
# REASON= is present iff STATUS is WARN/ERROR, opening with the first row's TYPE.
assert_contract() {
  local label="$1" out="$2" rows count
  rows=$(grep -cE '^  - SEVERITY=' <<<"$out" || true)
  count=$(sed -n 's/^ISSUE_COUNT=//p' <<<"$out")
  [ "$rows" = "$count" ] || fail "${label}: ISSUE_COUNT=${count} but ${rows} ISSUES rows:\n$out"
  if [ -f "$contract_script" ]; then
    bash "$contract_script" --validate - <<<"$out" >/dev/null \
      || fail "${label}: structured-output contract violated:\n$out"
  fi
}

# make_plugin <name> <version> <plugin.json body>: prints the install path.
make_plugin() {
  local plugin_name="$1" plugin_version="$2" manifest="$3"
  local root="${home_dir}/.claude/plugins/cache/mk/${plugin_name}/${plugin_version}"
  mkdir -p "${root}/.claude-plugin" "${root}/hooks" "${root}/scripts"
  printf '%s\n' "$manifest" > "${root}/.claude-plugin/plugin.json"
  printf '#!/usr/bin/env bash\nexit 0\n' > "${root}/scripts/ok.sh"
  printf '%s' "$root"
}

# write_registry <jq object of plugin-key -> entries array>
write_registry() {
  jq -n "{version: 2, plugins: ($1)}" > "${home_dir}/.claude/plugins/installed_plugins.json"
}

# -----------------------------------------------------------------------------
# Case 1: 30 s, 60 s and no timeout ("default") are fine
# -----------------------------------------------------------------------------
assert_no_timeout_issue "timeout=30" "$(run_with_timeout ',"timeout":30')"
pass "timeout 30 s raises no issue"
assert_no_timeout_issue "timeout=60" "$(run_with_timeout ',"timeout":60')"
pass "timeout 60 s (boundary) raises no issue"
assert_no_timeout_issue "no timeout" "$(run_with_timeout '')"
pass "missing timeout (default) raises no issue"

# -----------------------------------------------------------------------------
# Case 2: 300 s on a per-tool event is a high timeout, reported in seconds
# -----------------------------------------------------------------------------
out300="$(run_with_timeout ',"timeout":300')"
assert_has "timeout=300" "SEVERITY=WARN TYPE=high_timeout EVENT=PreToolUse TIMEOUT=300s " "$out300"
assert_lacks "timeout=300" "TIMEOUT=[0-9]*ms" "$out300"
assert_has "timeout=300" "^STATUS=WARN$" "$out300"
pass "timeout 300 s on PreToolUse is high_timeout with TIMEOUT=300s"

# -----------------------------------------------------------------------------
# Case 3: 5000 is a millisecond figure written as seconds
# -----------------------------------------------------------------------------
out5000="$(run_with_timeout ',"timeout":5000')"
assert_has "timeout=5000" "SEVERITY=WARN TYPE=ms_timeout EVENT=PreToolUse TIMEOUT=5000s " "$out5000"
assert_lacks "timeout=5000" "TYPE=high_timeout" "$out5000"
assert_has "timeout=5000" "^ISSUE_COUNT=1$" "$out5000"
pass "timeout 5000 is flagged as a likely millisecond value (ms_timeout)"

# -----------------------------------------------------------------------------
# Case 4: 1000 is the threshold (>= 1000 is ms_timeout; 999 is high_timeout)
# -----------------------------------------------------------------------------
assert_has "timeout=1000" "TYPE=ms_timeout" "$(run_with_timeout ',"timeout":1000')"
assert_has "timeout=999" "TYPE=high_timeout EVENT=PreToolUse TIMEOUT=999s " "$(run_with_timeout ',"timeout":999')"
pass "ms_timeout threshold is 1000, matching check-hook-timeout-units.sh"

# -----------------------------------------------------------------------------
# Case 5: SessionStart install hooks get the 300 s setup limit
# -----------------------------------------------------------------------------
assert_no_timeout_issue "SessionStart 300" "$(run_with_timeout ',"timeout":300' SessionStart)"
assert_no_timeout_issue "Setup 300" "$(run_with_timeout ',"timeout":300' Setup)"
assert_has "SessionStart 301" "TYPE=high_timeout EVENT=SessionStart TIMEOUT=301s LIMIT=300s " \
  "$(run_with_timeout ',"timeout":301' SessionStart)"
assert_has "SessionStart 5000" "TYPE=ms_timeout EVENT=SessionStart TIMEOUT=5000s " \
  "$(run_with_timeout ',"timeout":5000' SessionStart)"
pass "SessionStart 300 s is not flagged; 301 s is high_timeout; 5000 is ms_timeout"

# -----------------------------------------------------------------------------
# Case 6: unknown event name and unknown handler type are findings
# -----------------------------------------------------------------------------
printf '%s' '{"hooks":{"PreToolUse":[{"hooks":[{"type":"command","command":"true"}]}],
  "PreToolUsee":[{"hooks":[{"type":"command","command":"true"}]}],
  "Stop":[{"hooks":[{"type":"shell","command":"true"}]}],
  "PostToolUse":[{"hooks":[{"command":"true"}]}],
  "Notification":[{"hooks":[{"type":"mcp_tool"},{"type":"http"},{"type":"prompt"},{"type":"agent"}]}]}}' \
  > "${home_dir}/.claude/settings.json"
out_unknown="$(run_check)"
assert_has "unknown event" "SEVERITY=WARN TYPE=unknown_event EVENT=PreToolUsee " "$out_unknown"
assert_has "unknown type" "SEVERITY=WARN TYPE=unknown_hook_type EVENT=Stop HOOK_TYPE=shell " "$out_unknown"
assert_has "missing type" "TYPE=unknown_hook_type EVENT=PostToolUse HOOK_TYPE=<missing> " "$out_unknown"
assert_lacks "documented types" "HOOK_TYPE=(command|http|mcp_tool|prompt|agent) " "$out_unknown"
assert_lacks "documented events" "TYPE=unknown_event EVENT=(PreToolUse|Stop|PostToolUse|Notification) " "$out_unknown"
assert_has "unknown → WARN" "^STATUS=WARN$" "$out_unknown"
assert_has "unknown count" "^ISSUE_COUNT=3$" "$out_unknown"
assert_has "unknown reason" "^REASON=unknown_event: .* \(\+2 more\)$" "$out_unknown"
assert_contract "unknown" "$out_unknown"
pass "unknown event and unknown/missing hook type are flagged; documented ones pass"

# -----------------------------------------------------------------------------
# Case 7: enabled plugin hooks — inline object and string-ref forms
# -----------------------------------------------------------------------------
reset_sandbox
inline_root=$(make_plugin inline-plugin 1.0.0 '{"name":"inline-plugin","hooks":{
  "PreToolUse":[{"matcher":"Bash","hooks":[{"type":"command","command":"\"${CLAUDE_PLUGIN_ROOT}\"/scripts/ok.sh","timeout":10}]}],
  "SessionStart":[{"hooks":[{"type":"command","command":"bash \"${CLAUDE_PLUGIN_ROOT}/scripts/ok.sh\"","timeout":300}]}]}}')
ref_root=$(make_plugin ref-plugin 2.0.0 '{"name":"ref-plugin","hooks":["./hooks.json","./hooks/hooks.json"]}')
printf '%s' '{"description":"extra","hooks":{"Stop":[{"hooks":[{"type":"prompt","prompt":"done?"}]}]}}' > "${ref_root}/hooks.json"
printf '%s' '{"hooks":{"PostToolUse":[{"hooks":[{"type":"command","command":"${CLAUDE_PLUGIN_ROOT}/scripts/ok.sh"}]},
  {"matcher":"Write","hooks":[{"type":"command","command":"${CLAUDE_PLUGIN_ROOT}/scripts/gone.sh"}]}]}}' > "${ref_root}/hooks/hooks.json"
write_registry "{
  \"inline-plugin@mk\": [{scope: \"user\", installPath: \"${inline_root}\", version: \"1.0.0\"}],
  \"ref-plugin@mk\":    [{scope: \"user\", installPath: \"${ref_root}\", version: \"2.0.0\"}]}"
printf '%s' '{"enabledPlugins":{"inline-plugin@mk":true,"ref-plugin@mk":true},
  "hooks":{"PreToolUse":[{"hooks":[{"type":"command","command":"true"}]}]}}' > "${home_dir}/.claude/settings.json"
out_plugins="$(run_check)"
assert_has "plugin total" "^HOOK_COUNT=6$" "$out_plugins"
assert_has "settings count" "^SETTINGS_HOOK_COUNT=1$" "$out_plugins"
# inline: 2; ref-plugin: hooks/hooks.json 2 (once, though plugin.json names it
# too) + ./hooks.json 1.
assert_has "plugin count" "^PLUGIN_HOOK_COUNT=5$" "$out_plugins"
assert_has "plugins enabled" "^PLUGINS_ENABLED=2$" "$out_plugins"
assert_has "plugin missing command" \
  "TYPE=missing_command EVENT=PostToolUse COMMAND=${ref_root}/scripts/gone.sh FILE=${ref_root}/hooks/hooks.json SOURCE=plugin:ref-plugin@mk " \
  "$out_plugins"
assert_lacks "CLAUDE_PLUGIN_ROOT resolved" "COMMAND=[^ ]*ok\.sh" "$out_plugins"
assert_lacks "plugin SessionStart 300" "TYPE=high_timeout" "$out_plugins"
assert_has "plugin issue count" "^ISSUE_COUNT=1$" "$out_plugins"
assert_contract "plugins" "$out_plugins"
pass "inline and string-ref plugin hooks are inventoried with SOURCE= and separate counts"

# -----------------------------------------------------------------------------
# Case 8: a disabled plugin is excluded; one plugin with two installs counts once
# -----------------------------------------------------------------------------
reset_sandbox
v1_root=$(make_plugin multi-plugin 1.0.0 '{"name":"multi-plugin","hooks":{
  "PreToolUse":[{"hooks":[{"type":"command","command":"true"}]}]}}')
v2_root=$(make_plugin multi-plugin 2.0.0 '{"name":"multi-plugin","hooks":{
  "PreToolUse":[{"hooks":[{"type":"command","command":"true"},{"type":"command","command":"true"}]}]}}')
off_root=$(make_plugin off-plugin 1.0.0 '{"name":"off-plugin","hooks":{
  "BogusEvent":[{"hooks":[{"type":"bogus","command":"true","timeout":9000}]}]}}')
write_registry "{
  \"multi-plugin@mk\": [
    {scope: \"user\", installPath: \"${v1_root}\", version: \"1.0.0\"},
    {scope: \"project\", projectPath: \"${proj_dir}\", installPath: \"${v2_root}\", version: \"2.0.0\"}],
  \"off-plugin@mk\": [{scope: \"user\", installPath: \"${off_root}\", version: \"1.0.0\"}]}"
printf '%s' '{"enabledPlugins":{"multi-plugin@mk":true,"off-plugin@mk":true}}' > "${home_dir}/.claude/settings.json"
printf '%s' '{"enabledPlugins":{"off-plugin@mk":false}}' > "${proj_dir}/.claude/settings.json"
out_scope="$(run_check)"
assert_has "project install wins" "^PLUGIN_HOOK_COUNT=2$" "$out_scope"
assert_has "enabled count" "^PLUGINS_ENABLED=1$" "$out_scope"
assert_lacks "disabled plugin excluded" "off-plugin|BogusEvent|TYPE=" "$out_scope"
assert_has "clean" "^STATUS=OK$" "$out_scope"
pass "project false overrides user true; the project-scope install is the one counted"

# -----------------------------------------------------------------------------
# Case 9: plugin.json names a hooks file that is missing or unwrapped
# -----------------------------------------------------------------------------
reset_sandbox
bad_root=$(make_plugin bad-plugin 1.0.0 '{"name":"bad-plugin","hooks":["./missing.json","./bare.json"]}')
printf '%s' '{"PreToolUse":[{"hooks":[{"type":"command","command":"true"}]}]}' > "${bad_root}/bare.json"
write_registry "{\"bad-plugin@mk\": [{scope: \"user\", installPath: \"${bad_root}\"}]}"
printf '%s' '{"enabledPlugins":{"bad-plugin@mk":true}}' > "${home_dir}/.claude/settings.json"
out_bad="$(run_check)"
assert_has "missing file" "TYPE=missing_hooks_file FILE=${bad_root}/missing.json SOURCE=plugin:bad-plugin@mk " "$out_bad"
assert_has "unwrapped file" "TYPE=invalid_hooks_file FILE=${bad_root}/bare.json " "$out_bad"
assert_has "bad count" "^ISSUE_COUNT=2$" "$out_bad"
assert_has "bad reason" "^REASON=missing_hooks_file: .* \(\+1 more\)$" "$out_bad"
assert_contract "bad hooks files" "$out_bad"
pass "missing and unwrapped plugin hooks files are flagged"

# -----------------------------------------------------------------------------
# Case 10: nothing configured is N_A; WARN output carries REASON=
# -----------------------------------------------------------------------------
reset_sandbox
out_none="$(run_check)"
assert_has "none" "^HOOKS_CONFIGURED=false$" "$out_none"
assert_has "none" "^STATUS=N_A$" "$out_none"
assert_lacks "none" "^REASON=" "$out_none"
assert_contract "timeout WARN" "$(run_with_timeout ',"timeout":300')"
assert_has "timeout REASON" "^REASON=high_timeout: " "$(run_with_timeout ',"timeout":300')"
assert_contract "OK" "$(run_with_timeout ',"timeout":30')"
pass "N_A with no hooks; WARN carries REASON= and ISSUE_COUNT matches ISSUES rows"

# -----------------------------------------------------------------------------
# Case 11: no enabledPlugins entry falls back to the manifest defaultEnabled
# -----------------------------------------------------------------------------
reset_sandbox
dflt_root=$(make_plugin dflt-plugin 1.0.0 '{"name":"dflt-plugin","hooks":{
  "PreToolUse":[{"hooks":[{"type":"command","command":"true"}]}]}}')
optin_root=$(make_plugin optin-plugin 1.0.0 '{"name":"optin-plugin","defaultEnabled":false,"hooks":{
  "PreToolUse":[{"hooks":[{"type":"command","command":"true"},{"type":"command","command":"true"}]}]}}')
write_registry "{
  \"dflt-plugin@mk\":  [{scope: \"user\", installPath: \"${dflt_root}\"}],
  \"optin-plugin@mk\": [{scope: \"user\", installPath: \"${optin_root}\"}]}"
printf '%s' '{}' > "${home_dir}/.claude/settings.json"
out_dflt="$(run_check)"
assert_has "default-enabled hooks" "^PLUGIN_HOOK_COUNT=1$" "$out_dflt"
assert_has "default-enabled count" "^PLUGINS_ENABLED=1$" "$out_dflt"
assert_has "default-enabled status" "^STATUS=OK$" "$out_dflt"
printf '%s' '{"enabledPlugins":{"optin-plugin@mk":true}}' > "${proj_dir}/.claude/settings.json"
out_optin="$(run_check)"
assert_has "explicit true beats defaultEnabled false" "^PLUGIN_HOOK_COUNT=3$" "$out_optin"
assert_has "explicit true count" "^PLUGINS_ENABLED=2$" "$out_optin"
pass "a plugin with no entry is enabled unless its manifest sets defaultEnabled:false"

# -----------------------------------------------------------------------------
# Case 12: `bash <script>` checks the script; -c and relative paths are skipped
# -----------------------------------------------------------------------------
reset_sandbox
sh_root=$(make_plugin sh-plugin 1.0.0 '{"name":"sh-plugin","hooks":{
  "PreToolUse":[{"hooks":[
    {"type":"command","command":"bash \"${CLAUDE_PLUGIN_ROOT}/hooks/missing.sh\""},
    {"type":"command","command":"bash -e \"${CLAUDE_PLUGIN_ROOT}/scripts/ok.sh\""},
    {"type":"command","command":"bash -c true"},
    {"type":"command","command":"sh relative/thing.sh"}]}]}}')
write_registry "{\"sh-plugin@mk\": [{scope: \"user\", installPath: \"${sh_root}\"}]}"
printf '%s' '{"enabledPlugins":{"sh-plugin@mk":true}}' > "${home_dir}/.claude/settings.json"
out_sh="$(run_check)"
assert_has "bash missing script" \
  "TYPE=missing_command EVENT=PreToolUse COMMAND=${sh_root}/hooks/missing.sh FILE=${sh_root}/.claude-plugin/plugin.json SOURCE=plugin:sh-plugin@mk " \
  "$out_sh"
assert_lacks "existing script behind a flag" "COMMAND=[^ ]*ok\.sh" "$out_sh"
assert_lacks "bash -c and relative path skipped" "COMMAND=(true|relative/thing\.sh|-c|-e|bash|sh) " "$out_sh"
assert_has "one finding" "^ISSUE_COUNT=1$" "$out_sh"
assert_contract "bash script" "$out_sh"
pass "a bash-run hook script that is missing is reported; -c and relative paths are not"

# -----------------------------------------------------------------------------
# Case 13: ~/.claude/settings.local.json applies only when the project is home
# -----------------------------------------------------------------------------
reset_sandbox
printf '%s' '{"hooks":{"PreToolUse":[{"hooks":[{"type":"command","command":"true"}]}]}}' \
  > "${home_dir}/.claude/settings.local.json"
out_homelocal="$(run_check)"
assert_has "home local ignored for another project" "^HOOK_COUNT=0$" "$out_homelocal"
out_inhome="$(bash "$check_script" --home-dir "$home_dir" --project-dir "$home_dir")"
assert_has "home local read in the home directory" "^SETTINGS_HOOK_COUNT=1$" "$out_inhome"
pass 'the home settings.local.json counts only for a session in the home directory'

# -----------------------------------------------------------------------------
# Case 14: true with no install for this project is unresolved, not enabled
# -----------------------------------------------------------------------------
reset_sandbox
other_root=$(make_plugin other-plugin 1.0.0 '{"name":"other-plugin"}')
write_registry "{\"other-plugin@mk\": [{scope: \"project\", projectPath: \"/elsewhere\", installPath: \"${other_root}\"}]}"
printf '%s' '{"enabledPlugins":{"other-plugin@mk":true,"ghost-plugin@mk":true}}' > "${home_dir}/.claude/settings.json"
out_unres="$(run_check)"
assert_has "unresolved count" "^PLUGINS_UNRESOLVED=2$" "$out_unres"
assert_has "nothing enabled" "^PLUGINS_ENABLED=0$" "$out_unres"
pass "an enabled key with no install for this project counts as unresolved"

echo "ALL TESTS PASSED"
