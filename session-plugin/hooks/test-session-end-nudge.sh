#!/usr/bin/env bash
# Regression tests for session-end-nudge.sh
#
# Verifies the collapsed Stop-hook nudge (design D4) fires only when all
# gates pass, and specifically covers the two failure modes that motivated
# the collapse (observed 2026-06-10 in a live /session-wrap run):
#
#   1. The wind-down regex must NOT match skill markdown injected by a
#      slash-command expansion ("Wrap up a working session…"), and tool
#      results must NOT count toward the turn floor.
#   2. The nudge must stay silent when a session-wrap / session-end /
#      session-distill invocation already appears in the transcript — the
#      skill owns the flow; the hook must not race its confirmation gate.
#
# Semantic invariant (per .claude/rules/regression-testing.md): when the
# hook fires, the emitted JSON must mention session-plugin:session-end
# literally so prose edits cannot silently break the nudge contract.
#
# Run: bash session-plugin/hooks/test-session-end-nudge.sh
# Exit 0 = all tests pass, Exit 1 = failures
set -euo pipefail

HOOK="$(dirname "$0")/session-end-nudge.sh"
PASS=0
FAIL=0

TEST_HOME=$(mktemp -d) || { echo "mktemp -d failed" >&2; exit 1; }
REPO_WITH_RULES=$(mktemp -d) || { echo "mktemp -d failed" >&2; exit 1; }
REPO_PLAIN=$(mktemp -d) || { echo "mktemp -d failed" >&2; exit 1; }
trap 'rm -rf "$TEST_HOME" "$REPO_WITH_RULES" "$REPO_PLAIN"' EXIT

git -C "$REPO_WITH_RULES" init -q
mkdir -p "$REPO_WITH_RULES/.claude/rules"
echo "# rule" > "$REPO_WITH_RULES/.claude/rules/example.md"

git -C "$REPO_PLAIN" init -q
echo "# readme" > "$REPO_PLAIN/README.md"

# Build a fake transcript: N genuine user messages, then an optional final
# user phrase. Callers append special-shape lines themselves.
make_transcript() {
    local turns="$1"
    local final_phrase="${2:-}"
    local path
    path=$(mktemp)
    local i=1
    while [ "$i" -lt "$turns" ]; do
        printf '{"role":"user","content":"step %d"}\n' "$i" >> "$path"
        i=$((i + 1))
    done
    if [ -n "$final_phrase" ]; then
        printf '{"role":"user","content":"%s"}\n' "$final_phrase" >> "$path"
    else
        printf '{"role":"user","content":"step %d"}\n' "$turns" >> "$path"
    fi
    echo "$path"
}

# Run the hook; echo its stdout. NO_TASK=1 simulates absent taskwarrior.
run_hook_output() {
    local session_id="$1" cwd="$2" transcript="$3" extra="${4:-}"
    local json
    if [ -n "$extra" ]; then
        json=$(jq -nc --arg sid "$session_id" --arg cwd "$cwd" --arg tp "$transcript" \
            "{session_id: \$sid, cwd: \$cwd, transcript_path: \$tp, $extra}")
    else
        json=$(jq -nc --arg sid "$session_id" --arg cwd "$cwd" --arg tp "$transcript" \
            '{session_id: $sid, cwd: $cwd, transcript_path: $tp}')
    fi
    printf '%s' "$json" \
        | HOME="$TEST_HOME" SESSION_NUDGE_TASK_BIN="${NO_TASK:+/nonexistent/task}" \
          bash "$HOOK" 2>/dev/null || true
}

assert_contains() {
    local desc="$1" pattern="$2" actual="$3"
    if echo "$actual" | grep -q "$pattern"; then
        printf "  PASS: %s\n" "$desc"; PASS=$((PASS + 1))
    else
        printf "  FAIL: %s (expected '%s' in: %s)\n" "$desc" "$pattern" "$actual"; FAIL=$((FAIL + 1))
    fi
}

assert_silent() {
    local desc="$1" actual="$2"
    if echo "$actual" | grep -q '"decision"'; then
        printf "  FAIL: %s (hook emitted: %s)\n" "$desc" "$actual"; FAIL=$((FAIL + 1))
    else
        printf "  PASS: %s\n" "$desc"; PASS=$((PASS + 1))
    fi
}

echo "=== session-end-nudge hook tests ==="

# ── stop_hook_active and hard guards ─────────────────────────────────────────
echo ""
echo "hard guards:"
TRANSCRIPT=$(make_transcript 10 "wrap up for the day")
output=$(run_hook_output "sess-loop" "$REPO_WITH_RULES" "$TRANSCRIPT" '"stop_hook_active":true')
assert_silent "stop_hook_active=true is silent" "$output"

