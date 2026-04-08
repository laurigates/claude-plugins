#!/usr/bin/env bash
# Regression tests for task-completeness.sh
#
# Verifies that the Stop hook detects incomplete work without leaking
# the full prompt text in error output (issue #1009).
#
# Run: bash hooks-plugin/hooks/test-task-completeness.sh
# Exit 0 = all tests pass, Exit 1 = failures
set -euo pipefail

HOOK="$(dirname "$0")/task-completeness.sh"
PASS=0
FAIL=0

# Create temporary directories for testing
TMPDIR=$(mktemp -d)
NON_GIT_DIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR" "$NON_GIT_DIR"' EXIT

# Initialize git repo for tests
git -C "$TMPDIR" init -q
git -C "$TMPDIR" config user.email "test@example.com"
git -C "$TMPDIR" config user.name "Test"
echo "initial" > "$TMPDIR/README.md"
git -C "$TMPDIR" add README.md
git -C "$TMPDIR" commit -q -m "initial"

# Helper: run hook with a given CWD JSON and optional extra fields
# Returns the exit code as stdout
run_hook() {
    local cwd="$1"
    local extra="${2:-}"
    local json exit_code=0
    if [ -n "$extra" ]; then
        json=$(printf '{"cwd":"%s",%s}' "$cwd" "$extra")
    else
        json=$(printf '{"cwd":"%s"}' "$cwd")
    fi
    printf '%s' "$json" | bash "$HOOK" >/dev/null 2>&1 || exit_code=$?
    echo "$exit_code"
}

# Helper: run hook and capture stdout (the JSON output)
run_hook_output() {
    local cwd="$1"
    local extra="${2:-}"
    local json exit_code=0
    if [ -n "$extra" ]; then
        json=$(printf '{"cwd":"%s",%s}' "$cwd" "$extra")
    else
        json=$(printf '{"cwd":"%s"}' "$cwd")
    fi
    printf '%s' "$json" | bash "$HOOK" 2>/dev/null || true
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
        printf "  FAIL: %s (expected pattern '%s', output was: %s)\n" "$desc" "$pattern" "$actual"
        FAIL=$((FAIL + 1))
    fi
}

assert_not_contains() {
    local desc="$1" pattern="$2" actual="$3"
    if echo "$actual" | grep -q "$pattern"; then
        printf "  FAIL: %s (found forbidden '%s' in: %s)\n" "$desc" "$pattern" "$actual"
        FAIL=$((FAIL + 1))
    else
        printf "  PASS: %s\n" "$desc"
        PASS=$((PASS + 1))
    fi
}

echo "=== task-completeness hook tests ==="

# ── stop_hook_active guard ────────────────────────────────────────────────────
# Regression: must pass immediately when stop_hook_active=true to prevent
# infinite loops where the hook blocks and Claude tries again.
echo ""
echo "stop_hook_active guard:"

exit_code=$(run_hook "$TMPDIR" '"stop_hook_active":true')
assert_exit "stop_hook_active=true exits 0 (no blocking)" 0 "$exit_code"

# ── clean working tree ────────────────────────────────────────────────────────
echo ""
echo "clean working tree:"

exit_code=$(run_hook "$TMPDIR")
assert_exit "clean tree exits 0" 0 "$exit_code"

# ── TODO/FIXME markers in uncommitted changes ─────────────────────────────────
# Regression: the old prompt hook leaked the full LLM prompt in error output
# (issue #1009). The command hook must only emit {"decision":"block","reason":"..."}
echo ""
echo "TODO/FIXME/HACK/XXX detection:"

echo "# TODO: finish this" >> "$TMPDIR/README.md"

exit_code=$(run_hook "$TMPDIR")
assert_exit "unstaged TODO exits 2 (blocked)" 2 "$exit_code"

