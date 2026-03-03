#!/usr/bin/env bash
# Regression tests for bash-antipatterns.sh
#
# Run: bash hooks-plugin/hooks/test-bash-antipatterns.sh
# Exit 0 = all tests pass, Exit 1 = failures
set -euo pipefail

HOOK="$(dirname "$0")/bash-antipatterns.sh"
PASS=0
FAIL=0

assert_exit() {
    local desc="$1" expected="$2" cmd="$3"
    local json
    json=$(printf '{"tool_name":"Bash","tool_input":{"command":"%s"}}' "$cmd")
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

echo "=== bash-antipatterns hook tests ==="

# ── find exemption regression ────────────────────────────────────────────────
# Regression: find with -exec was allowed while find with -maxdepth/-type was
# blocked — the exact opposite of the project rules in agentic-permissions.md
# and shell-scripting.md, which recommend find with those flags for directory
# discovery that Glob cannot replicate.
echo ""
echo "find exemption (directory-discovery flags allowed, -exec blocked):"

assert_exit \
    "find -maxdepth -type d is allowed" 0 \
    "find . -maxdepth 1 -type d"

assert_exit \
    "find -maxdepth -name is allowed" 0 \
    "find . -maxdepth 1 -name '*.yml'"

assert_exit \
    "find -type f -print0 is allowed" 0 \
    "find . -type f -print0"

assert_exit \
    "find -mindepth -maxdepth is allowed" 0 \
    "find . -mindepth 1 -maxdepth 2 -name '*.md'"

assert_exit \
    "find -name only (Glob can do this) is blocked" 2 \
    "find . -name '*.ts'"

assert_exit \
    "find -exec (dangerous, no discovery flags) is blocked" 2 \
    "find . -exec ls {}"

# ── grep -q exemption regression ─────────────────────────────────────────────
# Regression: grep -q was blocked even though the Grep tool does not support
# boolean exit-code checks. grep -q is the standard shell idiom for testing
# whether a pattern exists (e.g. grep -q pattern file && do_thing).
echo ""
echo "grep -q exemption (exit-code checks allowed, plain searches blocked):"

assert_exit \
    "grep -q is allowed (boolean check)" 0 \
    "grep -q pattern file"

assert_exit \
    "grep -iq is allowed (case-insensitive boolean check)" 0 \
    "grep -iq pattern file"

assert_exit \
    "grep -qr is allowed (recursive boolean check)" 0 \
    "grep -qr pattern dir/"

assert_exit \
    "grep -q in conditional is allowed" 0 \
    "grep -q PATTERN file.txt && echo found"

assert_exit \
    "rg --quiet is allowed" 0 \
    "rg --quiet pattern file"

assert_exit \
    "grep pattern file (no -q, no pipe) is blocked" 2 \
    "grep pattern file"

assert_exit \
    "grep -n pattern file (no -q, no pipe) is blocked" 2 \
    "grep -n pattern file"

assert_exit \
    "grep in pipeline is allowed (piped output has different semantics)" 0 \
    "git log --oneline | grep pattern"

# ── echo/printf file-write detection ─────────────────────────────────────────
# Regression: echo "---"; git ... 2>/dev/null was falsely blocked because
# the regex used .* which crossed the ; command separator and matched the
# unrelated 2>/dev/null as if echo were redirecting to a file.
echo ""
echo "echo/printf file-write detection (true positives blocked, false negatives allowed):"

assert_exit \
    "echo text > file is blocked" 2 \
    "echo hello > file.txt"

assert_exit \
    "printf text > file is blocked" 2 \
    "printf hello > file.txt"

assert_exit \
    "echo separator followed by unrelated 2>/dev/null is allowed" 0 \
    "git log --oneline | head -20; echo '---'; git log --oneline 2>/dev/null | head -20"

assert_exit \
    "echo in compound command before git 2>/dev/null is allowed" 0 \
    "cd /some/repo && git log --oneline -10 -- infra/ 2>/dev/null | head -20; echo '---'; git log --oneline 2>/dev/null | head -20"

# ── Summary ──────────────────────────────────────────────────────────────────
echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
