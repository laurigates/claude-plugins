#!/usr/bin/env bash
# shellcheck disable=SC2016   # single quotes are the point: every fixture is the
# LITERAL text a user typed, handed to the hook unexpanded.
# Regression tests for terraform-lock-pipe-guard.sh (#3849)
#
# Run: bash terraform-plugin/hooks/test-terraform-lock-pipe-guard.sh
# Exit 0 = all tests pass, Exit 1 = failures
#
# Every case pipes JSON into the SHIPPED hook; none of its logic is retyped
# here. Three verdicts are pinned, each with controls so that a hook which
# blocks (or nudges) everything cannot pass:
#
#   1. BLOCK (exit 2): a direct tofu/terraform plan|apply|destroy|refresh|import
#      or a locking `state` subcommand whose stdout reaches an early-closing
#      reader (head, sed …q, grep -m/-q) through a pipe. The reported incident
#      (#3849, 2026-11-24) is the first row.
#   2. NUDGE (exit 0 + additionalContext): a wrapper (`just plan`, `make plan`,
#      `terragrunt plan`, …) piped into the same readers. The hook cannot see a
#      recipe body, so it warns and lets the command run.
#   3. ALLOW (exit 0, silent): everything else — the prescribed remedy, readers
#      that consume all input (tail, tee, plain grep), commands that take no
#      lock, quoted text, and `&&` chains that only look like pipelines to
#      tree-sitter-bash.
#
# The prescription check extracts every command the block message tells the
# agent to run and feeds it back through the hook, which must allow it.
set -uo pipefail

HOOK="$(cd "$(dirname "$0")" && pwd)/terraform-lock-pipe-guard.sh"
PASS=0
FAIL=0

OUT=""
STDOUT=""
RC=0

run_hook() { # $1 = Bash command string; OUT = stdout+stderr, STDOUT = stdout
    local json errf
    json=$(jq -n --arg c "$1" '{tool_input: {command: $c}}')
    errf=$(mktemp "${TMPDIR:-/tmp}/tf-lock-pipe-test.XXXXXX")
    STDOUT=$(printf '%s' "$json" | bash "$HOOK" 2>"$errf")
    RC=$?
    OUT="$STDOUT$(cat "$errf")"
    rm -f "$errf"
}

pass() { PASS=$((PASS + 1)); }
fail() { FAIL=$((FAIL + 1)); echo "FAIL: $1"; }

# Without a parser the hook fails open by design, so every blocking case would
# read exit 0. Skip loudly; scripts/required-to-run-tests.txt turns the skip
# into an ERROR on CI, where ast-grep is installed on purpose.
if ! command -v ast-grep >/dev/null 2>&1 \
    && ! { command -v sg >/dev/null 2>&1 && sg --version 2>/dev/null | grep -qi '^ast-grep'; }; then
    echo "SKIP: ast-grep not installed (terraform-lock-pipe-guard.sh fails open without it, so nothing can block)"
    exit 0
fi

assert_blocked() { # $1 = command, $2 = label
    run_hook "$1"
    if [ "$RC" -eq 2 ] && grep -q 'TERRAFORM STATE LOCK:' <<<"$OUT"; then
        pass
    else
        fail "$2 — expected exit 2 with 'TERRAFORM STATE LOCK:', got $RC: $OUT"
    fi
}

assert_allowed() { # $1 = command, $2 = label — exit 0 and no output at all
    run_hook "$1"
    if [ "$RC" -eq 0 ] && [ -z "$OUT" ]; then
        pass
    else
        fail "$2 — expected silent exit 0, got $RC: $OUT"
    fi
}

assert_nudged() { # $1 = command, $2 = label — exit 0 with an additionalContext nudge
    run_hook "$1"
    local ctx
    ctx=$(printf '%s' "$STDOUT" \
        | jq -r 'select(.hookSpecificOutput.hookEventName == "PreToolUse") | .hookSpecificOutput.additionalContext // empty' 2>/dev/null)
    if [ "$RC" -eq 0 ] && grep -q 'TERRAFORM STATE LOCK (nudge):' <<<"$ctx"; then
        pass
    else
        fail "$2 — expected exit 0 with a 'TERRAFORM STATE LOCK (nudge):' additionalContext, got $RC: $OUT"
    fi
}

echo "=== block: direct tofu/terraform into an early-closing reader ==="

assert_blocked 'cd infra && tofu plan -no-color 2>&1 | head -20' \
    'the reported incident (#3849, 2026-11-24)'
