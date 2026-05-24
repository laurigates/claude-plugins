#!/usr/bin/env bash
# Regression tests for project-distill-nudge.sh
#
# Verifies that the Stop hook nudges /project:distill only when all three
# filters pass (turn count >= 8, repo has distillable surface, recent user
# turn carries a wind-down phrase) and stays silent otherwise.
#
# Semantic invariant (per .claude/rules/regression-testing.md): when the
# hook fires, the emitted JSON must mention /project:distill literally so
# downstream prose edits cannot silently break the nudge contract.
#
# Run: bash project-plugin/hooks/test-project-distill-nudge.sh
# Exit 0 = all tests pass, Exit 1 = failures
set -euo pipefail

HOOK="$(dirname "$0")/project-distill-nudge.sh"
PASS=0
FAIL=0

# Use a per-test state directory so this run cannot collide with a real
# session's nudge marker. Override the HOME the hook sees.
TEST_HOME=$(mktemp -d)
REPO_WITH_RULES=$(mktemp -d)
REPO_WITH_JUSTFILE=$(mktemp -d)
REPO_PLAIN=$(mktemp -d)
trap 'rm -rf "$TEST_HOME" "$REPO_WITH_RULES" "$REPO_WITH_JUSTFILE" "$REPO_PLAIN"' EXIT

# REPO_WITH_RULES: has .claude/rules/, no justfile
git -C "$REPO_WITH_RULES" init -q
mkdir -p "$REPO_WITH_RULES/.claude/rules"
echo "# rule" > "$REPO_WITH_RULES/.claude/rules/example.md"

# REPO_WITH_JUSTFILE: has justfile, no .claude/rules/
git -C "$REPO_WITH_JUSTFILE" init -q
printf 'default:\n\t@echo ok\n' > "$REPO_WITH_JUSTFILE/justfile"

# REPO_PLAIN: no distillable surface
git -C "$REPO_PLAIN" init -q
echo "# readme" > "$REPO_PLAIN/README.md"

# Build a fake transcript file with N user messages and an optional final
# user phrase. Each line is a minimal JSONL record carrying role=user.
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

# Run the hook with a synthetic input JSON. Returns exit code via stdout.
run_hook() {
    local session_id="$1"
    local cwd="$2"
    local transcript="$3"
    local extra="${4:-}"
    local json exit_code=0
    if [ -n "$extra" ]; then
        json=$(jq -nc \
            --arg sid "$session_id" \
            --arg cwd "$cwd" \
            --arg tp "$transcript" \
            "{session_id: \$sid, cwd: \$cwd, transcript_path: \$tp, $extra}")
    else
        json=$(jq -nc \
            --arg sid "$session_id" \
            --arg cwd "$cwd" \
            --arg tp "$transcript" \
            '{session_id: $sid, cwd: $cwd, transcript_path: $tp}')
    fi
    printf '%s' "$json" | HOME="$TEST_HOME" bash "$HOOK" >/dev/null 2>&1 || exit_code=$?
    echo "$exit_code"
}

run_hook_output() {
    local session_id="$1"
    local cwd="$2"
    local transcript="$3"
    local extra="${4:-}"
    local json
    if [ -n "$extra" ]; then
        json=$(jq -nc \
            --arg sid "$session_id" \
            --arg cwd "$cwd" \
            --arg tp "$transcript" \
            "{session_id: \$sid, cwd: \$cwd, transcript_path: \$tp, $extra}")
    else
        json=$(jq -nc \
            --arg sid "$session_id" \
            --arg cwd "$cwd" \
            --arg tp "$transcript" \
            '{session_id: $sid, cwd: $cwd, transcript_path: $tp}')
    fi
    printf '%s' "$json" | HOME="$TEST_HOME" bash "$HOOK" 2>/dev/null || true
}

assert_exit() {
    local desc="$1" expected="$2" actual="$3"
    if [ "$actual" -eq "$expected" ]; then
        printf "  PASS: %s\n" "$desc"
        PASS=$((PASS + 1))
    else
        printf "  FAIL: %s (expected exit %d, got %d)\n" "$desc" "$expected" "$actual"
        FAIL=$((FAIL + 1))
    fi
}

assert_contains() {
    local desc="$1" pattern="$2" actual="$3"
    if echo "$actual" | grep -q "$pattern"; then
        printf "  PASS: %s\n" "$desc"
        PASS=$((PASS + 1))
    else
        printf "  FAIL: %s (expected '%s' in: %s)\n" "$desc" "$pattern" "$actual"
        FAIL=$((FAIL + 1))
    fi
}

assert_not_contains() {
    local desc="$1" pattern="$2" actual="$3"
    if echo "$actual" | grep -q "$pattern"; then
        printf "  FAIL: %s (forbidden '%s' in: %s)\n" "$desc" "$pattern" "$actual"
        FAIL=$((FAIL + 1))
    else
        printf "  PASS: %s\n" "$desc"
        PASS=$((PASS + 1))
    fi
}

echo "=== project-distill-nudge hook tests ==="

