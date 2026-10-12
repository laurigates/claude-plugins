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
#   - a single simple kubectl statement gets the flag INSIDE the kubectl node,
#     at its END (so before any trailing comment, and after any --dry-run
#     override the text check misses, since kubectl's last value wins) plus a
#     copy right after the verb, and an allow;
#   - a `--` argument (which ends option parsing) gets no output;
#   - anything beyond one simple command, a node that already carries its own
#     --dry-run (however spelled: --dry_run, --dry-r''un), quoted text, and a
#     parse the hook cannot trust (no parser, a failing parser, an ERROR node)
#     produce NO output at all: no allow, no rewrite — the command goes through
#     the user's normal permission flow.
# #2887 pins the shapes the #2734 fix still allowed although they were not dry
# runs: --raw, a trailing valued flag that swallows the injected flag, a
# leading redirect, a herestring, any substitution or expansion, a glob or
# brace expansion, and --profile / --cache-dir. Each now yields no output, also
# when a line continuation splits the flag, and so does an environment prefix
# other than KUBECONFIG=….
# #2888 pins the forms that were missed: global flags before the verb (the
# `kubectl --context=X apply` form validate-kubectl-context.sh asks for, checked
# against that hook's own printed example), `timeout N` / `env KUBECONFIG=…`
# wrappers (sudo, a path and other env assignments stay silent), and the apply
# subcommands that reject --dry-run (view-last-applied, edit-last-applied).
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
D=--dry-run=client
assert_rewrite 'kubectl apply -f x.yaml' "kubectl apply $D -f x.yaml $D" 'apply'
assert_rewrite 'kubectl delete pod web-0' "kubectl delete $D pod web-0 $D" 'delete'
assert_rewrite 'kubectl patch deploy web -p replicas.yaml' \
    "kubectl patch $D deploy web -p replicas.yaml $D" 'patch'
assert_rewrite 'kubectl apply' "kubectl apply $D" 'verb with no arguments: one copy'
assert_rewrite 'kubectl apply -f x.yaml # deploy web' \
    "kubectl apply $D -f x.yaml $D # deploy web" 'flag lands before a trailing comment'
assert_rewrite 'kubectl apply -f x.yaml # rerun with --dry-run=none later' \
    "kubectl apply $D -f x.yaml $D # rerun with --dry-run=none later" \
    'a --dry-run in the comment is not the node'"'"'s argument'
assert_rewrite "kubectl apply ${BS}${NL}  -f x.yaml" "kubectl apply $D ${BS}${NL}  -f x.yaml $D" 'line continuation'
assert_rewrite '  kubectl delete pod web-0  ' "  kubectl delete $D pod web-0 $D  " 'surrounding whitespace'
# ast-grep reports BYTE offsets; multibyte text must not shift either insertion.
assert_rewrite 'KUBECONFIG=/tmp/kö kubectl apply -f x.yaml' \
    "KUBECONFIG=/tmp/kö kubectl apply $D -f x.yaml $D" 'multibyte bytes before the verb'
assert_rewrite 'kubectl apply -f kö.yaml # ö' "kubectl apply $D -f kö.yaml $D # ö" 'multibyte bytes inside the node'

echo "=== a disguised --dry-run override: the hook declines it (#2887) ==="
# kubectl takes the last --dry-run, and its normalizer maps _ to -. #2734 pinned
# a trailing --dry-run=client that beat these; the hook now reads each of them
# as the node's own --dry-run (or as an expansion it cannot see through) and
# stays silent, so the command meets the user's normal permission prompt.
assert_silent "kubectl apply -f x.yaml --dry-r''un=none" "--dry-r''un=none"
assert_silent 'kubectl apply -f x.yaml --dry-r""un=none' '--dry-r""un=none'
assert_silent "kubectl apply -f x.yaml --dry-r${BS}un=none" '--dry-r\un=none'
assert_silent 'kubectl apply -f x.yaml --dry-${X:-run}=none' '--dry-${X:-run}=none'
assert_silent "kubectl apply -f x.yaml \$'--dry-r${BS}x75n=none'" "\$'--dry-r\\x75n=none'"
assert_silent 'kubectl apply -f x.yaml --dry_run=none' '--dry_run=none (apply)'
assert_silent 'kubectl delete pod x --dry_run=none' '--dry_run=none (delete)'
assert_silent 'kubectl delete pod x ${X:---} y' 'expansion that may be --'

