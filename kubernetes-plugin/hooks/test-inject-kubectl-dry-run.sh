#!/usr/bin/env bash
# shellcheck disable=SC2016   # single quotes are the point: each fixture is the literal command text the hook receives
# Regression tests for inject-kubectl-dry-run.sh (#2734)
#
# Run: bash kubernetes-plugin/hooks/test-inject-kubectl-dry-run.sh
# Exit 0 = all tests pass, Exit 1 = failures
#
# The pre-fix hook matched `kubectl apply|delete|patch` anywhere in the raw
# string and appended --dry-run=client to the END of the whole command while
# returning allow, so `kubectl apply -f x.yaml && echo done` became
# `… && echo done --dry-run=client`: the apply ran for real, auto-approved.
# Pinned here:
#   - a single simple kubectl statement gets the flag INSIDE the kubectl node
#     (right after the verb, so before any trailing comment) and an allow;
#   - anything beyond one simple command, a node that already carries its own
#     --dry-run, quoted text, and a parse the hook cannot trust (no parser, a
#     failing parser, an ERROR node) produce NO output at all: no allow, no
#     rewrite — the command goes through the user's normal permission flow.
set -uo pipefail

HOOK="$(cd "$(dirname "$0")" && pwd)/inject-kubectl-dry-run.sh"
PASS=0
FAIL=0

pass() { PASS=$((PASS + 1)); }
fail() {
    FAIL=$((FAIL + 1))
    echo "FAIL: $1"
}

# Without a parser the hook passes everything through, so every pass-through
# row below would be vacuously green. Skip loudly; required-to-run-tests.txt
# turns the skip into an ERROR on CI, where ast-grep is installed on purpose.
if ! command -v ast-grep >/dev/null 2>&1 \
    && ! { command -v sg >/dev/null 2>&1 && sg --version 2>/dev/null | grep -qi '^ast-grep'; }; then
    echo "SKIP: ast-grep not installed (inject-kubectl-dry-run.sh needs it to rewrite anything)"
    exit 0
fi

OUT=""
RC=0

# $1 = command string; optional $2 = PATH to run the hook under.
run_hook() {
    local json
    json=$(jq -n --arg c "$1" '{tool_name: "Bash", tool_input: {command: $c, description: "d"}}')
    if [ -n "${2:-}" ]; then
        OUT=$(printf '%s' "$json" | PATH="$2" "$BASH" "$HOOK" 2>/dev/null)
    else
        OUT=$(printf '%s' "$json" | "$BASH" "$HOOK" 2>/dev/null)
    fi
    RC=$?
}

# $1 = command, $2 = expected rewrite, $3 = label
assert_rewrite() {
    local got decision event desc
    run_hook "$1"
    got=$(jq -r '.hookSpecificOutput.updatedInput.command // empty' <<<"$OUT" 2>/dev/null || true)
    decision=$(jq -r '.hookSpecificOutput.permissionDecision // empty' <<<"$OUT" 2>/dev/null || true)
    event=$(jq -r '.hookSpecificOutput.hookEventName // empty' <<<"$OUT" 2>/dev/null || true)
    desc=$(jq -r '.hookSpecificOutput.updatedInput.description // empty' <<<"$OUT" 2>/dev/null || true)
    if [ "$RC" -eq 0 ] && [ "$got" = "$2" ] && [ "$decision" = "allow" ] \
        && [ "$event" = "PreToolUse" ] && [ "$desc" = "d" ]; then
        pass
    else
        fail "$3
      expected: allow + $2
      got:      exit $RC, $OUT"
    fi
}

# $1 = command, $2 = label, optional $3 = PATH. No output, exit 0.
assert_silent() {
    run_hook "$1" "${3:-}"
    if [ "$RC" -eq 0 ] && [ -z "$OUT" ]; then
        pass
    else
        fail "$2 — expected no output (no allow, no rewrite), got exit $RC: $OUT"
    fi
}

NL=$'\n'
BS=$'\\'

echo "=== #2734 issue examples: no allow, no rewrite ==="
assert_silent 'kubectl apply -f x.yaml && echo done' 'apply && echo done'
assert_silent 'kubectl apply -f x.yaml | tee apply.log' 'apply | tee apply.log'
assert_silent 'helm template --dry-run chart > out.yaml && kubectl apply -f out.yaml' 'helm --dry-run && kubectl apply'
assert_silent 'gh issue comment 1 --body "run kubectl apply"' 'quoted kubectl apply in gh --body'

