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
TMPDIR=$(mktemp -d) || { echo "mktemp -d failed" >&2; exit 1; }
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

# shellcheck disable=SC2016  # literal $(...) is intentional test-fixture data, not an expansion
MULTILINE_BODY_HEREDOC=$(printf 'gh pr create --title "feat: add feature" --body "$(cat <<'"'"'EOF'"'"'\n## Summary\nAdd feature.\n\nCloses #42\nEOF\n)"')
assert_exit \
    "heredoc-style body with Closes keyword is allowed" 0 \
    "$(make_json "$MULTILINE_BODY_HEREDOC")"

# ── Unresolvable body forms with literal keyword in command (regression) ─────
# Regression (issue #1489): the hook could not resolve the body at PreToolUse
# time for three common invocations and emitted false-positive blocks, even
# though the closing keyword was present literally in the command string.
echo ""
echo "unresolvable body forms carrying the keyword in the command (issue #1489):"

# 1. ANSI-C ($'...') quoted body — perl --body '...'/"..." regexes never matched
ANSIC_BODY=$(printf "gh pr create --title 'feat: add feature' --body \$'## Summary\\\\n\\\\nCloses #42'")
assert_exit \
    "ANSI-C quoted (\$'...') body with Closes keyword is allowed" 0 \
    "$(make_json "$ANSIC_BODY")"

# 2. Command substitution reading a separate file: --body "$(cat external.md)".
#    The literal $(cat ...) text has no keyword, but the agent put Closes #42 in
#    the same command's heredoc — keyword is in the command string.
# shellcheck disable=SC2016  # literal $(...) is intentional test-fixture data, not an expansion
CMDSUB_BODY=$(printf 'gh pr create --title "feat: add feature" --body "$(printf %%s "## Summary\nCloses #42")"')
assert_exit \
    "command-substitution body with literal Closes keyword in command is allowed" 0 \
    "$(make_json "$CMDSUB_BODY")"

# 3. Heredoc writes the --body-file in the SAME compound command, so the file
#    does not exist on disk when the PreToolUse hook runs.
SAME_CMD_BODYFILE=$(printf 'cat > /tmp/pr-body-%s.md <<EOF\n## Summary\n\nCloses #42\nEOF\ngh pr create --title "feat: add feature" --body-file /tmp/pr-body-%s.md' "$$" "$$")
assert_exit \
    "same-command heredoc body-file (file not yet written) is allowed" 0 \
    "$(make_json "$SAME_CMD_BODYFILE")"

# ── -F / --body-file resolvable at hook time (regression: issue #1913) ──────
# Regression (issue #1913): a compliant PR created with the -F short alias for
# --body-file — where the body file contains Closes #N — was false-blocked
# because the guard/extraction only recognized the long --body-file form. All
# resolvable -F forms whose file carries the keyword must be allowed.
echo ""
echo "-F / --body-file alias with keyword in the file (issue #1913):"

BODYFILE=$(mktemp)
printf '## Summary\n\nCloses #42\n' > "$BODYFILE"
# shellcheck disable=SC2064  # expand BODYFILE now so the trap removes this exact file
trap "rm -rf '$TMPDIR' '$BODYFILE'" EXIT

assert_exit \
    "-F <file> (space form) with Closes in the file is allowed" 0 \
    "$(make_json "gh pr create --title 'feat: add feature' -F $BODYFILE")"

assert_exit \
    "-F<file> (attached form) with Closes in the file is allowed" 0 \
    "$(make_json "gh pr create --title 'feat: add feature' -F$BODYFILE")"

assert_exit \
    "-F=<file> (equals form) with Closes in the file is allowed" 0 \
    "$(make_json "gh pr create --title 'feat: add feature' -F=$BODYFILE")"

# ── Unresolvable body-file/-F paths defer, not block (issue #1913) ──────────
# When a body-file/-F path cannot be read at PreToolUse time (missing file or
# stdin sentinel), the keyword may live inside it — defer (exit 0) rather than
# emit a false-positive block.
echo ""
echo "unresolvable body-file/-F paths defer instead of blocking (issue #1913):"

assert_exit \
    "--body-file <missing> defers (file unreadable at hook time)" 0 \
    "$(make_json "gh pr create --title 'feat: add feature' --body-file /nonexistent/pr-body-$$.md")"

assert_exit \
    "-F - (stdin) defers (cannot resolve stdin at hook time)" 0 \
    "$(make_json "gh pr create --title 'feat: add feature' -F -")"

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

# A readable -F body file that genuinely lacks a closing keyword must still
# block when commits reference an issue — the #1913 fix must not defer here.
BODYFILE_NOKEY=$(mktemp)
printf '## Summary\n\nNo closing keyword here.\n' > "$BODYFILE_NOKEY"
# shellcheck disable=SC2064  # expand the filenames now so the trap removes these exact files
trap "rm -rf '$TMPDIR' '$BODYFILE' '$BODYFILE_NOKEY'" EXIT
assert_exit \
    "-F <file> whose readable content lacks closing keywords is blocked" 2 \
    "$(make_json "gh pr create --title 'feat: add feature' -F $BODYFILE_NOKEY")"

# ── Summary ─────────────────────────────────────────────────────────────────
echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