echo "=== #2887 issue examples: not a dry run, so no allow ==="
assert_silent 'kubectl delete --raw /api/v1/namespaces/x' '--raw deletes before --dry-run is read'
assert_silent 'kubectl delete --raw=/api/v1/namespaces/x' '--raw=<path>'
assert_silent 'kubectl delete pod foo --dry_run=none --cache-dir' '--dry_run=none then a valued flag'
assert_silent "kubectl delete pod foo --dry_run=none \$'--'" "\$'--' expands to --"
assert_silent 'kubectl apply -f x.yaml {-,}-' 'brace expansion to --'
assert_silent 'kubectl apply -f x.yaml $EXTRA' 'unquoted $EXTRA'
assert_silent '>/tmp/out kubectl apply -f x.yaml' 'leading redirect (inside the command node)'
assert_silent '> f kubectl apply -f x.yaml' 'leading redirect with a space'
assert_silent 'kubectl apply -f x.yaml $(>/tmp/pwn)' 'redirect-only command substitution'
assert_silent 'kubectl apply -f x.yaml <(>/tmp/pwn)' 'redirect-only process substitution'
assert_silent 'kubectl apply -f x.yaml ${X:-`touch /tmp/pwn`}' 'backtick nested in ${…}'
assert_silent 'kubectl apply -f x.yaml ${X}' 'braced expansion'
assert_silent 'kubectl apply -f x.yaml --profile=cpu --profile-output=/tmp/p' '--profile-output writes a file'
assert_silent 'kubectl apply -f x.yaml --profile=cpu' '--profile writes profile.pprof'
assert_silent 'kubectl apply -f x.yaml --cache-dir=/tmp/c' '--cache-dir=<path>'
assert_silent 'kubectl apply -f x.yaml <<< x' 'herestring'
assert_silent 'kubectl apply -f x.yaml -o' 'last word -o would take the injected flag as its value'
assert_silent 'kubectl delete pod foo --as' 'last word --as would take the injected flag as its value'
assert_silent 'kubectl apply -f *.yaml' 'glob'
assert_silent 'kubectl apply -f x?.yaml' 'single-character glob'
assert_silent 'kubectl apply -f [xy].yaml' 'bracket glob'
assert_silent 'kubectl patch deploy web -p '"'"'{"spec":{"replicas":2}}'"'"'' \
    'patch with quoted JSON: a { now declines (stricter gate)'
# A flag with its value after `=` swallows nothing.
assert_rewrite 'kubectl apply -f x.yaml -o=yaml' "kubectl apply $D -f x.yaml -o=yaml $D" 'last word -o=yaml'

echo "=== a line continuation inside a word: bash joins it, so does the hook ==="
# Bash deletes backslash-newline before it splits words, so each of these
# reaches kubectl as the flag the word guards decline (#2887 review).
assert_silent "kubectl delete --ra${BS}${NL}w /api/v1/namespaces/x" '--ra\<NL>w is --raw'
assert_silent "kubectl delete -${BS}${NL}-raw /api/v1/namespaces/x" '-\<NL>-raw is --raw'
assert_silent "kubectl delete pod x --dry-${BS}${NL}run=none -${BS}${NL}- y" \
    '--dry-\<NL>run=none and -\<NL>- are --dry-run=none and --'
assert_silent "kubectl apply -f x.yaml --dry-r${BS}${NL}un=none" '--dry-r\<NL>un=none is the node'"'"'s own --dry-run'
assert_silent "kubectl apply -f x.yaml --cache${BS}${NL}-dir=/tmp/c" '--cache\<NL>-dir is --cache-dir'
assert_silent "kubectl apply -f x.yaml -${BS}${NL}o" 'last word -\<NL>o is -o'
# An escaped backslash before the newline ends the statement instead.
assert_silent "kubectl delete x${BS}${BS}${NL}--raw /api/v1/namespaces/x" '\\<NL> ends the statement: two commands'

echo "=== an environment prefix other than KUBECONFIG: no output ==="
assert_silent 'PATH=/tmp/evil kubectl apply -f x.yaml' 'PATH= can swap the kubectl binary'
assert_silent 'LD_PRELOAD=/tmp/x.so kubectl apply -f x.yaml' 'LD_PRELOAD= loads a library'
assert_silent 'KUBECONFIG=/tmp/k PATH=/tmp/evil kubectl apply -f x.yaml' 'KUBECONFIG= beside PATH='
assert_silent 'KUBECONFIG+=/tmp/k kubectl apply -f x.yaml' 'KUBECONFIG+= is not the allowed form'
assert_rewrite 'KUBECONFIG=/tmp/k kubectl apply -f x.yaml' \
    "KUBECONFIG=/tmp/k kubectl apply $D -f x.yaml $D" 'KUBECONFIG= alone is still rewritten'