output=$(run_hook_output "$TMPDIR")
assert_contains     "blocked output has 'decision' field"       '"decision"'        "$output"
assert_contains     "blocked output has 'reason' field"         '"reason"'          "$output"
assert_not_contains "output does not leak prompt text"          "You are evaluating" "$output"
assert_not_contains "output does not leak stop_hook_active text" "stop_hook_active"  "$output"

git -C "$TMPDIR" checkout -- README.md  # restore clean state

# Staged TODO
echo "# FIXME: broken" >> "$TMPDIR/README.md"
git -C "$TMPDIR" add README.md

exit_code=$(run_hook "$TMPDIR")
assert_exit "staged FIXME exits 2 (blocked)" 2 "$exit_code"

git -C "$TMPDIR" restore --staged README.md 2>/dev/null || git -C "$TMPDIR" reset HEAD README.md 2>/dev/null || true
git -C "$TMPDIR" checkout -- README.md

# ── merge conflict markers ────────────────────────────────────────────────────
echo ""
echo "merge conflict marker detection:"

cat > "$TMPDIR/conflict.txt" <<'CONFLICT'
<<<<<<< HEAD
local change
=======
remote change
>>>>>>> main
CONFLICT
git -C "$TMPDIR" add conflict.txt

exit_code=$(run_hook "$TMPDIR")
assert_exit "staged conflict markers exits 2 (blocked)" 2 "$exit_code"

output=$(run_hook_output "$TMPDIR")
assert_contains     "conflict output has 'decision' field"      '"decision"'         "$output"
assert_not_contains "conflict output does not leak prompt text" "Respond with ONLY"  "$output"

git -C "$TMPDIR" restore --staged conflict.txt 2>/dev/null || git -C "$TMPDIR" reset HEAD conflict.txt 2>/dev/null || true
rm -f "$TMPDIR/conflict.txt"

# ── debugging artifacts ───────────────────────────────────────────────────────
echo ""
echo "debugging artifact detection:"

echo "console.log('debug', x);" >> "$TMPDIR/app.js"
git -C "$TMPDIR" add app.js

exit_code=$(run_hook "$TMPDIR")
assert_exit "staged console.log exits 2 (blocked)" 2 "$exit_code"

git -C "$TMPDIR" restore --staged app.js 2>/dev/null || git -C "$TMPDIR" reset HEAD app.js 2>/dev/null || true
rm -f "$TMPDIR/app.js"

echo "debugger;" >> "$TMPDIR/app.js"
git -C "$TMPDIR" add app.js

exit_code=$(run_hook "$TMPDIR")
assert_exit "staged 'debugger;' exits 2 (blocked)" 2 "$exit_code"

git -C "$TMPDIR" restore --staged app.js 2>/dev/null || git -C "$TMPDIR" reset HEAD app.js 2>/dev/null || true
rm -f "$TMPDIR/app.js"

# ── edge cases ────────────────────────────────────────────────────────────────
echo ""
echo "edge cases:"

exit_code=$(run_hook "$NON_GIT_DIR")
assert_exit "non-git directory exits 0" 0 "$exit_code"

empty_exit=0
printf '{}' | bash "$HOOK" >/dev/null 2>&1 || empty_exit=$?
assert_exit "missing cwd field exits 0" 0 "$empty_exit"

# ── disable via environment variable ─────────────────────────────────────────
echo ""
echo "CLAUDE_HOOKS_DISABLE_TASK_COMPLETENESS override:"

echo "# TODO: should be ignored" >> "$TMPDIR/README.md"
override_exit=0
printf '{"cwd":"%s"}' "$TMPDIR" | CLAUDE_HOOKS_DISABLE_TASK_COMPLETENESS=1 bash "$HOOK" >/dev/null 2>&1 || override_exit=$?
assert_exit "CLAUDE_HOOKS_DISABLE_TASK_COMPLETENESS=1 skips checks" 0 "$override_exit"
git -C "$TMPDIR" checkout -- README.md

# ── Summary ──────────────────────────────────────────────────────────────────
echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
