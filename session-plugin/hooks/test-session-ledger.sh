#!/usr/bin/env bash
# shellcheck disable=SC2016,SC2034  # check() evals single-quoted assertions; out/rc are read inside them
# Regression tests for session-ledger.sh (Stop + SessionEnd).
#
# The ledger is the guard against closing a session that still holds
# uncaptured learnings or manual steps: no hook event can block a close
# (SessionEnd is notify-only, and a killed process or closed terminal fires
# nothing at all), so the hook records every substantive session on each
# Stop and clears the record once an end-of-session skill has run. The next
# session start surfaces what is left (session-spinup-nudge.sh).
#
# Semantic invariants pinned here:
#   - an entry carries the resume coordinates (session_id + cwd), since a
#     record that cannot be resumed captures nothing;
#   - an end-of-session skill in the transcript removes the entry, so a
#     wrapped session never nags;
#   - the hook prints nothing and always exits 0 (Stop output would inject
#     context into the conversation; SessionEnd output is discarded).
#
# Run: bash session-plugin/hooks/test-session-ledger.sh
set -euo pipefail

# Neutralize any inherited git context before building sandbox repos (issues #1745, #3080).
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_OBJECT_DIRECTORY \
  GIT_COMMON_DIR GIT_NAMESPACE GIT_PREFIX

HOOK="$(dirname "$0")/session-ledger.sh"
PASS=0
FAIL=0

TEST_HOME=$(mktemp -d) || { echo "mktemp -d failed" >&2; exit 1; }
LEDGER=$(mktemp -d) || { echo "mktemp -d failed" >&2; exit 1; }
REPO=$(mktemp -d) || { echo "mktemp -d failed" >&2; exit 1; }
trap 'rm -rf "$TEST_HOME" "$LEDGER" "$REPO"' EXIT
git -C "$REPO" init -q

make_transcript() {
    local turns="$1" path i=1
    path=$(mktemp)
    while [ "$i" -le "$turns" ]; do
        printf '{"role":"user","content":"step %d"}\n' "$i" >> "$path"
        i=$((i + 1))
    done
    echo "$path"
}

run_hook() {
    local event="$1" sid="$2" tp="$3" reason="${4:-}"
    jq -nc --arg e "$event" --arg sid "$sid" --arg cwd "$REPO" --arg tp "$tp" --arg r "$reason" \
        '{hook_event_name: $e, session_id: $sid, cwd: $cwd, transcript_path: $tp}
         + (if $r == "" then {} else {reason: $r} end)' \
        | HOME="$TEST_HOME" SESSION_LEDGER_DIR="$LEDGER" bash "$HOOK"
}

ok()   { printf "  PASS: %s\n" "$1"; PASS=$((PASS + 1)); }
bad()  { printf "  FAIL: %s\n" "$1"; FAIL=$((FAIL + 1)); }
check() { if eval "$2"; then ok "$1"; else bad "$1"; fi; }

echo "=== session-ledger hook tests ==="

echo ""
echo "thresholds and guards:"
T=$(make_transcript 2)
out=$(run_hook Stop sess-short "$T"); rc=$?
check "short session (2 turns) writes no entry" '[ ! -e "$LEDGER/sess-short.json" ]'
check "hook prints nothing" '[ -z "$out" ] && [ "$rc" = 0 ]'
rm -f "$T"

out=$(printf '{"hook_event_name":"Stop","cwd":"/x"}' \
    | HOME="$TEST_HOME" SESSION_LEDGER_DIR="$LEDGER" bash "$HOOK"); rc=$?
check "missing session_id exits 0 silently" '[ -z "$out" ] && [ "$rc" = 0 ]'

out=$(printf '{"hook_event_name":"Stop","session_id":"../evil","cwd":"/x","transcript_path":"/nonexistent"}' \
    | HOME="$TEST_HOME" SESSION_LEDGER_DIR="$LEDGER" bash "$HOOK"); rc=$?