output=$(printf '{"cwd":"%s","transcript_path":"%s"}' "$REPO_WITH_RULES" "$TRANSCRIPT" \
    | HOME="$TEST_HOME" bash "$HOOK" 2>/dev/null || true)
assert_silent "missing session_id is silent" "$output"
rm -f "$TRANSCRIPT"

# ── turn-count floor over GENUINE user turns ─────────────────────────────────
echo ""
echo "turn-count floor (>=6 genuine user turns):"
TRANSCRIPT=$(make_transcript 4 "wrap up for the day")
output=$(run_hook_output "sess-short" "$REPO_WITH_RULES" "$TRANSCRIPT")
assert_silent "4 genuine turns does NOT nudge" "$output"
rm -f "$TRANSCRIPT"

# Regression: tool_result lines carry role=user but must not count.
TRANSCRIPT=$(make_transcript 3 "wrap up for the day")
for i in 1 2 3 4 5 6 7 8; do
    printf '{"role":"user","content":[{"tool_use_id":"toolu_%d","type":"tool_result","content":"ok"}]}\n' "$i" >> "$TRANSCRIPT"
done
output=$(run_hook_output "sess-toolresults" "$REPO_WITH_RULES" "$TRANSCRIPT")
assert_silent "tool_result lines do NOT count toward the turn floor" "$output"
rm -f "$TRANSCRIPT"

# ── wind-down phrase gates on genuine user text only ─────────────────────────
echo ""
echo "wind-down phrase (genuine user text only):"
TRANSCRIPT=$(make_transcript 10 "what does this function do?")
output=$(run_hook_output "sess-no-winddown" "$REPO_WITH_RULES" "$TRANSCRIPT")
assert_silent "no wind-down phrase does NOT nudge" "$output"
rm -f "$TRANSCRIPT"

# Regression: a slash-command expansion containing skill markdown ("Wrap up a
# working session…") fired the old nudge mid-skill. Expansion lines must be
# excluded from the wind-down scan.
TRANSCRIPT=$(make_transcript 10 "show me the open PRs")
printf '{"role":"user","content":"<command-name>/some-other-skill</command-name> Wrap up a working session by capturing loose threads"}\n' >> "$TRANSCRIPT"
output=$(run_hook_output "sess-expansion" "$REPO_WITH_RULES" "$TRANSCRIPT")
assert_silent "skill markdown in a command expansion does NOT trigger the wind-down gate" "$output"
rm -f "$TRANSCRIPT"

# ── in-progress guard: wrap/end/distill already invoked ──────────────────────
echo ""
echo "in-progress guard (skill owns the flow):"
TRANSCRIPT=$(make_transcript 10 "wrap up for the day")
printf '{"role":"user","content":"<command-name>/session-wrap</command-name> expanded skill body"}\n' >> "$TRANSCRIPT"
output=$(run_hook_output "sess-wrap-running" "$REPO_WITH_RULES" "$TRANSCRIPT")
assert_silent "slash-invoked session-wrap suppresses the nudge" "$output"
rm -f "$TRANSCRIPT"

TRANSCRIPT=$(make_transcript 10 "wrap up for the day")
printf '{"role":"assistant","content":[{"type":"tool_use","name":"Skill","input":{"skill":"session-plugin:session-distill"}}]}\n' >> "$TRANSCRIPT"
output=$(run_hook_output "sess-distill-running" "$REPO_WITH_RULES" "$TRANSCRIPT")
assert_silent "Skill-tool-invoked session-distill suppresses the nudge" "$output"
rm -f "$TRANSCRIPT"

# ── surface gate ─────────────────────────────────────────────────────────────
echo ""
echo "surface gate (no taskwarrior, no distillable surface):"
TRANSCRIPT=$(make_transcript 10 "wrap up for the day")
output=$(NO_TASK=1 run_hook_output "sess-plain" "$REPO_PLAIN" "$TRANSCRIPT")
assert_silent "plain repo without taskwarrior does NOT nudge" "$output"

output=$(NO_TASK=1 run_hook_output "sess-rules-notask" "$REPO_WITH_RULES" "$TRANSCRIPT")
assert_contains "distillable surface alone still nudges" '"decision":"block"' "$output"
rm -f "$TRANSCRIPT"

