#!/usr/bin/env bash
# Regression tests for validate-kubectl-context.sh
#
# Run: bash kubernetes-plugin/hooks/test-validate-kubectl-context.sh
# Exit 0 = all tests pass, Exit 1 = failures
set -euo pipefail

HOOK="$(dirname "$0")/validate-kubectl-context.sh"
PASS=0
FAIL=0

run_hook() {
    local json="$1"
    printf '%s' "$json" | bash "$HOOK" 2>/dev/null
}

assert_exit() {
    local desc="$1" expected="$2" json="$3"
    local actual
    actual=$(run_hook "$json"; echo "$?") || true
    actual="${actual##*$'\n'}"  # last line is exit code from subshell
    # Re-run cleanly to capture exit code
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

echo "=== validate-kubectl-context hook tests ==="

# ── Heredoc regression tests ────────────────────────────────────────────────
# Regression: the word "kubectl" in a heredoc body (e.g. PR descriptions,
# commit messages) was falsely triggering the hook.
echo ""
echo "Heredoc false-positive regression:"

# Single-quoted heredoc body mentioning kubectl — must be allowed (exit 0)
assert_exit \
    "kubectl in single-quoted heredoc body" 0 \
    '{"tool_name":"Bash","tool_input":{"command":"git commit -m \"$(cat <<'"'"'EOF'"'"'\nNote: the validate-kubectl-context hook triggered on kubectl in text.\nEOF\n)\""}}'

# Double-quoted heredoc body mentioning kubectl — must be allowed (exit 0)
assert_exit \
    "kubectl in double-quoted heredoc body" 0 \
    '{"tool_name":"Bash","tool_input":{"command":"cat <<\"EOF\"\nrun kubectl --context=x get pods\nEOF"}}'

# Unquoted heredoc body mentioning kubectl — must be allowed (exit 0)
assert_exit \
    "kubectl in unquoted heredoc body" 0 \
    '{"tool_name":"Bash","tool_input":{"command":"cat <<EOF\nuse kubectl to manage your cluster\nEOF"}}'

# helm in heredoc body — must be allowed (exit 0)
assert_exit \
    "helm in heredoc body" 0 \
    '{"tool_name":"Bash","tool_input":{"command":"git commit -m \"$(cat <<'"'"'MSG'"'"'\nResolves helm --kube-context issue.\nMSG\n)\""}}'

# ── kubectl enforcement tests ────────────────────────────────────────────────
echo ""
echo "kubectl enforcement:"

assert_exit \
    "kubectl without --context is blocked" 2 \
    '{"tool_name":"Bash","tool_input":{"command":"kubectl get pods"}}'

assert_exit \
    "kubectl with --context=NAME is allowed" 0 \
    '{"tool_name":"Bash","tool_input":{"command":"kubectl --context=staging get pods"}}'

assert_exit \
    "kubectl with --context NAME is allowed" 0 \
    '{"tool_name":"Bash","tool_input":{"command":"kubectl --context staging get pods"}}'

assert_exit \
    "kubectl config (safe subcommand) is allowed" 0 \
    '{"tool_name":"Bash","tool_input":{"command":"kubectl config get-contexts"}}'

assert_exit \
    "kubectl version (safe subcommand) is allowed" 0 \
    '{"tool_name":"Bash","tool_input":{"command":"kubectl version"}}'

# ── helm enforcement tests ───────────────────────────────────────────────────
echo ""
echo "helm enforcement:"

assert_exit \
    "helm install without --kube-context is blocked" 2 \
    '{"tool_name":"Bash","tool_input":{"command":"helm install myapp ./chart"}}'

assert_exit \
    "helm install with --kube-context=NAME is allowed" 0 \
    '{"tool_name":"Bash","tool_input":{"command":"helm --kube-context=staging install myapp ./chart"}}'

assert_exit \
    "helm version (safe subcommand) is allowed" 0 \
    '{"tool_name":"Bash","tool_input":{"command":"helm version"}}'

# ── Edge cases ───────────────────────────────────────────────────────────────
echo ""
echo "Edge cases:"

assert_exit \
    "empty command is allowed" 0 \
    '{"tool_name":"Bash","tool_input":{}}'

assert_exit \
    "non-kubectl command is allowed" 0 \
    '{"tool_name":"Bash","tool_input":{"command":"git status"}}'

# ── Summary ──────────────────────────────────────────────────────────────────
echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
