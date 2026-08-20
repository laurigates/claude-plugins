#!/usr/bin/env bash
# Regression tests for skill-usage-log.sh
#
# Verifies that the logger:
#  - Records a model-invoked skill (PreToolUse Skill) with plugin split out.
#  - Records a user-typed slash command (UserPromptSubmit), raw and wrapped.
#  - Ignores non-skill tools, plain prompts, and bare "/" or path-like tokens.
#  - Emits valid JSON even when args contain quotes and newlines.
#  - Writes NOTHING to stdout on any path — a UserPromptSubmit hook's stdout is
#    injected into the model's context, so a stray byte leaks into every turn.
#  - Stays silent when CLAUDE_HOOKS_ENABLE_SKILL_USAGE_LOG is unset (opt-in).
#
# The payload shapes below are taken from real transcripts, not invented:
# `{"skill": "...", "args": "..."}` is the observed Skill tool_input in
# ~/.claude/projects/**/*.jsonl (170 occurrences, 108 of them with args).
#
# Run: bash hooks-plugin/hooks/test-skill-usage-log.sh
# Exit 0 = all tests pass, Exit 1 = failures
set -uo pipefail

HOOK="$(dirname "$0")/skill-usage-log.sh"
PASS=0
FAIL=0

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
LOG="$WORK/skill-usage.jsonl"

# Run the hook on one payload; returns its stdout, appends to $LOG.
run_hook() {
    printf '%s' "$1" \
        | CLAUDE_SKILL_USAGE_LOG="$LOG" \
          CLAUDE_HOOKS_ENABLE_SKILL_USAGE_LOG=1 \
          bash "$HOOK" 2>/dev/null
}

reset_log() { : > "$LOG"; }
records() { [ -f "$LOG" ] && wc -l < "$LOG" | tr -d ' ' || echo 0; }
last_field() { jq -r "$1" < "$LOG" | tail -1; }

check() {
    local desc="$1" expected="$2" actual="$3"
    if [ "$expected" = "$actual" ]; then
        PASS=$((PASS + 1))
        echo "  PASS: $desc"
    else
        FAIL=$((FAIL + 1))
        echo "  FAIL: $desc"
        echo "        expected: $expected"
        echo "        actual:   $actual"
    fi
}

echo "=== skill-usage-log.sh ==="

# --- 1. Model-invoked skill via the Skill tool -------------------------------
reset_log
OUT=$(run_hook '{"hook_event_name":"PreToolUse","tool_name":"Skill","session_id":"sess-1","cwd":"/tmp","permission_mode":"default","tool_input":{"skill":"git-plugin:git-pr","args":"draft"}}')
check "Skill tool logs one record" "1" "$(records)"
check "  skill recorded" "git-plugin:git-pr" "$(last_field '.skill')"
check "  plugin split out" "git-plugin" "$(last_field '.plugin')"
check "  src=tool" "tool" "$(last_field '.src')"
check "  args recorded" "draft" "$(last_field '.args')"
check "  session recorded" "sess-1" "$(last_field '.session')"
check "  no stdout" "" "$OUT"

# --- 2. Skill tool without args (observed shape) -----------------------------
reset_log
run_hook '{"hook_event_name":"PreToolUse","tool_name":"Skill","session_id":"s","cwd":"/tmp","tool_input":{"skill":"git-plugin:deadbranch"}}' >/dev/null
check "Skill tool without args still logs" "1" "$(records)"
check "  args empty, length 0" "0" "$(last_field '.args_len')"

# --- 3. Unnamespaced skill ---------------------------------------------------
reset_log
run_hook '{"hook_event_name":"PreToolUse","tool_name":"Skill","session_id":"s","cwd":"/tmp","tool_input":{"skill":"artifact-design"}}' >/dev/null
check "unnamespaced skill logs plugin=-" "-" "$(last_field '.plugin')"