# ── happy path + semantic invariant ──────────────────────────────────────────
echo ""
echo "happy path (semantic invariant: session-plugin:session-end in reason):"
TRANSCRIPT=$(make_transcript 10 "im done for now")
output=$(run_hook_output "sess-happy" "$REPO_WITH_RULES" "$TRANSCRIPT")
assert_contains "all gates pass emits block" '"decision":"block"' "$output"
assert_contains "reason references session-plugin:session-end" 'session-plugin:session-end' "$output"
assert_contains "reason instructs offer-only" 'never run it without explicit user confirmation' "$output"

# ── once-per-session marker ──────────────────────────────────────────────────
echo ""
echo "once-per-session marker:"
output=$(run_hook_output "sess-happy" "$REPO_WITH_RULES" "$TRANSCRIPT")
assert_silent "second call in same session is silent" "$output"
rm -f "$TRANSCRIPT"

# ── taskwarrior state-sync cue ───────────────────────────────────────────────
echo ""
echo "taskwarrior state-sync cue (open tasks → sync cue in reason):"

# run_hook_output always injects SESSION_NUDGE_TASK_BIN from the NO_TASK seam;
# for taskwarrior-specific tests we call the hook directly so we can set our
# own SESSION_NUDGE_TASK_BIN without interference.
run_hook_with_task_bin() {
    local task_bin="$1" session_id="$2" cwd="$3" transcript="$4"
    local json
    json=$(jq -nc --arg sid "$session_id" --arg cwd "$cwd" --arg tp "$transcript" \
        '{session_id: $sid, cwd: $cwd, transcript_path: $tp}')
    printf '%s' "$json" \
        | HOME="$TEST_HOME" SESSION_NUDGE_TASK_BIN="$task_bin" \
          bash "$HOOK" 2>/dev/null || true
}

# Create a mock task binary that returns a non-empty task list when queried.
MOCK_TASK_DIR=$(mktemp -d) || { echo "mktemp -d failed" >&2; exit 1; }
cat > "$MOCK_TASK_DIR/task" <<'MOCK'
#!/bin/sh
# Minimal task stub: 'export' returns one pending task; all other calls are no-ops.
case "$*" in
  *export*) printf '[{"id":1,"description":"open task","status":"pending","uuid":"00000000-0000-0000-0000-000000000001"}]\n' ;;
  *) exit 0 ;;
esac
MOCK
chmod +x "$MOCK_TASK_DIR/task"

TRANSCRIPT=$(make_transcript 10 "im done for now")
output=$(run_hook_with_task_bin "$MOCK_TASK_DIR/task" "sess-tw-tasks" "$REPO_WITH_RULES" "$TRANSCRIPT")
assert_contains "open tasks → reason mentions taskwarrior sync cue" 'taskwarrior' "$output"
assert_contains "open tasks → reason still references session-plugin:session-end" 'session-plugin:session-end' "$output"
assert_contains "open tasks → reason still instructs offer-only" 'never run it without explicit user confirmation' "$output"
assert_contains "open tasks → reason mentions stable UUID pattern" 'task +LATEST uuids' "$output"

# When the task stub returns an empty list, the sync cue must NOT appear.
MOCK_TASK_EMPTY_DIR=$(mktemp -d) || { echo "mktemp -d failed" >&2; exit 1; }
cat > "$MOCK_TASK_EMPTY_DIR/task" <<'MOCK'
#!/bin/sh
# Task stub: returns empty list for all calls.
case "$*" in
  *export*) printf '[]\n' ;;
  *) exit 0 ;;
esac
MOCK
chmod +x "$MOCK_TASK_EMPTY_DIR/task"

# Use a fresh session ID so the once-per-session marker doesn't suppress.
output=$(run_hook_with_task_bin "$MOCK_TASK_EMPTY_DIR/task" "sess-tw-empty" "$REPO_WITH_RULES" "$TRANSCRIPT")
# Hook must still fire (tasks stub means taskwarrior is "present" → has_surface=1)
assert_contains "empty task list → hook still fires" '"decision":"block"' "$output"
# But the taskwarrior sync cue text must not appear in the reason
if echo "$output" | grep -q 'task +LATEST uuids'; then
    printf "  FAIL: empty task list should NOT include UUID sync cue\n"; FAIL=$((FAIL + 1))
else
    printf "  PASS: empty task list does NOT include UUID sync cue\n"; PASS=$((PASS + 1))
fi

rm -rf "$MOCK_TASK_DIR" "$MOCK_TASK_EMPTY_DIR"
rm -f "$TRANSCRIPT"

echo ""
echo "=== Results: ${PASS} passed, ${FAIL} failed ==="
[ "$FAIL" -gt 0 ] && exit 1
exit 0
