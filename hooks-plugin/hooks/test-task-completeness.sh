#!/usr/bin/env bash
# Regression tests for task-completeness.sh
#
# Verifies that the Stop hook detects incomplete work without leaking
# the full prompt text in error output (issue #1009).
#
# The hook contract: block by emitting {"decision":"block","reason":"..."}
# on stdout and exit 0 (per hooks-reference.md). Exit 0 with no output =
# allow the stop. The legacy assertions that expected exit 2 were a bug
# in the tests themselves, not the hook.
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
git -C "$TMPDIR" config commit.gpgsign false
git -C "$TMPDIR" config gpg.format ""
echo "initial" > "$TMPDIR/README.md"
git -C "$TMPDIR" add README.md
git -C "$TMPDIR" commit -q -m "initial"

# Reset the test repo to a clean state between scenarios.
reset_repo() {
    git -C "$TMPDIR" restore --staged . 2>/dev/null || true
    git -C "$TMPDIR" checkout -- . 2>/dev/null || true
    git -C "$TMPDIR" clean -fdq 2>/dev/null || true
}

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
    local json
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

reset_repo
exit_code=$(run_hook "$TMPDIR")
assert_exit "clean tree exits 0" 0 "$exit_code"
output=$(run_hook_output "$TMPDIR")
assert_not_contains "clean tree emits no block decision" '"decision"' "$output"

# ── TODO/FIXME markers in source-file diffs ──────────────────────────────────
# Regression: the old prompt hook leaked the full LLM prompt in error output
# (issue #1009). The command hook must only emit {"decision":"block","reason":"..."}.
# Regression (this commit): a previous version grepped the file *content* for
# `^\+...` lines instead of the diff output, so this check was a silent no-op.
echo ""
echo "TODO/FIXME/HACK/XXX detection in source files:"

reset_repo
echo "function foo() { /* TODO: implement */ }" > "$TMPDIR/app.js"
git -C "$TMPDIR" add app.js
output=$(run_hook_output "$TMPDIR")
assert_contains     "staged TODO in app.js emits block decision"   '"decision": "block"' "$output"
assert_contains     "staged TODO message references the count"     'TODO/FIXME/HACK/XXX' "$output"
assert_not_contains "block output does not leak prompt text"       "You are evaluating"  "$output"
assert_not_contains "block output does not leak stop_hook_active"  "stop_hook_active"    "$output"

reset_repo
echo "# FIXME: broken" > "$TMPDIR/app.py"
git -C "$TMPDIR" add app.py
output=$(run_hook_output "$TMPDIR")
assert_contains "staged FIXME in app.py emits block decision" '"decision": "block"' "$output"

# ── markdown / docs files are excluded ───────────────────────────────────────
# Documentation files (this very plugin's README) routinely quote literal
# TODO/FIXME tokens, conflict markers, and console.log examples in prose.
# Treating those as unfinished work is the dominant false-positive class.
echo ""
echo "documentation files are excluded:"

reset_repo
echo "We have a TODO list to track outstanding work." >> "$TMPDIR/README.md"
git -C "$TMPDIR" add README.md
output=$(run_hook_output "$TMPDIR")
assert_not_contains "TODO in README.md does NOT emit a block decision" '"decision"' "$output"

reset_repo
cat > "$TMPDIR/notes.md" <<'NOTES'
Conflict example for the runbook:
<<<<<<< HEAD
local
=======
remote
>>>>>>> main
NOTES
git -C "$TMPDIR" add notes.md
output=$(run_hook_output "$TMPDIR")
assert_not_contains "conflict markers in *.md do NOT emit a block decision" '"decision"' "$output"

reset_repo
echo "Avoid leaving console.log statements in committed code." >> "$TMPDIR/README.md"
git -C "$TMPDIR" add README.md
output=$(run_hook_output "$TMPDIR")
assert_not_contains "console.log in *.md does NOT emit a block decision" '"decision"' "$output"

