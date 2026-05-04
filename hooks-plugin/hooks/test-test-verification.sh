#!/usr/bin/env bash
# Regression tests for test-verification.sh
#
# Verifies the three layered constraints on the test-verification hook:
#   Layer 1 - require an explicit fast recipe (no bare-`test` fallback)
#   Layer 2 - skip when HEAD has not advanced since session start
#   Layer 3 - is wired to TaskCompleted, not Stop (covered by plugin.json)
#
# The hook contract: emit {"decision":"block","reason":"..."} on stdout when
# tests fail; emit {"decision":"approve","reason":"..."} on timeout; exit 0
# silently in every other case (including all "skip" paths).
#
# Run: bash hooks-plugin/hooks/test-test-verification.sh
# Exit 0 = all tests pass, Exit 1 = failures
set -euo pipefail

HOOK="$(dirname "$0")/test-verification.sh"
PASS=0
FAIL=0

TMPDIR=$(mktemp -d)
NON_GIT_DIR=$(mktemp -d)
TEST_BASELINE_DIR="/tmp/claude-test-baselines"
mkdir -p "$TEST_BASELINE_DIR"

# Use a deterministic session ID per run so we can clean up our own baselines.
SESSION_ID="task-verify-test-$$"
BASELINE_FILE="${TEST_BASELINE_DIR}/${SESSION_ID}"

trap 'rm -rf "$TMPDIR" "$NON_GIT_DIR" "$BASELINE_FILE"' EXIT

# Initialize git repo
git -C "$TMPDIR" init -q
git -C "$TMPDIR" config user.email "test@example.com"
git -C "$TMPDIR" config user.name "Test"
git -C "$TMPDIR" config commit.gpgsign false
git -C "$TMPDIR" config gpg.format ""
echo "initial" > "$TMPDIR/README.md"
git -C "$TMPDIR" add README.md
git -C "$TMPDIR" commit -q -m "initial"

# Helpers
reset_repo() {
    git -C "$TMPDIR" restore --staged . 2>/dev/null || true
    git -C "$TMPDIR" checkout -- . 2>/dev/null || true
    git -C "$TMPDIR" clean -fdq 2>/dev/null || true
    rm -f "$TMPDIR/justfile" "$TMPDIR/Makefile" "$TMPDIR/package.json" "$TMPDIR/bun.lockb" "$TMPDIR/bun.lock"
}

set_baseline() {
    git -C "$TMPDIR" rev-parse HEAD > "$BASELINE_FILE"
}

clear_baseline() {
    rm -f "$BASELINE_FILE"
}

run_hook_output() {
    local extra="${1:-}"
    local json
    if [ -n "$extra" ]; then
        json=$(printf '{"cwd":"%s","session_id":"%s",%s}' "$TMPDIR" "$SESSION_ID" "$extra")
    else
        json=$(printf '{"cwd":"%s","session_id":"%s"}' "$TMPDIR" "$SESSION_ID")
    fi
    printf '%s' "$json" | bash "$HOOK" 2>/dev/null || true
}