check "path-like session_id is refused" '[ "$rc" = 0 ] && [ -z "$(ls -A "$LEDGER")" ]'

out=$(printf 'not json' | HOME="$TEST_HOME" SESSION_LEDGER_DIR="$LEDGER" bash "$HOOK"); rc=$?
check "malformed input exits 0 silently" '[ -z "$out" ] && [ "$rc" = 0 ]'

# Tool results and harness-injected lines are not user turns.
T=$(make_transcript 2)
for i in 1 2 3 4 5; do
    printf '{"role":"user","content":[{"tool_use_id":"t%d","type":"tool_result","content":"ok"}]}\n' "$i" >> "$T"
    printf '{"role":"user","isMeta":true,"content":"<system-reminder>x</system-reminder>"}\n' >> "$T"
done
run_hook Stop sess-noise "$T" >/dev/null
check "tool results and meta lines do not count as turns" '[ ! -e "$LEDGER/sess-noise.json" ]'
rm -f "$T"

echo ""
echo "recording on Stop:"
T=$(make_transcript 4)
printf '{"role":"user","message":{"role":"user","content":[{"type":"text","text":"remember to rotate the deploy key"}]}}\n' >> "$T"
run_hook Stop sess-live "$T" >/dev/null
E="$LEDGER/sess-live.json"
check "substantive session writes an entry" '[ -f "$E" ]'
check "entry is valid JSON" 'jq -e . "$E" >/dev/null'
check "entry carries session_id and cwd (resume coordinates)" \
    '[ "$(jq -r .session_id "$E")" = sess-live ] && [ "$(jq -r .cwd "$E")" = "$REPO" ]'
check "entry is open (no ended_at) after Stop" '[ "$(jq -r .ended_at "$E")" = null ]'
check "entry counts genuine user turns" '[ "$(jq -r .user_turns "$E")" = 5 ]'
check "entry keeps the last user message (Claude Code message shape)" \
    'jq -r .last_user_message "$E" | grep -q "rotate the deploy key"'
first_seen=$(jq -r .first_seen "$E")
check "timestamps are ISO-8601 UTC" 'grep -Eq "^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$" <<<"$first_seen"'

printf '{"role":"user","content":"one more"}\n' >> "$T"
run_hook Stop sess-live "$T" >/dev/null
check "later Stop updates the turn count" '[ "$(jq -r .user_turns "$E")" = 6 ]'
check "later Stop keeps first_seen" '[ "$(jq -r .first_seen "$E")" = "$first_seen" ]'

echo ""
echo "SessionEnd:"
run_hook SessionEnd sess-live "$T" prompt_input_exit >/dev/null
check "SessionEnd marks the entry closed" '[ "$(jq -r .ended_at "$E")" != null ]'
check "SessionEnd records the reason" '[ "$(jq -r .end_reason "$E")" = prompt_input_exit ]'
check "no temp files left behind" '[ -z "$(find "$LEDGER" -name ".*" -type f)" ]'

echo ""
echo "clearing when an end-of-session skill ran:"
printf '{"role":"user","content":"<command-name>/session-plugin:session-end</command-name>"}\n' >> "$T"
run_hook Stop sess-live "$T" >/dev/null
check "slash-command session-end removes the entry" '[ ! -e "$E" ]'
rm -f "$T"

T=$(make_transcript 6)
printf '{"role":"assistant","message":{"content":[{"type":"tool_use","name":"Skill","input":{"skill":"session-plugin:session-wrap"}}]}}\n' >> "$T"
run_hook SessionEnd sess-wrapped "$T" other >/dev/null
check "Skill-tool session-wrap prevents an entry" '[ ! -e "$LEDGER/sess-wrapped.json" ]'
rm -f "$T"

T=$(make_transcript 6)
run_hook SessionEnd sess-direct "$T" logout >/dev/null
check "SessionEnd alone (no earlier Stop) still records" \
    '[ "$(jq -r .end_reason "$LEDGER/sess-direct.json")" = logout ]'
rm -f "$T"

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