# ── stop_hook_active guard ────────────────────────────────────────────────────
echo ""
echo "stop_hook_active guard:"
TRANSCRIPT=$(make_transcript 10 "wrap up for the day")
exit_code=$(run_hook "sess-loop" "$REPO_WITH_RULES" "$TRANSCRIPT" '"stop_hook_active":true')
assert_exit "stop_hook_active=true exits 0 (no blocking)" 0 "$exit_code"
rm -f "$TRANSCRIPT"

# ── missing session_id / transcript guards ───────────────────────────────────
echo ""
echo "hard guards:"
TRANSCRIPT=$(make_transcript 10 "wrap up for the day")
exit_code=$(printf '{"cwd":"%s","transcript_path":"%s"}' "$REPO_WITH_RULES" "$TRANSCRIPT" \
    | HOME="$TEST_HOME" bash "$HOOK" >/dev/null 2>&1; echo $?)
assert_exit "missing session_id exits 0" 0 "$exit_code"

exit_code=$(printf '{"session_id":"sess-no-tp","cwd":"%s"}' "$REPO_WITH_RULES" \
    | HOME="$TEST_HOME" bash "$HOOK" >/dev/null 2>&1; echo $?)
assert_exit "missing transcript_path exits 0" 0 "$exit_code"

exit_code=$(printf '{"session_id":"sess-bad-tp","cwd":"%s","transcript_path":"/no/such/file"}' \
    "$REPO_WITH_RULES" \
    | HOME="$TEST_HOME" bash "$HOOK" >/dev/null 2>&1; echo $?)
assert_exit "nonexistent transcript exits 0" 0 "$exit_code"
rm -f "$TRANSCRIPT"

# ── turn-count floor ─────────────────────────────────────────────────────────
echo ""
echo "turn-count floor (>=8):"
TRANSCRIPT=$(make_transcript 5 "wrap up for the day")
output=$(run_hook_output "sess-short" "$REPO_WITH_RULES" "$TRANSCRIPT")
assert_not_contains "5 user turns does NOT emit a nudge" '"decision"' "$output"
rm -f "$TRANSCRIPT"

TRANSCRIPT=$(make_transcript 7 "wrap up for the day")
output=$(run_hook_output "sess-just-under" "$REPO_WITH_RULES" "$TRANSCRIPT")
assert_not_contains "7 user turns does NOT emit a nudge" '"decision"' "$output"
rm -f "$TRANSCRIPT"

# ── scope filter: repo with no distillable surface ───────────────────────────
echo ""
echo "scope filter:"
TRANSCRIPT=$(make_transcript 10 "wrap up for the day")
output=$(run_hook_output "sess-plain" "$REPO_PLAIN" "$TRANSCRIPT")
assert_not_contains "repo without .claude/rules/ or justfile does NOT nudge" '"decision"' "$output"
rm -f "$TRANSCRIPT"

# ── wind-down phrase missing ─────────────────────────────────────────────────
echo ""
echo "wind-down phrase:"
TRANSCRIPT=$(make_transcript 10 "what does this function do?")
output=$(run_hook_output "sess-no-windown" "$REPO_WITH_RULES" "$TRANSCRIPT")
assert_not_contains "no wind-down phrase does NOT nudge" '"decision"' "$output"
rm -f "$TRANSCRIPT"

# ── happy paths: all filters pass ────────────────────────────────────────────
echo ""
echo "happy paths (semantic invariant: /project:distill appears in reason):"

TRANSCRIPT=$(make_transcript 10 "wrap up for the day")
output=$(run_hook_output "sess-happy-rules" "$REPO_WITH_RULES" "$TRANSCRIPT")
assert_contains "all filters pass with .claude/rules/ emits block" '"decision":"block"' "$output"
assert_contains "block reason references /project:distill" '/project:distill' "$output"
rm -f "$TRANSCRIPT"

TRANSCRIPT=$(make_transcript 10 "im done for now")
output=$(run_hook_output "sess-happy-just" "$REPO_WITH_JUSTFILE" "$TRANSCRIPT")
assert_contains "all filters pass with justfile emits block" '"decision":"block"' "$output"
assert_contains "block reason references /project:distill" '/project:distill' "$output"
rm -f "$TRANSCRIPT"

# ── once-per-session: state file ─────────────────────────────────────────────
echo ""
echo "once-per-session marker:"
SESS_REPEAT="sess-repeat-$$"
TRANSCRIPT=$(make_transcript 10 "wrap up for the day")
# First call should nudge and create the marker
output=$(run_hook_output "$SESS_REPEAT" "$REPO_WITH_RULES" "$TRANSCRIPT")
assert_contains "first call in session emits block" '"decision":"block"' "$output"
# Second call (same session_id) must NOT nudge
output=$(run_hook_output "$SESS_REPEAT" "$REPO_WITH_RULES" "$TRANSCRIPT")
assert_not_contains "second call in same session is silent" '"decision"' "$output"
rm -f "$TRANSCRIPT"

# ── summary ──────────────────────────────────────────────────────────────────
echo ""
echo "=== Results: ${PASS} passed, ${FAIL} failed ==="

if [ "$FAIL" -gt 0 ]; then
    exit 1
fi
exit 0