echo "=== more than one simple command: defer to the user ==="
assert_silent "kubectl apply -f a.yaml${NL}echo done" 'two statements on two lines'
assert_silent 'kubectl apply -f a.yaml; kubectl delete -f b.yaml' 'two kubectl statements'
assert_silent 'kubectl apply -f x.yaml;' 'trailing semicolon'
assert_silent 'kubectl apply -f x.yaml &' 'background job'
assert_silent 'kubectl apply -f x.yaml > apply.log' 'file redirect'
assert_silent 'kubectl apply -f x.yaml 2>&1' 'fd redirect'
assert_silent "kubectl apply -f - <<'EOF'${NL}kind: ConfigMap${NL}EOF" 'heredoc-fed apply'
assert_silent 'kubectl apply -f $(echo x.yaml)' 'command substitution in an argument'
assert_silent 'kubectl apply -f <(cat x.yaml)' 'process substitution'
assert_silent 'echo "$(kubectl delete pod web-0)"' 'kubectl inside a substitution'
assert_silent '(kubectl apply -f x.yaml)' 'subshell'
assert_silent 'for f in a b; do kubectl apply -f "$f"; done' 'loop'
assert_silent '! kubectl delete pod web-0' 'negated command'

echo "=== single simple command: flag lands inside the kubectl node ==="
assert_rewrite 'kubectl apply -f x.yaml' 'kubectl apply --dry-run=client -f x.yaml' 'apply'
assert_rewrite 'kubectl delete pod web-0' 'kubectl delete --dry-run=client pod web-0' 'delete'
assert_rewrite 'kubectl patch deploy web -p '"'"'{"spec":{"replicas":2}}'"'"'' \
    'kubectl patch --dry-run=client deploy web -p '"'"'{"spec":{"replicas":2}}'"'"'' 'patch with quoted JSON'
assert_rewrite 'kubectl apply' 'kubectl apply --dry-run=client' 'verb with no arguments'
assert_rewrite 'kubectl apply -f x.yaml # deploy web' \
    'kubectl apply --dry-run=client -f x.yaml # deploy web' 'flag lands before a trailing comment'
assert_rewrite 'kubectl apply -f x.yaml # rerun with --dry-run=none later' \
    'kubectl apply --dry-run=client -f x.yaml # rerun with --dry-run=none later' \
    'a --dry-run in the comment is not the node'"'"'s argument'
assert_rewrite "kubectl apply ${BS}${NL}  -f x.yaml" "kubectl apply --dry-run=client ${BS}${NL}  -f x.yaml" 'line continuation'
assert_rewrite '  kubectl delete pod web-0  ' '  kubectl delete --dry-run=client pod web-0  ' 'surrounding whitespace'
# ast-grep reports BYTE offsets; multibyte text before the verb must not shift the insertion.
assert_rewrite 'KUBECONFIG=/tmp/kö kubectl apply -f x.yaml' \
    'KUBECONFIG=/tmp/kö kubectl apply --dry-run=client -f x.yaml' 'multibyte bytes before the verb'

echo "=== the node already carries --dry-run: unchanged ==="
assert_silent 'kubectl apply -f x.yaml --dry-run=none' '--dry-run=none bypass'
assert_silent 'kubectl apply -f x.yaml --dry-run=server' '--dry-run=server'
assert_silent 'kubectl apply --dry-run=client -f x.yaml' '--dry-run=client'
assert_silent 'kubectl delete pod web-0 --dry-run' 'bare --dry-run'
assert_silent 'kubectl apply -f x.yaml "--dry-run=none"' 'quoted --dry-run=none'

echo "=== not a kubectl apply/delete/patch node ==="
assert_silent 'kubectl get pods' 'read-only verb'
assert_silent 'echo kubectl apply -f x.yaml' 'kubectl as an echo argument'
assert_silent 'bash -c "kubectl apply -f x.yaml"' 'kubectl inside a script string'
assert_silent "cat <<'EOF'${NL}kubectl apply -f x.yaml${NL}EOF" 'heredoc body'
assert_silent 'kubectl "apply" -f x.yaml' 'quoted verb is not read'
assert_silent 'kubectl $FLAGS apply -f x.yaml' 'verb must directly follow kubectl'
assert_silent '' 'empty command'