echo "=== a -- argument ends option parsing: no output ==="
assert_silent 'kubectl delete pod x -- y' 'bare --'
assert_silent "kubectl delete pod x '--' y" "quoted '--'"
assert_silent 'kubectl delete pod x "--" y' 'double-quoted "--"'
assert_silent "kubectl delete pod x ${BS}-- y" 'escaped \--'
assert_silent 'kubectl patch deploy web -p {} --' 'trailing --'

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

echo "=== #2888 item 1: kubectl global flags before the verb ==="
# validate-kubectl-context.sh tells the agent to write `kubectl --context=X
# <command>`; the checkpoint must fire on that exact form.
assert_rewrite 'kubectl --context=staging apply -f x.yaml' \
    "kubectl --context=staging apply $D -f x.yaml $D" '--context=X before the verb'
assert_rewrite 'kubectl --context staging apply -f x.yaml' \
    "kubectl --context staging apply $D -f x.yaml $D" '--context X before the verb'
assert_rewrite 'kubectl -n prod delete pod x' "kubectl -n prod delete $D pod x $D" '-n ns before the verb'
assert_rewrite 'kubectl --namespace=prod --context=staging patch deploy web -p r.yaml' \
    "kubectl --namespace=prod --context=staging patch $D deploy web -p r.yaml $D" 'two global flags'
assert_rewrite 'kubectl --kubeconfig /tmp/k --cluster c --user u apply -f x.yaml' \
    "kubectl --kubeconfig /tmp/k --cluster c --user u apply $D -f x.yaml $D" '--kubeconfig/--cluster/--user values'
assert_rewrite 'kubectl -v 6 --request-timeout=30s -s https://k:6443 delete pod x' \
    "kubectl -v 6 --request-timeout=30s -s https://k:6443 delete $D pod x $D" '-v N, --request-timeout=, -s URL'
assert_rewrite 'kubectl --as=admin --as-group g --token=t --server=https://k apply -f x.yaml' \
    "kubectl --as=admin --as-group g --token=t --server=https://k apply $D -f x.yaml $D" '--as/--as-group/--token/--server'
assert_rewrite 'kubectl --context apply delete pod x' \
    "kubectl --context apply delete $D pod x $D" 'a context named apply is the value, delete is the verb'
assert_silent 'kubectl --insecure-skip-tls-verify apply -f x.yaml' 'unknown global flag before the verb'
assert_silent 'kubectl -nprod apply -f x.yaml' 'attached short value is not modelled'
assert_silent 'kubectl --context "staging" apply -f x.yaml' 'quoted flag value before the verb'
assert_silent 'kubectl --context="staging" apply -f x.yaml' 'quoted value glued to the flag is not a bare word'
assert_silent 'kubectl --context apply' 'valued flag swallows the would-be verb'
assert_silent 'kubectl -n --context=s apply -f x.yaml' 'a flag is not a flag value'
assert_silent 'kubectl --context=staging get pods' 'read-only verb after a global flag'
# Cross-hook: the corrected form validate-kubectl-context.sh prints is rewritten.
CTX_HOOK="$(dirname "$HOOK")/validate-kubectl-context.sh"
CTX_EXAMPLE=$(jq -n '{tool_input: {command: "kubectl apply -f deployment.yaml"}}' \
    | "$BASH" "$CTX_HOOK" 2>&1 >/dev/null | sed -n 's/^[[:space:]]*\(kubectl --context=[^ ]* apply .*\)$/\1/p' | head -1 || true)
if [ -n "$CTX_EXAMPLE" ]; then
    assert_rewrite "$CTX_EXAMPLE" "${CTX_EXAMPLE/ apply / apply $D } $D" \
        'the apply example validate-kubectl-context.sh prints'
else
    fail 'validate-kubectl-context.sh printed no `kubectl --context=… apply …` example'
fi

echo "=== #2888 item 2: wrapper and path invocations ==="
# timeout DURATION and env KUBECONFIG=… run the same kubectl from PATH, so they
# are rewritten (restoring the pre-#2880 coverage). sudo escalates, a path can
# name any binary, and env NAME=… can set PATH= or LD_PRELOAD=: no output.
assert_rewrite 'timeout 60 kubectl apply -f x.yaml' "timeout 60 kubectl apply $D -f x.yaml $D" 'timeout N'
assert_rewrite 'timeout 1.5m kubectl --context=s delete pod x' \
    "timeout 1.5m kubectl --context=s delete $D pod x $D" 'timeout with a unit and a global flag'
assert_rewrite 'env KUBECONFIG=/tmp/k kubectl apply -f x.yaml' \
    "env KUBECONFIG=/tmp/k kubectl apply $D -f x.yaml $D" 'env KUBECONFIG=…'
assert_rewrite 'timeout 60 env kubectl apply -f x.yaml' \
    "timeout 60 env kubectl apply $D -f x.yaml $D" 'timeout then env'
