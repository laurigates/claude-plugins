#!/usr/bin/env bash
# Regression tests for validate-pr-issue-links.sh
#
# Run: bash git-plugin/hooks/test-validate-pr-issue-links.sh
# Exit 0 = all tests pass, Exit 1 = failures
set -euo pipefail

HOOK="$(dirname "$0")/validate-pr-issue-links.sh"
PASS=0
FAIL=0

# Create a temporary git repo with a commit referencing an issue
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

make_json() {
    local cmd="$1"
    # Use jq to safely encode the command string (handles newlines, quotes)
    jq -n --arg cmd "$cmd" --arg cwd "$TMPDIR" \
        '{"tool_name":"Bash","tool_input":{"command":$cmd},"cwd":$cwd}'
}

echo "=== validate-pr-issue-links hook tests ==="

# ── Non-PR commands should pass through ─────────────────────────────────────
echo ""
echo "guard clause (non-PR commands pass through):"

assert_exit \
    "non-gh command is allowed" 0 \
    "$(make_json "ls -la")"

assert_exit \
    "gh pr view is allowed" 0 \
    "$(make_json "gh pr view 123")"

# ── Single-line body with closing keywords ──────────────────────────────────
echo ""
echo "single-line body with closing keywords:"

assert_exit \
    "single-line body with Closes keyword is allowed" 0 \
    "$(make_json "gh pr create --title 'feat: add feature' --body 'Summary here. Closes #42'")"

assert_exit \
    "single-line body with Fixes keyword is allowed" 0 \
    "$(make_json "gh pr create --title 'fix: bug' --body 'Summary here. Fixes #42'")"

# ── Multi-line body with closing keywords (regression) ──────────────────────
# Regression: multi-line --body content was not matched because perl -ne
# processes line-by-line, so the opening quote on one line and closing quote
# on another line never matched the regex pattern.
echo ""
echo "multi-line body with closing keywords (regression fix):"

MULTILINE_BODY_DQ=$(printf 'gh pr create --title "feat: add feature" --body "## Summary\nAdd feature.\n\nCloses #42"')
assert_exit \
    "multi-line double-quoted body with Closes keyword is allowed" 0 \
    "$(make_json "$MULTILINE_BODY_DQ")"

MULTILINE_BODY_SQ=$(printf "gh pr create --title 'feat: add feature' --body '## Summary\nAdd feature.\n\nCloses #42'")
assert_exit \
    "multi-line single-quoted body with Closes keyword is allowed" 0 \
    "$(make_json "$MULTILINE_BODY_SQ")"

MULTILINE_BODY_HEREDOC=$(printf 'gh pr create --title "feat: add feature" --body "$(cat <<'"'"'EOF'"'"'\n## Summary\nAdd feature.\n\nCloses #42\nEOF\n)"')
assert_exit \
    "heredoc-style body with Closes keyword is allowed" 0 \
    "$(make_json "$MULTILINE_BODY_HEREDOC")"

# ── Missing closing keywords should block ───────────────────────────────────
echo ""
echo "missing closing keywords (should block):"

assert_exit \
    "body without closing keywords is blocked" 2 \
    "$(make_json "gh pr create --title 'feat: add feature' --body 'Just a summary'")"

MULTILINE_NO_CLOSE=$(printf 'gh pr create --title "feat: add feature" --body "## Summary\nAdd feature.\n\n## Changes\n- Did things"')
assert_exit \
    "multi-line body without closing keywords is blocked" 2 \
    "$(make_json "$MULTILINE_NO_CLOSE")"

# ── Summary ─────────────────────────────────────────────────────────────────
echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