# Mixed: markdown should be skipped but the source-file change still blocks.
reset_repo
echo "We have a TODO list" >> "$TMPDIR/README.md"
echo "function foo() { /* TODO: implement */ }" > "$TMPDIR/app.js"
git -C "$TMPDIR" add README.md app.js
output=$(run_hook_output "$TMPDIR")
assert_contains "TODO in source still blocks when markdown TODO is also staged" '"decision": "block"' "$output"

# ── merge conflict markers ────────────────────────────────────────────────────
echo ""
echo "merge conflict marker detection:"

reset_repo
cat > "$TMPDIR/conflict.js" <<'CONFLICT'
<<<<<<< HEAD
local change
=======
remote change
>>>>>>> main
CONFLICT
git -C "$TMPDIR" add conflict.js
output=$(run_hook_output "$TMPDIR")
assert_contains     "staged conflict markers emit block decision"  '"decision": "block"' "$output"
assert_contains     "block message names the affected file"        'conflict.js'         "$output"
assert_not_contains "conflict output does not leak prompt text"    "Respond with ONLY"   "$output"

# Regression: standalone `=======` divider lines (decorative separators in
# fenced code blocks, console-output examples, ASCII art) must NOT be flagged
# as merge conflicts. Real conflicts always leave at least one of <<<<<<< or
# >>>>>>> behind, even after a partial resolution.
reset_repo
cat > "$TMPDIR/dividers.sh" <<'DIVIDERS'
#!/bin/bash
echo "=================================================="
echo "Setup Validation"
echo "=================================================="
echo "All checks passed"
DIVIDERS
git -C "$TMPDIR" add dividers.sh
output=$(run_hook_output "$TMPDIR")
assert_not_contains "standalone === dividers do NOT emit a block decision" '"decision"' "$output"

# Regression: orphan markers (left after a partial conflict resolution) must
# still be flagged.
reset_repo
cat > "$TMPDIR/orphan-open.js" <<'ORPHAN_OPEN'
<<<<<<< HEAD
local change
ORPHAN_OPEN
git -C "$TMPDIR" add orphan-open.js
output=$(run_hook_output "$TMPDIR")
assert_contains "orphan <<<<<<< marker still emits a block decision" '"decision"' "$output"

reset_repo
cat > "$TMPDIR/orphan-close.js" <<'ORPHAN_CLOSE'
remote change
>>>>>>> main
ORPHAN_CLOSE
git -C "$TMPDIR" add orphan-close.js
output=$(run_hook_output "$TMPDIR")
assert_contains "orphan >>>>>>> marker still emits a block decision" '"decision"' "$output"

# ── debugging artifacts ───────────────────────────────────────────────────────
echo ""
echo "debugging artifact detection:"

reset_repo
echo "console.log('debug', x);" > "$TMPDIR/app.js"
git -C "$TMPDIR" add app.js
output=$(run_hook_output "$TMPDIR")
assert_contains "staged console.log emits block decision" '"decision": "block"' "$output"

reset_repo
echo "debugger;" > "$TMPDIR/app.js"
git -C "$TMPDIR" add app.js
output=$(run_hook_output "$TMPDIR")
assert_contains "staged 'debugger;' emits block decision" '"decision": "block"' "$output"

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

reset_repo
echo "function f() { /* TODO: should be ignored */ }" > "$TMPDIR/app.js"
git -C "$TMPDIR" add app.js
override_exit=0
override_output=$(printf '{"cwd":"%s"}' "$TMPDIR" | CLAUDE_HOOKS_DISABLE_TASK_COMPLETENESS=1 bash "$HOOK" 2>/dev/null) || override_exit=$?
assert_exit       "CLAUDE_HOOKS_DISABLE_TASK_COMPLETENESS=1 exits 0" 0 "$override_exit"
assert_not_contains "CLAUDE_HOOKS_DISABLE_TASK_COMPLETENESS=1 emits no decision" '"decision"' "$override_output"

# ── Summary ──────────────────────────────────────────────────────────────────
echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