assert_silent 'sudo kubectl delete pod x' 'sudo is not a target'
assert_silent '/usr/local/bin/kubectl apply -f x.yaml' 'a path to kubectl can be any binary'
assert_silent './kubectl apply -f x.yaml' 'a relative path to kubectl'
assert_silent 'env K=v kubectl apply -f x.yaml' 'env with a non-KUBECONFIG assignment'
assert_silent 'K=v kubectl apply -f x.yaml' 'bare non-KUBECONFIG assignment (control, #2887)'
assert_silent 'env PATH=/tmp/evil kubectl apply -f x.yaml' 'env PATH= can swap the binary'
assert_silent 'env -i kubectl apply -f x.yaml' 'env with an option'
assert_silent 'timeout -s KILL 60 kubectl apply -f x.yaml' 'timeout with an option'
assert_silent 'timeout kubectl apply -f x.yaml' 'timeout without a duration'
assert_silent 'timeout 60 sudo kubectl apply -f x.yaml' 'timeout then sudo'
assert_silent 'timeout 60 kubectl get pods' 'read-only verb behind timeout'

echo "=== #2888 item 3: apply subcommands that reject --dry-run ==="
assert_silent 'kubectl apply view-last-applied deploy/web' 'view-last-applied has no --dry-run'
assert_silent 'kubectl apply edit-last-applied deploy/web' 'edit-last-applied has no --dry-run'
assert_silent 'kubectl --context=staging apply view-last-applied deploy/web -o yaml' \
    'view-last-applied after a global flag'
assert_silent 'kubectl apply -f x.yaml view-last-applied' 'view-last-applied after a flag (cobra still finds it)'
assert_rewrite 'kubectl apply set-last-applied -f x.yaml' \
    "kubectl apply $D set-last-applied -f x.yaml $D" 'set-last-applied accepts --dry-run'
assert_rewrite 'kubectl delete configmap view-last-applied' \
    "kubectl delete $D configmap view-last-applied $D" 'the name only matters under apply'

echo "=== #2888 item 4: an unseen -- stays out of reach ==="
assert_silent 'kubectl delete pod x ${X:---} y' '${X:---} declines (no positional --dry-run=client)'

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
# The same clean parse plus one substitution / expansion / redirect node, or an
# environment assignment that is not KUBECONFIG=… (#2887).
# The command text carries none of $ ` { < >, so the text guard cannot be what
# silences these rows: only the parse-node bail can.
AST_BAIL_IDS="csub psub exp sexp fredir hstr asgn"
for id in $AST_BAIL_IDS; do
    mkdir -p "$SANDBOX/node-$id"
    for tool in jq cat sort grep; do ln -sf "$(command -v "$tool")" "$SANDBOX/node-$id/$tool"; done
    printf '#!%s\ncat >/dev/null\necho '"'"'[%s,{"ruleId":"%s","range":{"byteOffset":{"start":17,"end":23}}}]'"'"'\n' \
        "$BASH" "$CLEAN_PARSE" "$id" >"$SANDBOX/node-$id/ast-grep"
    chmod +x "$SANDBOX/node-$id/ast-grep"
done

echo "=== parser absent or failing: no output ==="
assert_silent 'kubectl apply -f x.yaml' 'no ast-grep on PATH' "$SANDBOX/none"
assert_silent 'kubectl apply -f x.yaml' 'only shadow-utils sg on PATH (#2451)' "$SANDBOX/shadow"
assert_silent 'kubectl apply -f x.yaml' 'ast-grep exits non-zero' "$SANDBOX/fails"
assert_silent 'kubectl apply -f x.yaml' 'ast-grep prints junk' "$SANDBOX/junk"
assert_silent 'kubectl apply -f x.yaml' 'parse holds an ERROR node' "$SANDBOX/errnode"
for id in $AST_BAIL_IDS; do
    assert_silent 'kubectl apply -f x.yaml' "parse holds a $id node (#2887)" "$SANDBOX/node-$id"
done
# Non-vacuity: the canned clean parse, and the real parser, DO rewrite it.
run_hook 'kubectl apply -f x.yaml' "$SANDBOX/canned"
if [ "$(jq -r '.hookSpecificOutput.updatedInput.command // empty' <<<"$OUT" 2>/dev/null)" = "kubectl apply $D -f x.yaml $D" ]; then
    pass
else
    fail "canned clean parse should rewrite (else the ERROR row is vacuous): $OUT"
fi
assert_rewrite 'kubectl apply -f x.yaml' "kubectl apply $D -f x.yaml $D" 'same command with the parser present'

echo
echo "Passed: $PASS, Failed: $FAIL"
[ "$FAIL" -eq 0 ]
