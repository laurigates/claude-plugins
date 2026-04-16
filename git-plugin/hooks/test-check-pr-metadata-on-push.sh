#!/usr/bin/env bash
# Regression tests for check-pr-metadata-on-push.sh
#
# Run: bash git-plugin/hooks/test-check-pr-metadata-on-push.sh
# Exit 0 = all tests pass, Exit 1 = failures
#
# Note: Tests that require gh CLI or an actual PR are guarded
# and skipped when gh is unavailable. Core guard-clause tests
# always run since they exit before reaching gh.
set -euo pipefail

HOOK="$(dirname "$0")/check-pr-metadata-on-push.sh"
PASS=0
FAIL=0
SKIP=0

# Create a temporary git repo
TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

git -C "$TMPDIR" init -q
git -C "$TMPDIR" config commit.gpgsign false
git -C "$TMPDIR" config user.email "test@test.com"
git -C "$TMPDIR" config user.name "Test"
git -C "$TMPDIR" commit --allow-empty -m "initial" -q
git -C "$TMPDIR" checkout -b main -q 2>/dev/null || true
git -C "$TMPDIR" checkout -b feature -q
git -C "$TMPDIR" commit --allow-empty -m "feat: add feature

Closes #42" -q

# Point origin/HEAD at main so merge-base works
git -C "$TMPDIR" remote add origin "$TMPDIR" 2>/dev/null || true
git -C "$TMPDIR" symbolic-ref refs/remotes/origin/HEAD refs/heads/main

assert_exit() {
    local desc="$1" expected="$2"
    local json="$3"
    local exit_code=0
    printf '%s' "$json" | bash "$HOOK" >/dev/null 2>&1 || exit_code=$?
    if [ "$exit_code" -eq "$expected" ]; then
        printf "  PASS: %s\n" "$desc"
        PASS=$((PASS + 1))
    else
        printf "  FAIL: %s (expected exit %d, got %d)\n" "$desc" "$expected" "$exit_code"
        FAIL=$((FAIL + 1))
    fi
}

skip_test() {
    local desc="$1" reason="$2"
    printf "  SKIP: %s (%s)\n" "$desc" "$reason"
    SKIP=$((SKIP + 1))
}

make_json() {
    local cmd="$1"
    local cwd="${2:-$TMPDIR}"
    jq -n --arg cmd "$cmd" --arg cwd "$cwd" \
        '{"tool_name":"Bash","tool_input":{"command":$cmd},"cwd":$cwd}'
}

echo "=== check-pr-metadata-on-push hook tests ==="

# ── Guard clauses: non-push commands pass through ──────────────────────────
echo ""
echo "guard clause (non-push commands pass through):"

assert_exit \
    "non-git command is allowed" 0 \
    "$(make_json "ls -la")"

assert_exit \
    "git status is allowed" 0 \
    "$(make_json "git status")"

assert_exit \
    "git commit is allowed" 0 \
    "$(make_json "git commit -m 'feat: something'")"

assert_exit \
    "git pull is allowed" 0 \
    "$(make_json "git pull origin main")"

assert_exit \
    "git fetch is allowed" 0 \
    "$(make_json "git fetch origin")"

assert_exit \
    "gh pr create is allowed (not a push)" 0 \
    "$(make_json "gh pr create --title 'feat: test'")"

# ── Guard clause: git push detected but no CWD ────────────────────────────
echo ""
echo "guard clause (push without valid cwd):"

assert_exit \
    "git push with empty cwd passes through" 0 \
    '{"tool_name":"Bash","tool_input":{"command":"git push origin main"},"cwd":""}'

assert_exit \
    "git push with non-repo cwd passes through" 0 \
    "$(make_json "git push origin main" "/tmp")"

# ── Guard clause: git push patterns are detected ──────────────────────────
# These test that the regex correctly identifies push commands.
# Since there's no real PR, gh pr view will fail and the hook exits 0.
echo ""
echo "push pattern detection (no PR exists, so these allow through):"

assert_exit \
    "simple git push is detected (no PR, allows)" 0 \
    "$(make_json "git push")"