echo "=== a parse the hook cannot trust: no output ==="
assert_silent 'kubectl apply -f x.yaml && )' 'ERROR node'
assert_silent 'kubectl apply -f x.yaml &&' 'missing node after &&'
assert_silent 'kubectl apply -f "x.yaml' 'unterminated quote (a MISSING node, not ERROR)'
assert_silent 'kubectl apply -f ${x' 'unterminated ${'
assert_silent 'kubectl apply -f `x' 'unterminated backtick'

SANDBOX=$(mktemp -d "${TMPDIR:-/tmp}/kubectl-dry-run-test.XXXXXX") || SANDBOX=""
if [ -z "$SANDBOX" ] || [ ! -d "$SANDBOX" ]; then
    echo "FAIL: mktemp -d failed"
    exit 1
fi
trap 'rm -rf "$SANDBOX"' EXIT
# A PATH holding only what the hook needs besides the parser.
for tool in jq cat sort grep; do
    for dir in "$SANDBOX/none" "$SANDBOX/shadow" "$SANDBOX/fails" "$SANDBOX/junk"; do
        mkdir -p "$dir"
        ln -sf "$(command -v "$tool")" "$dir/$tool"
    done
done
printf '#!%s\necho "sg from shadow-utils"\nexit 2\n' "$BASH" >"$SANDBOX/shadow/sg"
printf '#!%s\nexit 1\n' "$BASH" >"$SANDBOX/fails/ast-grep"
printf '#!%s\necho "not json"\n' "$BASH" >"$SANDBOX/junk/ast-grep"
# A canned parse of `kubectl apply -f x.yaml`, with and without an ERROR node,
# so the ERROR branch is exercised even where bash -n would also have refused.
CLEAN_PARSE='{"ruleId":"cmd","range":{"byteOffset":{"start":0,"end":23}}},{"ruleId":"name","range":{"byteOffset":{"start":0,"end":7}}},{"ruleId":"word","range":{"byteOffset":{"start":8,"end":13}}}'
for dir in canned errnode; do
    mkdir -p "$SANDBOX/$dir"
    for tool in jq cat sort grep; do ln -sf "$(command -v "$tool")" "$SANDBOX/$dir/$tool"; done
done
printf '#!%s\ncat >/dev/null\necho '"'"'[%s]'"'"'\n' "$BASH" "$CLEAN_PARSE" >"$SANDBOX/canned/ast-grep"
printf '#!%s\ncat >/dev/null\necho '"'"'[%s,{"ruleId":"err","range":{"byteOffset":{"start":17,"end":23}}}]'"'"'\n' \
    "$BASH" "$CLEAN_PARSE" >"$SANDBOX/errnode/ast-grep"
chmod +x "$SANDBOX/shadow/sg" "$SANDBOX/fails/ast-grep" "$SANDBOX/junk/ast-grep" \
    "$SANDBOX/canned/ast-grep" "$SANDBOX/errnode/ast-grep"

echo "=== parser absent or failing: no output ==="
assert_silent 'kubectl apply -f x.yaml' 'no ast-grep on PATH' "$SANDBOX/none"
assert_silent 'kubectl apply -f x.yaml' 'only shadow-utils sg on PATH (#2451)' "$SANDBOX/shadow"
assert_silent 'kubectl apply -f x.yaml' 'ast-grep exits non-zero' "$SANDBOX/fails"
assert_silent 'kubectl apply -f x.yaml' 'ast-grep prints junk' "$SANDBOX/junk"
assert_silent 'kubectl apply -f x.yaml' 'parse holds an ERROR node' "$SANDBOX/errnode"
# Non-vacuity: the canned clean parse, and the real parser, DO rewrite it.
run_hook 'kubectl apply -f x.yaml' "$SANDBOX/canned"
if [ "$(jq -r '.hookSpecificOutput.updatedInput.command // empty' <<<"$OUT" 2>/dev/null)" = 'kubectl apply --dry-run=client -f x.yaml' ]; then
    pass
else
    fail "canned clean parse should rewrite (else the ERROR row is vacuous): $OUT"
fi
assert_rewrite 'kubectl apply -f x.yaml' 'kubectl apply --dry-run=client -f x.yaml' 'same command with the parser present'

echo
echo "Passed: $PASS, Failed: $FAIL"
[ "$FAIL" -eq 0 ]