run_hook_exit() {
    local extra="${1:-}"
    local json exit_code=0
    if [ -n "$extra" ]; then
        json=$(printf '{"cwd":"%s","session_id":"%s",%s}' "$TMPDIR" "$SESSION_ID" "$extra")
    else
        json=$(printf '{"cwd":"%s","session_id":"%s"}' "$TMPDIR" "$SESSION_ID")
    fi
    printf '%s' "$json" | bash "$HOOK" >/dev/null 2>&1 || exit_code=$?
    echo "$exit_code"
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

echo "=== test-verification hook tests ==="

# ── Guard tests ──────────────────────────────────────────────────────────────
echo ""
echo "guards:"

reset_repo
output=$(run_hook_output '"stop_hook_active":true')
assert_not_contains "stop_hook_active=true emits no decision" '"decision"' "$output"

exit_code=$(printf '{}' | bash "$HOOK" >/dev/null 2>&1; echo $?)
assert_exit "missing cwd field exits 0" 0 "$exit_code"

exit_code=$(printf '{"cwd":"%s","session_id":"x"}' "$NON_GIT_DIR" | bash "$HOOK" >/dev/null 2>&1; echo $?)
assert_exit "non-git directory exits 0" 0 "$exit_code"

# ── Layer 2: HEAD baseline ───────────────────────────────────────────────────
# When the baseline matches HEAD, the hook must skip silently regardless of
# what other state is present (changed files, fast recipe, anything).
echo ""
echo "Layer 2 — HEAD baseline:"

reset_repo
set_baseline  # baseline now equals current HEAD
echo "function f() { return 1; }" > "$TMPDIR/app.js"
git -C "$TMPDIR" add app.js
# Even with a fast recipe defined, baseline match must short-circuit.
cat > "$TMPDIR/justfile" <<'JF'
test-quick:
	exit 1
JF
output=$(run_hook_output)
assert_not_contains "HEAD == baseline emits no decision" '"decision"' "$output"

clear_baseline

# ── Layer 1: fast recipe required ────────────────────────────────────────────
echo ""
echo "Layer 1 — fast recipe required:"

# No fast recipe → silent no-op even with source changes.
reset_repo
echo "function f() { return 1; }" > "$TMPDIR/app.js"
git -C "$TMPDIR" add app.js
output=$(run_hook_output)
assert_not_contains "no fast recipe → no decision" '"decision"' "$output"

# Bare `test` recipe in justfile is NOT a fast recipe.
reset_repo
echo "function f() { return 1; }" > "$TMPDIR/app.js"
git -C "$TMPDIR" add app.js
cat > "$TMPDIR/justfile" <<'JF'
test:
	exit 1
JF
output=$(run_hook_output)
assert_not_contains "bare 'just test' is NOT a fast recipe" '"decision"' "$output"

# Bare `test` target in Makefile is NOT a fast recipe.
reset_repo
echo "function f() { return 1; }" > "$TMPDIR/app.js"
git -C "$TMPDIR" add app.js
cat > "$TMPDIR/Makefile" <<'MK'
test:
	exit 1
MK
output=$(run_hook_output)
assert_not_contains "bare 'make test' is NOT a fast recipe" '"decision"' "$output"

# Bare `test` script in package.json is NOT a fast recipe.
reset_repo
echo "function f() { return 1; }" > "$TMPDIR/app.js"
git -C "$TMPDIR" add app.js
cat > "$TMPDIR/package.json" <<'PJ'
{"name":"x","scripts":{"test":"exit 1"}}
PJ
output=$(run_hook_output)
assert_not_contains "bare 'npm test' is NOT a fast recipe" '"decision"' "$output"

# ── Layer 1: explicit fast recipes are honoured ──────────────────────────────
echo ""
echo "Layer 1 — explicit fast recipes are honoured:"

# justfile test-quick that fails should block.
reset_repo
echo "function f() { return 1; }" > "$TMPDIR/app.js"
git -C "$TMPDIR" add app.js
cat > "$TMPDIR/justfile" <<'JF'
test-quick:
	echo "FAIL"; exit 1
JF
output=$(run_hook_output)
assert_contains "failing 'just test-quick' emits block decision" '"decision": "block"' "$output"
assert_contains "block reason names the recipe"               'just test-quick'      "$output"

# Makefile test-fast that passes should be silent.
reset_repo
echo "function f() { return 1; }" > "$TMPDIR/app.js"
git -C "$TMPDIR" add app.js
cat > "$TMPDIR/Makefile" <<'MK'
test-fast:
	@exit 0
MK
output=$(run_hook_output)
assert_not_contains "passing 'make test-fast' emits no decision" '"decision"' "$output"

# package.json test:quick failure should block (npm runner).
reset_repo
echo "function f() { return 1; }" > "$TMPDIR/app.js"
git -C "$TMPDIR" add app.js
cat > "$TMPDIR/package.json" <<'PJ'
{"name":"x","scripts":{"test:quick":"exit 1"}}
PJ
output=$(run_hook_output)
assert_contains "failing 'npm run test:quick' emits block decision" '"decision": "block"' "$output"
assert_contains "block reason names the npm runner"                'npm run test:quick'  "$output"

# package.json with bun.lockb present should use bun runner.
reset_repo
echo "function f() { return 1; }" > "$TMPDIR/app.js"
git -C "$TMPDIR" add app.js
cat > "$TMPDIR/package.json" <<'PJ'
{"name":"x","scripts":{"test:fast":"exit 1"}}
PJ
echo "" > "$TMPDIR/bun.lock"
output=$(run_hook_output)
assert_contains "bun.lock + test:fast → bun run test:fast" 'bun run test:fast' "$output"

# Priority: test-quick > test-unit > test-fast (justfile)
reset_repo
echo "function f() { return 1; }" > "$TMPDIR/app.js"
git -C "$TMPDIR" add app.js
cat > "$TMPDIR/justfile" <<'JF'
test-quick:
	@echo QUICK; exit 1
test-unit:
	@echo UNIT; exit 1
JF
output=$(run_hook_output)
assert_contains "test-quick wins over test-unit" 'just test-quick' "$output"

# ── Source-file gate ─────────────────────────────────────────────────────────
echo ""
echo "source-file gate:"

# No file changes at all → silent.
reset_repo
cat > "$TMPDIR/justfile" <<'JF'
test-quick:
	@exit 1
JF
output=$(run_hook_output)
assert_not_contains "no changed files → no decision" '"decision"' "$output"

# Only docs changed → silent (even with a fast recipe and a failing one).
reset_repo
echo "more docs" >> "$TMPDIR/README.md"
git -C "$TMPDIR" add README.md
cat > "$TMPDIR/justfile" <<'JF'
test-quick:
	@exit 1
JF
output=$(run_hook_output)
assert_not_contains "only docs changed → no decision" '"decision"' "$output"

# ── Disable via environment variable ─────────────────────────────────────────
echo ""
echo "CLAUDE_HOOKS_DISABLE_TEST_VERIFICATION override:"

reset_repo
echo "function f() { return 1; }" > "$TMPDIR/app.js"
git -C "$TMPDIR" add app.js
cat > "$TMPDIR/justfile" <<'JF'
test-quick:
	@exit 1
JF
override_output=$(printf '{"cwd":"%s","session_id":"%s"}' "$TMPDIR" "$SESSION_ID" \
    | CLAUDE_HOOKS_DISABLE_TEST_VERIFICATION=1 bash "$HOOK" 2>/dev/null) || true
assert_not_contains "CLAUDE_HOOKS_DISABLE_TEST_VERIFICATION=1 emits no decision" '"decision"' "$override_output"

# ── Summary ──────────────────────────────────────────────────────────────────
echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