# --- 4. Non-skill tool is ignored -------------------------------------------
reset_log
OUT=$(run_hook '{"hook_event_name":"PreToolUse","tool_name":"Bash","session_id":"s","cwd":"/tmp","tool_input":{"command":"ls"}}')
check "Bash tool logs nothing" "0" "$(records)"
check "  no stdout" "" "$OUT"

# --- 5. User-typed slash command --------------------------------------------
reset_log
OUT=$(run_hook '{"hook_event_name":"UserPromptSubmit","session_id":"s","cwd":"/tmp","prompt":"/session-plugin:session-end wrap it up"}')
check "slash command logs one record" "1" "$(records)"
check "  skill recorded" "session-plugin:session-end" "$(last_field '.skill')"
check "  src=slash" "slash" "$(last_field '.src')"
check "  args recorded" "wrap it up" "$(last_field '.args')"
check "  no stdout (context-injection guard)" "" "$OUT"

# --- 6. Wrapped <command-name> form -----------------------------------------
reset_log
run_hook '{"hook_event_name":"UserPromptSubmit","session_id":"s","cwd":"/tmp","prompt":"<command-message>x</command-message>\n<command-name>/git-plugin:git-triage</command-name>"}' >/dev/null
check "wrapped command-name form parsed" "git-plugin:git-triage" "$(last_field '.skill')"

# --- 7. Plain prompts and path-like tokens are ignored -----------------------
reset_log
run_hook '{"hook_event_name":"UserPromptSubmit","session_id":"s","cwd":"/tmp","prompt":"what does this repo do?"}' >/dev/null
check "plain prompt logs nothing" "0" "$(records)"
run_hook '{"hook_event_name":"UserPromptSubmit","session_id":"s","cwd":"/tmp","prompt":"/tmp/foo.txt is the file"}' >/dev/null
check "path-like first token logs nothing" "0" "$(records)"
run_hook '{"hook_event_name":"UserPromptSubmit","session_id":"s","cwd":"/tmp","prompt":"/"}' >/dev/null
check "bare slash logs nothing" "0" "$(records)"

# --- 8. Unrelated events are ignored ----------------------------------------
reset_log
run_hook '{"hook_event_name":"SessionStart","session_id":"s","cwd":"/tmp"}' >/dev/null
check "SessionStart logs nothing" "0" "$(records)"

# --- 9. Hostile args stay valid JSON ----------------------------------------
reset_log
run_hook '{"hook_event_name":"PreToolUse","tool_name":"Skill","session_id":"s","cwd":"/tmp","tool_input":{"skill":"x:y","args":"he said \"hi\"\nthen {\"a\":1}"}}' >/dev/null
check "quotes/newlines in args stay one valid record" "1" "$(records)"
if jq -e . < "$LOG" >/dev/null 2>&1; then
    check "  record parses as JSON" "ok" "ok"
else
    check "  record parses as JSON" "ok" "invalid"
fi

# --- 10. Opt-in guard --------------------------------------------------------
# Unset explicitly: the developer's shell may export the opt-in var, which would
# make this pass locally for the wrong reason.
reset_log
printf '%s' '{"hook_event_name":"PreToolUse","tool_name":"Skill","session_id":"s","cwd":"/tmp","tool_input":{"skill":"a:b"}}' \
    | env -u CLAUDE_HOOKS_ENABLE_SKILL_USAGE_LOG CLAUDE_SKILL_USAGE_LOG="$LOG" bash "$HOOK" >/dev/null 2>&1
check "disabled by default (opt-in)" "0" "$(records)"

# --- 11. Control: the fixture itself is capable of failing -------------------
# Without this, every "logs nothing" assertion above would also pass if the
# hook were broken outright.
reset_log
run_hook '{"hook_event_name":"PreToolUse","tool_name":"Skill","session_id":"s","cwd":"/tmp","tool_input":{"skill":"control:probe"}}' >/dev/null
check "control: harness observes a real write" "control:probe" "$(last_field '.skill')"

echo
echo "Passed: $PASS  Failed: $FAIL"
[ "$FAIL" -eq 0 ]