assert_exit \
    "git push origin branch is detected (no PR, allows)" 0 \
    "$(make_json "git push origin feature")"

assert_exit \
    "git push -u origin branch is detected (no PR, allows)" 0 \
    "$(make_json "git push -u origin feature")"

assert_exit \
    "git push with --force flag is detected (no PR, allows)" 0 \
    "$(make_json "git push --force origin feature")"

assert_exit \
    "chained command with git push is detected (no PR, allows)" 0 \
    "$(make_json "git add . && git push origin feature")"

# ── Guard clause: empty/missing input ─────────────────────────────────────
echo ""
echo "guard clause (empty/missing input):"

assert_exit \
    "empty command passes through" 0 \
    '{"tool_name":"Bash","tool_input":{"command":""},"cwd":"/tmp"}'

assert_exit \
    "missing command field passes through" 0 \
    '{"tool_name":"Bash","tool_input":{},"cwd":"/tmp"}'

# ── Retry-aware bypass: PR updated after HEAD commit ──────────────────────
# Regression test for issue #1041: the hook must NOT block when the PR
# metadata was edited after the latest local commit, because the agent
# (or human) has demonstrably already reconciled metadata for HEAD.
echo ""
echo "retry-aware bypass (PR updatedAt vs HEAD commit time):"

# Mock gh CLI: writes canned PR JSON from $MOCK_PR_JSON
MOCK_BIN=$(mktemp -d)
cat >"$MOCK_BIN/gh" <<'MOCK_EOF'
#!/usr/bin/env bash
# Mock: only handles `gh pr view ...` for these tests.
if [ "${1:-}" = "pr" ] && [ "${2:-}" = "view" ]; then
    if [ -n "${MOCK_PR_JSON:-}" ]; then
        printf '%s' "$MOCK_PR_JSON"
    fi
    exit 0
fi
exit 0
MOCK_EOF
chmod +x "$MOCK_BIN/gh"

# Cross-platform ISO 8601 timestamp helpers (BSD vs GNU date)
iso_offset() {
    local offset_sec="$1"
    if date -u -v"${offset_sec}S" "+%Y-%m-%dT%H:%M:%SZ" 2>/dev/null; then
        return 0
    fi
    date -u -d "${offset_sec} seconds" "+%Y-%m-%dT%H:%M:%SZ"
}

PR_FUTURE=$(iso_offset "+3600")  # 1h ahead of HEAD commit
PR_PAST=$(iso_offset   "-3600")  # 1h behind HEAD commit

# Make `git push origin feature` resolve to a PR via the mock
PUSH_JSON=$(make_json "git push origin feature")

# Test: PR updated AFTER HEAD commit → hook exits 0 (skip block)
MOCK_PR_JSON=$(jq -n --arg t "$PR_FUTURE" \
    '{number:42,title:"feat: x",body:"body",url:"https://example/42",updatedAt:$t}')
PATH="$MOCK_BIN:$PATH" MOCK_PR_JSON="$MOCK_PR_JSON" \
    assert_exit "PR updated after HEAD commit allows push (retry-aware)" 0 "$PUSH_JSON"

# Test: PR updated BEFORE HEAD commit → hook still blocks (exit 2)
MOCK_PR_JSON=$(jq -n --arg t "$PR_PAST" \
    '{number:42,title:"feat: x",body:"body",url:"https://example/42",updatedAt:$t}')
PATH="$MOCK_BIN:$PATH" MOCK_PR_JSON="$MOCK_PR_JSON" \
    assert_exit "PR not updated since HEAD commit still blocks" 2 "$PUSH_JSON"

# Test: missing updatedAt → fall back to legacy block behaviour
MOCK_PR_JSON='{"number":42,"title":"feat: x","body":"body","url":"https://example/42"}'
PATH="$MOCK_BIN:$PATH" MOCK_PR_JSON="$MOCK_PR_JSON" \
    assert_exit "missing updatedAt falls back to blocking" 2 "$PUSH_JSON"

rm -rf "$MOCK_BIN"

# ── Summary ────────────────────────────────────────────────────────────────
echo ""
echo "Results: $PASS passed, $FAIL failed, $SKIP skipped"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
