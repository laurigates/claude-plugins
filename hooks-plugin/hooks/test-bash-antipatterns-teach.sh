#!/usr/bin/env bash
# Regression tests for bash-antipatterns-teach.sh
#
# Run: bash hooks-plugin/hooks/test-bash-antipatterns-teach.sh
# Exit 0 = all tests pass, Exit 1 = failures
#
# Unlike test-bash-antipatterns.sh (which asserts on exit codes), this hook
# returns exit 0 always. The contract is the stdout JSON: presence of
# `.hookSpecificOutput.updatedToolOutput` for matched antipatterns, empty
# stdout for non-matches and when the env-var guard is off.
set -euo pipefail

HOOK="$(dirname "$0")/bash-antipatterns-teach.sh"
PASS=0
FAIL=0

# Build a minimal PostToolUse input. tool_response is a stand-in for whatever
# the harness actually produces; the hook just stringifies it.
_payload() {
    local cmd="$1"
    jq -nc --arg cmd "$cmd" '{
        tool_name: "Bash",
        tool_input: {command: $cmd},
        tool_response: "sample stdout output\n"
    }'
}

# With the env var set, the hook should emit JSON whose
# .hookSpecificOutput.updatedToolOutput contains the expected substring.
assert_emits() {
    local desc="$1" cmd="$2" needle="$3"
    local out
    out=$(_payload "$cmd" | CLAUDE_HOOKS_ENABLE_BASH_ANTIPATTERNS_TEACH=1 bash "$HOOK" 2>/dev/null || true)
    if [ -z "$out" ]; then
        printf "  FAIL: %s (expected hint, got empty stdout)\n" "$desc"
        FAIL=$((FAIL + 1))
        return
    fi
    local body
    body=$(echo "$out" | jq -r '.hookSpecificOutput.updatedToolOutput // empty' 2>/dev/null || true)
    if [ -z "$body" ]; then
        printf "  FAIL: %s (stdout missing hookSpecificOutput.updatedToolOutput)\n" "$desc"
        FAIL=$((FAIL + 1))
        return
    fi
    if echo "$body" | grep -qF "$needle"; then
        printf "  PASS: %s\n" "$desc"
        PASS=$((PASS + 1))
    else
        printf "  FAIL: %s (substring %q not found in hint)\n" "$desc" "$needle"
        FAIL=$((FAIL + 1))
    fi
}

# With the env var set, the hook should produce empty stdout (non-matching command).
assert_silent() {
    local desc="$1" cmd="$2"
    local out
    out=$(_payload "$cmd" | CLAUDE_HOOKS_ENABLE_BASH_ANTIPATTERNS_TEACH=1 bash "$HOOK" 2>/dev/null || true)
    if [ -z "$out" ]; then
        printf "  PASS: %s\n" "$desc"
        PASS=$((PASS + 1))
    else
        printf "  FAIL: %s (expected silent, got: %s)\n" "$desc" "$out"
        FAIL=$((FAIL + 1))
    fi
}

# With the env var unset, the hook should always produce empty stdout.
assert_disabled() {
    local desc="$1" cmd="$2"
    local out
    out=$(_payload "$cmd" | bash "$HOOK" 2>/dev/null || true)
    if [ -z "$out" ]; then
        printf "  PASS: %s\n" "$desc"
        PASS=$((PASS + 1))
    else
        printf "  FAIL: %s (expected env-guard silence, got: %s)\n" "$desc" "$out"
        FAIL=$((FAIL + 1))
    fi
}

echo "=== bash-antipatterns-teach hook tests ==="

echo ""
echo "cat / head / tail file reads (standalone):"
assert_emits "cat README.md emits Read hint" "cat README.md" "Read tool"
assert_emits "head -50 file.md emits Read offset/limit hint" "head -50 file.md" "Read tool with offset/limit"
assert_emits "tail -50 file.md emits Read offset/limit hint" "tail -50 file.md" "Read tool with offset/limit"

echo ""
echo "find without directory-discovery flags:"
assert_emits "find -name only emits Glob hint" "find . -name '*.ts'" "Glob tool"
assert_silent "find -maxdepth -type d is exempt" "find . -maxdepth 1 -type d"
assert_silent "find -type f -print0 is exempt" "find . -type f -print0"

echo ""
echo "grep / rg standalone searches:"
assert_emits "grep -rn pattern emits Grep hint" "grep -rn foo src/" "Grep tool"
assert_emits "rg with --type emits Grep hint" "rg foo --type ts" "Grep tool"
assert_silent "grep -q boolean check is exempt" "grep -q pattern file"
assert_silent "rg --quiet boolean check is exempt" "rg --quiet pattern file"

echo ""
echo "ls with glob:"
assert_emits "ls *.md emits Glob hint" "ls *.md" "Glob tool"

echo ""
echo "pipelines and unrelated commands stay silent:"
assert_silent "cat file | head -10 (pipeline) is silent" "cat README.md | head -10"
assert_silent "git status --porcelain is silent" "git status --porcelain"
assert_silent "echo hello is silent" "echo hello"

echo ""
echo "env-var guard (disabled by default):"
assert_disabled "cat README.md is silent when env var unset" "cat README.md"
assert_disabled "grep -rn foo src/ is silent when env var unset" "grep -rn foo src/"
assert_disabled "find . -name '*.ts' is silent when env var unset" "find . -name '*.ts'"

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
