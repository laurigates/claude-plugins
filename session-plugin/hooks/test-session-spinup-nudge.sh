#!/usr/bin/env bash
# Regression tests for session-spinup-nudge.sh
#
# Verifies the SessionStart nudge fires only on startup/resume with genuine
# open threads (dirty tree, unpushed commits, or open taskwarrior tasks),
# injects additionalContext (never a block), and stays silent on clean state.
#
# Semantic invariant: when the hook fires, the JSON must mention
# session-plugin:session-spinup literally.
#
# Run: bash session-plugin/hooks/test-session-spinup-nudge.sh
set -euo pipefail

HOOK="$(dirname "$0")/session-spinup-nudge.sh"
PASS=0
FAIL=0

TEST_HOME=$(mktemp -d) || { echo "mktemp -d failed" >&2; exit 1; }
REPO_CLEAN=$(mktemp -d) || { echo "mktemp -d failed" >&2; exit 1; }
REPO_DIRTY=$(mktemp -d) || { echo "mktemp -d failed" >&2; exit 1; }
trap 'rm -rf "$TEST_HOME" "$REPO_CLEAN" "$REPO_DIRTY"' EXIT

for repo in "$REPO_CLEAN" "$REPO_DIRTY"; do
    git -C "$repo" init -q
    git -C "$repo" -c user.email=t@t -c user.name=t commit -q --allow-empty -m init
done
echo "wip" > "$REPO_DIRTY/wip.txt"

run_hook_output() {
    local session_id="$1" cwd="$2" source_kind="$3" gh_bin="${4:-/nonexistent/gh}"
    jq -nc --arg sid "$session_id" --arg cwd "$cwd" --arg src "$source_kind" \
        '{session_id: $sid, cwd: $cwd, source: $src}' \
        | HOME="$TEST_HOME" SESSION_NUDGE_TASK_BIN=/nonexistent/task \
          SESSION_NUDGE_GH_BIN="$gh_bin" \
          bash "$HOOK" 2>/dev/null || true
}

# Stub gh: `auth status` succeeds; `issue list` emits a JSON array sized by
# GH_STUB_ISSUE_COUNT (0 = empty, so the issue signal stays silent). The hook
# now delegates to the collector, which calls `gh issue list --json ...`, so
# the stub must emit JSON, not a bare integer.
GH_STUB_DIR=$(mktemp -d) || { echo "mktemp -d failed" >&2; exit 1; }
trap 'rm -rf "$TEST_HOME" "$REPO_CLEAN" "$REPO_DIRTY" "$GH_STUB_DIR"' EXIT
cat > "$GH_STUB_DIR/gh" <<'STUB'
#!/usr/bin/env bash
case "$1 $2" in
    "auth status") exit 0 ;;
    "issue list")
        n="${GH_STUB_ISSUE_COUNT:-0}"
        printf '['
        for i in $(seq 1 "$n" 2>/dev/null); do
            [ "$i" -gt 1 ] && printf ','
            printf '{"number":%d,"title":"issue %d","url":"http://x/%d","updatedAt":"2026-06-22T10:00:00Z"}' "$i" "$i" "$i"
        done
        printf ']'
        ;;
    "pr list") echo "[]" ;;
    *) echo "[]" ;;
esac
STUB
chmod +x "$GH_STUB_DIR/gh"

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
    if [ -n "$actual" ]; then
        printf "  FAIL: %s (hook emitted: %s)\n" "$desc" "$actual"; FAIL=$((FAIL + 1))
    else
        printf "  PASS: %s\n" "$desc"; PASS=$((PASS + 1))
    fi
}

echo "=== session-spinup-nudge hook tests ==="

echo ""
echo "source gate:"
output=$(run_hook_output "sp-clear" "$REPO_DIRTY" "clear")
assert_silent "source=clear is silent" "$output"
output=$(run_hook_output "sp-compact" "$REPO_DIRTY" "compact")
assert_silent "source=compact is silent" "$output"

echo ""
echo "clean state stays silent:"
output=$(run_hook_output "sp-clean" "$REPO_CLEAN" "startup")
assert_silent "clean repo without taskwarrior threads is silent" "$output"

echo ""
echo "open threads fire additionalContext (never a block):"
output=$(run_hook_output "sp-dirty" "$REPO_DIRTY" "startup")
assert_contains "dirty tree emits additionalContext" 'additionalContext' "$output"
assert_contains "context references session-plugin:session-spinup" 'session-plugin:session-spinup' "$output"
assert_contains "context mentions uncommitted changes" 'uncommitted changes' "$output"
if echo "$output" | grep -q '"decision"'; then
    printf "  FAIL: spinup nudge must not emit a decision/block\n"; FAIL=$((FAIL + 1))
else
    printf "  PASS: spinup nudge does not block\n"; PASS=$((PASS + 1))
fi

echo ""
echo "GitHub issues signal (gh-auth-gated):"
export GH_STUB_ISSUE_COUNT=0
output=$(run_hook_output "sp-gh-zero" "$REPO_CLEAN" "startup" "$GH_STUB_DIR/gh")
assert_silent "clean repo + zero assigned issues stays silent" "$output"
export GH_STUB_ISSUE_COUNT=2
output=$(run_hook_output "sp-gh-two" "$REPO_CLEAN" "startup" "$GH_STUB_DIR/gh")
assert_contains "assigned issues emit additionalContext" 'additionalContext' "$output"
assert_contains "context mentions assigned GitHub issue(s)" 'assigned GitHub issue' "$output"
assert_contains "issue-only nudge still references the skill" 'session-plugin:session-spinup' "$output"
unset GH_STUB_ISSUE_COUNT

echo ""
echo "unauthenticated gh adds no thread (gate holds):"
# /nonexistent/gh fails `command -v`, so the issue block is skipped entirely.
output=$(run_hook_output "sp-gh-noauth" "$REPO_CLEAN" "startup" "/nonexistent/gh")
assert_silent "clean repo + no gh binary stays silent" "$output"

echo ""
echo "once-per-session marker:"
output=$(run_hook_output "sp-dirty" "$REPO_DIRTY" "startup")
assert_silent "second call in same session is silent" "$output"

echo ""
echo "=== Results: ${PASS} passed, ${FAIL} failed ==="
[ "$FAIL" -gt 0 ] && exit 1
exit 0
