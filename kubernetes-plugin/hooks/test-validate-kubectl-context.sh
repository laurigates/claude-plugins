#!/usr/bin/env bash
# shellcheck disable=SC2016  # Single-quoted JSON test data contains $() intentionally
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

# ── Quoted-string false-positive regression tests ──────────────────────────
# Regression (issue #1430): kubectl/helm mentioned inside a quoted grep
# pattern, echo argument, awk regex, or find -name pattern was falsely
# triggering this hook.
echo ""
echo "Quoted-string false-positive regression (#1430):"

# grep with kubectl inside a double-quoted alternation pattern
assert_exit \
    "grep with kubectl in double-quoted pattern" 0 \
    '{"tool_name":"Bash","tool_input":{"command":"grep -n \"pod-exec|pod-db|namespace|kubectl exec|skaffold\" justfile | head -40"}}'

# grep with kubectl in a bare double-quoted pattern
assert_exit \
    "grep with bare kubectl pattern" 0 \
    '{"tool_name":"Bash","tool_input":{"command":"grep -rn \"kubectl\" docs/"}}'

# echo with kubectl in a double-quoted argument
assert_exit \
    "echo with kubectl in double-quoted arg" 0 \
    '{"tool_name":"Bash","tool_input":{"command":"echo \"run kubectl get pods to list things\""}}'

# awk with kubectl inside a single-quoted regex
assert_exit \
    "awk with kubectl in single-quoted regex" 0 \
    "{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"awk '/kubectl/ {print}' justfile\"}}"

# find with kubectl in a quoted -name pattern
assert_exit \
    "find -name with kubectl in quoted pattern" 0 \
    '{"tool_name":"Bash","tool_input":{"command":"find . -name \"kubectl*\" -type f"}}'

# helm mentioned inside a quoted grep pattern
assert_exit \
    "grep with helm in double-quoted pattern" 0 \
    '{"tool_name":"Bash","tool_input":{"command":"grep -n \"helm install\" justfile"}}'

# Legitimate kubectl with quoted --context value (must still be allowed)
assert_exit \
    "kubectl with quoted --context value" 0 \
    '{"tool_name":"Bash","tool_input":{"command":"kubectl --context=\"prod\" get pods"}}'

# Legitimate kubectl with quoted argument after --context (must still be allowed)
assert_exit \
    "kubectl --context plus quoted positional arg" 0 \
    '{"tool_name":"Bash","tool_input":{"command":"kubectl --context=staging get pods -l \"app=foo\""}}'

# Pipe into kubectl (legitimate; must still be blocked without --context)
assert_exit \
    "pipe into kubectl without --context is blocked" 2 \
    '{"tool_name":"Bash","tool_input":{"command":"cat manifest.yaml | kubectl apply -f -"}}'

# Pipe into kubectl with --context (allowed)
assert_exit \
    "pipe into kubectl with --context is allowed" 0 \
    '{"tool_name":"Bash","tool_input":{"command":"cat manifest.yaml | kubectl --context=staging apply -f -"}}'

# ── Prose-substring false-positive regression tests ────────────────────────
# Regression (issue #1544): the detection anchor allowed ANY whitespace before
# the tool name, so a bare mention of "helm"/"kubectl" in prose that leaked past
# heredoc/quote stripping (e.g. a commit message with an escaped quote) was
# blocked as if it were a real invocation. Detection now anchors on command
# position (start, after a separator, or after env/sudo prefixes), so mid-prose
# mentions are allowed while genuine invocations are still enforced.
echo ""
echo "Prose-substring false-positive regression (#1544):"

# helm mentioned mid-sentence in an unquoted command (prose, not an invocation)
assert_exit \
    "helm mid-prose after a non-command word is allowed" 0 \
    '{"tool_name":"Bash","tool_input":{"command":"echo please install helm soon"}}'

# kubectl mentioned mid-sentence in an unquoted command
assert_exit \
    "kubectl mid-prose after a non-command word is allowed" 0 \
    '{"tool_name":"Bash","tool_input":{"command":"echo run kubectl later to inspect pods"}}'

# Commit message whose escaped quote defeats naive quote-stripping, leaking the
# word "helm" into the cleaned command — must NOT be treated as an invocation
assert_exit \
    "helm in commit message with escaped quote is allowed" 0 \
    '{"tool_name":"Bash","tool_input":{"command":"git commit -m \"rename the \\\"fix\\\" fork to a helm hook name\""}}'

# Same shape for kubectl
assert_exit \
    "kubectl in commit message with escaped quote is allowed" 0 \
    '{"tool_name":"Bash","tool_input":{"command":"git commit -m \"document the \\\"new\\\" kubectl context flow\""}}'

# Protection preserved: sudo/env-prefixed invocations are still real invocations
assert_exit \
    "sudo helm install without --kube-context is still blocked" 2 \
    '{"tool_name":"Bash","tool_input":{"command":"sudo helm install myapp ./chart"}}'

assert_exit \
    "env-prefixed kubectl without --context is still blocked" 2 \
    '{"tool_name":"Bash","tool_input":{"command":"KUBECONFIG=/tmp/kc kubectl get pods"}}'

assert_exit \
    "sudo helm with --kube-context is allowed" 0 \
    '{"tool_name":"Bash","tool_input":{"command":"sudo helm --kube-context=prod install myapp ./chart"}}'

assert_exit \
    "env-prefixed kubectl with --context is allowed" 0 \
    '{"tool_name":"Bash","tool_input":{"command":"KUBECONFIG=/tmp/kc kubectl --context=prod get pods"}}'

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

# Regression: `helm pull`/`fetch` and other chart-only subcommands were
# missing from the safe list, blocking chart downloads from a repo even
# though the commands never touch a cluster.
assert_exit \
    "helm pull --repo is allowed (downloads chart, no cluster)" 0 \
    '{"tool_name":"Bash","tool_input":{"command":"helm pull --repo https://example.com/charts mychart --version 1.0.0"}}'

assert_exit \
    "helm fetch is allowed (alias for pull)" 0 \
    '{"tool_name":"Bash","tool_input":{"command":"helm fetch mychart"}}'

assert_exit \
    "helm search repo is allowed" 0 \
    '{"tool_name":"Bash","tool_input":{"command":"helm search repo --repo https://example.com/charts mychart"}}'

assert_exit \
    "helm lint is allowed (local chart analysis)" 0 \
    '{"tool_name":"Bash","tool_input":{"command":"helm lint ./mychart"}}'

assert_exit \
    "helm dependency update is allowed (local chart deps)" 0 \
    '{"tool_name":"Bash","tool_input":{"command":"helm dependency update ./mychart"}}'

assert_exit \
    "helm registry login is allowed (registry, not cluster)" 0 \
    '{"tool_name":"Bash","tool_input":{"command":"helm registry login registry.example.com"}}'

assert_exit \
    "helm push is allowed (pushes to registry, not cluster)" 0 \
    '{"tool_name":"Bash","tool_input":{"command":"helm push mychart-1.0.0.tgz oci://registry.example.com/charts"}}'

assert_exit \
    "helm verify is allowed (local provenance check)" 0 \
    '{"tool_name":"Bash","tool_input":{"command":"helm verify mychart-1.0.0.tgz"}}'

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