assert_blocked 'tofu plan | head -20' 'tofu plan | head'
assert_blocked 'terraform plan | head' 'terraform plan | head'
assert_blocked 'tofu plan | sed -n "1,40p;40q"' 'sed -n …q'
assert_blocked 'tofu plan | sed 30q' 'sed NNq'
assert_blocked "tofu plan | sed '/Plan:/q'" 'sed /re/q'
assert_blocked "tofu plan | grep -m1 'Plan:'" 'grep -m1'
assert_blocked 'tofu plan | grep -m 1 Plan' 'grep -m 1 (separate value)'
assert_blocked 'tofu plan | grep --max-count=1 Plan' 'grep --max-count='
assert_blocked "tofu plan | grep -q 'No changes'" 'grep -q'
assert_blocked "tofu plan -no-color | grep -Eq 'Plan|No changes'" 'grep -Eq (flag cluster)'
assert_blocked 'tofu plan | egrep --quiet Plan' 'egrep --quiet'
assert_blocked 'tofu plan | tee tmp/plan.log | head' 'through tee into head'
assert_blocked 'tofu plan |& head' 'pipe with |&'
assert_blocked 'tofu apply tfplan | head' 'apply'
assert_blocked 'terraform destroy | head' 'destroy'
assert_blocked 'tofu refresh | head' 'refresh'
assert_blocked 'tofu import aws_instance.web i-123 | head' 'import'
assert_blocked 'tofu state mv a.b c.d | head' 'state mv'
assert_blocked 'terraform state rm a.b | grep -q Removed' 'state rm'
assert_blocked 'terraform -chdir=env/prod plan | head' 'global -chdir before the subcommand'
assert_blocked 'timeout 600 tofu plan | head' 'behind a wrapper'
assert_blocked '/usr/local/bin/tofu plan | head' 'absolute path'
assert_blocked "tofu plan 2>&1 "$'\\\n'"  | head -30" 'line continuation before the pipe'
assert_blocked 'for d in a b; do tofu -chdir=$d plan | head -5; done' 'inside a loop body'
assert_blocked 'while read -r d; do tofu -chdir=$d plan; done < envs.txt | head' \
    'loop whose output is piped'
assert_blocked '(cd infra && tofu plan) | head' 'subshell piped'
assert_blocked '{ tofu plan; } | head' 'brace group piped'
assert_blocked 'echo "$(tofu plan | head)"' 'pipeline inside a command substitution'
assert_blocked 'bash -c "tofu plan | head"' 'shell invoker with a double-quoted script'
assert_blocked "sh -c 'terraform plan | grep -m3 x'" 'shell invoker with a single-quoted script'

echo "=== block message: names the fix and the recovery ==="

run_hook 'cd infra && tofu plan -no-color 2>&1 | head -20'
if grep -q 'tofu force-unlock' <<<"$OUT"; then pass; else fail "message omits the force-unlock recovery: $OUT"; fi
if grep -q 'pgrep -x tofu' <<<"$OUT"; then pass; else fail "message omits 'pgrep -x tofu': $OUT"; fi
if grep -q 'Read tool' <<<"$OUT"; then pass; else fail "message omits the Read-the-file step: $OUT"; fi
if grep -qE '^[[:space:]]+mkdir -p tmp && tofu plan -no-color > tmp/tf-plan\.txt 2>&1$' <<<"$OUT"; then
    pass
else
    fail "message does not prescribe the stage redirected to tmp/tf-plan.txt: $OUT"
fi

run_hook 'terraform plan | head'
if grep -q 'pgrep -x terraform' <<<"$OUT" && grep -q 'terraform force-unlock' <<<"$OUT"; then
    pass
else
    fail "message does not name the program actually run (terraform): $OUT"
fi

# Feed the message's own prescription back through the hook. A prescription the
# hook refuses would leave the agent with no allowed path.
check_prescriptions() { # $1 = command that blocks, $2 = label
    run_hook "$1"
    if [ "$RC" -ne 2 ]; then
        fail "$2 — fixture did not block, so its message cannot be checked"
        return
    fi
    local line cmd count=0
    while IFS= read -r line; do
        cmd=$(printf '%s' "$line" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')
        [ -n "$cmd" ] || continue
        count=$((count + 1))
        run_hook "$cmd"
        if [ "$RC" -eq 0 ] && [ -z "$OUT" ]; then
            pass
        else
            fail "$2 — the message prescribes '$cmd', which the hook does not silently allow (exit $RC): $OUT"
        fi
    done < <(printf '%s\n' "$OUT" | grep -E '^[[:space:]]+(mkdir|tofu|terraform|timeout) ')

    if [ "$count" -ge 1 ]; then
        pass
    else
        fail "$2 — expected >=1 prescribed command in the message, found $count"
    fi
}

check_prescriptions 'cd infra && tofu plan -no-color 2>&1 | head -20' 'reported shape'
check_prescriptions 'timeout 600 terraform apply tfplan | grep -m1 Apply' 'wrapped apply'

echo "=== nudge: wrappers whose recipe body the hook cannot see ==="

assert_nudged 'just plan | head -20' 'just plan | head'
assert_nudged 'just tf-plan prod | grep -m5 Plan' 'just tf-plan | grep -m5'
assert_nudged 'make plan | head' 'make plan | head'
assert_nudged 'mise run tf:plan | sed 20q' 'mise run tf:plan | sed 20q'
assert_nudged 'terragrunt run-all plan | head' 'terragrunt run-all plan | head'
assert_nudged 'cd infra && just apply | grep -q Apply' 'just apply after cd'

echo "=== allow: the remedy and readers that consume everything ==="

assert_allowed 'tofu plan > tmp/plan.txt 2>&1' 'the remedy: redirect to a file'
assert_allowed 'mkdir -p tmp && tofu plan -no-color > tmp/tf-plan.txt 2>&1' 'the remedy as prescribed'
assert_allowed 'tofu plan > tmp/plan.txt 2>&1 && head -50 tmp/plan.txt' 'head on the finished file'
# tree-sitter-bash parses `a && b | c` as `(a && b) | c`; bash runs `a && (b | c)`.
# The tofu stage here is not in the pipeline at all.
assert_allowed 'tofu plan > tmp/plan.txt 2>&1 && grep -m1 Plan tmp/plan.txt | head' \
    'an && chain that tree-sitter reads as a pipeline'
assert_allowed 'tofu plan > f.txt 2>&1; cat f.txt | head' 'sequence, then a separate pipeline'
assert_allowed 'tofu plan > tmp/plan.txt | head' 'stdout redirected to a file before the pipe'
assert_allowed 'tofu plan | tee tmp/plan.txt' 'tee alone reads everything'
assert_allowed 'tofu plan | tail -40' 'tail reads everything'
assert_allowed 'tofu plan | grep Plan' 'grep without -m/-q reads everything'
assert_allowed "tofu plan | sed -n '1,40p'" 'sed without q reads everything'
assert_allowed "tofu plan | sed 's/q/x/'" 'a q inside an s command is not a quit'
assert_allowed 'tofu plan -lock=false | head' 'no lock taken'
assert_allowed 'tofu state list | head' 'state list takes no lock'
assert_allowed 'terraform state show aws_instance.web | head' 'state show takes no lock'
assert_allowed 'tofu validate | head' 'validate takes no lock'
assert_allowed 'tofu fmt -check -recursive | head' 'fmt takes no lock'
assert_allowed 'tofu output -json | head' 'output takes no lock'
assert_allowed 'echo $(tofu plan) | head' 'a substitution captures all output before head runs'
assert_allowed 'head -20 plan.txt | grep tofu' 'no tofu stage'
assert_allowed 'just plan > tmp/plan.txt 2>&1' 'wrapper redirected to a file'
assert_allowed 'just plan | tee tmp/plan.txt' 'wrapper into tee'
assert_allowed 'just test | head' 'a wrapper recipe with no plan-like name'

echo "=== allow: the phrase is data, not a command ==="

assert_allowed 'gh pr comment 1 --body "never run tofu plan | head -20"' 'quoted in a PR comment body'
assert_allowed "echo 'tofu plan | head -20'" 'single-quoted echo argument'
assert_allowed "$(printf '%s\n' "git commit -F - <<'EOF'" 'docs: tofu plan | head orphans the lock' 'EOF')" \
    'heredoc body'
assert_allowed 'echo hello' 'unrelated command'

run_hook ''
if [ "$RC" -eq 0 ] && [ -z "$OUT" ]; then pass; else fail "empty command — expected silent exit 0, got $RC: $OUT"; fi

echo "=== the parser is really the classifier (fail-open, and it is present) ==="

FAILOPEN_JSON=$(jq -n --arg c 'tofu plan | head' '{tool_input: {command: $c}}')
if printf '%s' "$FAILOPEN_JSON" \
    | CLAUDE_HOOKS_TERRAFORM_LOCK_PIPE_NO_ASTGREP=1 bash "$HOOK" >/dev/null 2>&1; then
    pass
else
    fail "with the parser suppressed the hook must fail open (exit 0)"
fi

run_hook 'tofu plan | head'
if [ "$RC" -eq 2 ]; then
    pass
else
    fail "the same command blocks only when the parser is available — it did not, so every row above is vacuous"
fi

# `"${arr[@]}"` on an empty array is fatal under `set -u` before bash 4.4, and
# `#!/usr/bin/env bash` finds 3.2 on a stock macOS. Run allow-cases through
# /bin/bash itself so that regression shows up as a failed row.
SYSTEM_BASH_VERSION=$(/bin/bash -c 'echo "${BASH_VERSINFO[0]}.${BASH_VERSINFO[1]}"' 2>/dev/null || echo unknown)
echo "system /bin/bash: $SYSTEM_BASH_VERSION"
for legacy_case in 'echo hello' 'tofu plan > tmp/plan.txt 2>&1' 'tofu plan | tail'; do
    LEGACY_JSON=$(jq -n --arg c "$legacy_case" '{tool_input: {command: $c}}')
    if printf '%s' "$LEGACY_JSON" | /bin/bash "$HOOK" >/dev/null 2>&1; then
        pass
    else
        fail "under /bin/bash $SYSTEM_BASH_VERSION an allowed command must exit 0: $legacy_case"
    fi
done

echo
echo "Passed: $PASS, Failed: $FAIL"
[ "$FAIL" -eq 0 ]
