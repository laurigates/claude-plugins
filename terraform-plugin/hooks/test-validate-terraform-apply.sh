#!/usr/bin/env bash
# shellcheck disable=SC2016   # single quotes are the point: every fixture is the
# LITERAL text a user typed, handed to the hook unexpanded. Letting the harness
# expand `$(…)` or `$PLAN` would test this shell, not the hook.
# Regression tests for validate-terraform-apply.sh (#2506)
#
# Run: bash terraform-plugin/hooks/test-validate-terraform-apply.sh
# Exit 0 = all tests pass, Exit 1 = failures
#
# Every case pipes JSON into the SHIPPED hook — none of its logic is retyped
# here, so a fix that only looks right on paper cannot pass.
#
# Two properties are pinned, and the second is the one the reporter could not
# satisfy at all:
#
#   1. Command position. The three reported false positives (a `gh pr edit
#      --body` quoting the phrase, a `python3` heredoc body carrying it, a
#      read-only `gh issue list --search`) must be ALLOWED, while a real apply
#      must still block. The negative and positive halves are weighted equally:
#      a hook that allowed everything would satisfy the first half alone.
#
#   2. The prescription is reachable. Rather than grepping the block message for
#      a literal, every `terraform …` command the message prescribes is
#      EXTRACTED from that message and fed back into the hook, which must allow
#      it. A message that prescribes a command it refuses is what #2506 reported,
#      and a literal grep would not notice the message drifting back into one.
set -uo pipefail

HOOK="$(cd "$(dirname "$0")" && pwd)/validate-terraform-apply.sh"
PASS=0
FAIL=0

OUT=""
RC=0

run_hook() { # $1 = Bash command string
    local json
    json=$(jq -n --arg c "$1" '{tool_input: {command: $c}}')
    OUT=$(printf '%s' "$json" | bash "$HOOK" 2>&1)
    RC=$?
}

pass() { PASS=$((PASS + 1)); }
fail() { FAIL=$((FAIL + 1)); echo "FAIL: $1"; }

assert_allowed() { # $1 = command, $2 = label
    run_hook "$1"
    if [ "$RC" -eq 0 ]; then
        pass
    else
        fail "$2 — expected exit 0, got $RC: $OUT"
    fi
}

assert_blocked() { # $1 = command, $2 = label
    run_hook "$1"
    if [ "$RC" -eq 2 ]; then
        pass
    else
        fail "$2 — expected exit 2, got $RC"
    fi
}

echo "=== reported false positives (#2506): the phrase is not a command ==="

assert_allowed \
    'gh pr edit 12 --body "we ran terraform apply here for the targeted rollout"' \
    'gh pr edit --body quoting the phrase'

assert_allowed \
    'gh issue list --search "validate-terraform-apply terraform apply hook"' \
    'read-only gh issue list --search quoting the phrase'

assert_allowed \
    "$(printf '%s\n' \
        "python3 - <<'PY'" \
        'body = """' \
        'The rollout ran terraform apply against the prod workspace.' \
        '"""' \
        'print(body)' \
        'PY')" \
    'python3 heredoc body carrying the phrase'

assert_allowed \
    'terraform plan -out=tfplan && echo "then terraform apply"' \
    'the phrase inside a quoted echo argument'

assert_allowed \
    'git commit -F - <<EOF
docs: record that terraform apply is gated
EOF' \
    'git commit heredoc body carrying the phrase'

echo "=== the prescribed remedy is reachable ==="

assert_allowed 'terraform apply tfplan' 'apply naming a saved plan file'
assert_allowed 'terraform plan -out=tfplan && terraform apply tfplan' \
    'plan-then-apply chain'
assert_allowed 'terraform apply -input=false tfplan' \
    'apply with a valued flag plus a plan file'
assert_allowed 'terraform -chdir=env/prod apply tfplan' \
    'global -chdir with a plan file'

# Feed each message's own prescription back through the hook. A prescription
# the hook refuses is exactly the defect #2506 reported.
check_prescriptions() { # $1 = command that blocks, $2 = label
    run_hook "$1"
    if [ "$RC" -ne 2 ]; then
        fail "$2 — fixture did not block, so its message cannot be checked"
        return
    fi
    local line cmd count=0
    while IFS= read -r line; do
        cmd=${line%%#*}
        cmd=$(printf '%s' "$cmd" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')
        [ -n "$cmd" ] || continue
        count=$((count + 1))
        run_hook "$cmd"
        if [ "$RC" -eq 0 ]; then
            pass
        else
            fail "$2 — the message prescribes '$cmd', which the hook refuses (exit $RC)"
        fi
    done < <(printf '%s\n' "$OUT" | grep -E '^[[:space:]]+terraform ')

    # Non-vacuity: an empty extraction would make every assertion above silent.
    if [ "$count" -ge 3 ]; then
        pass
    else
        fail "$2 — expected >=3 prescribed commands in the message, found $count"
    fi
}

check_prescriptions 'terraform apply' 'standard block message'
check_prescriptions 'terraform apply -auto-approve' 'auto-approve block message'

echo "=== guard integrity: real applies still block ==="

assert_blocked 'terraform apply' 'bare apply'
assert_blocked 'terraform apply -auto-approve' 'auto-approve'
assert_blocked 'terraform apply -auto-approve tfplan' \
    'auto-approve alongside a plan file (blocked in every form)'
assert_blocked 'terraform -chdir=env/prod apply' \
    'bare apply behind a global -chdir'
assert_blocked 'terraform apply -var foo=bar' \
    'an operand carrying = is not a plan file'
assert_blocked 'terraform apply -target aws_instance.web' \
    "a bare flag's value is not a plan file"
assert_blocked 'sudo terraform apply' 'apply behind sudo'
assert_blocked 'cd infra && terraform apply' \
    'apply as the second statement of a compound command'
assert_blocked '/usr/local/bin/terraform apply' 'apply invoked by absolute path'

echo "=== masking a span must not open a bypass ==="

# A quoted span is data, but two things inside one are not: a command
# substitution the shell runs, and the argument of a shell invoker. The old
# whole-string matcher blocked both; allowing them would trade the reported
# false positives for a silent hole.
assert_blocked 'echo "$(terraform apply)"' \
    'command substitution inside double quotes'
assert_blocked 'terraform plan -out=tfplan && echo "$(terraform apply -auto-approve)"' \
    'auto-approve inside a command substitution'
assert_blocked 'echo "`terraform apply`"' \
    'backtick substitution inside double quotes'
assert_blocked 'bash -c "terraform apply"' 'shell invoker with a double-quoted script'
assert_blocked "sh -c 'terraform apply'" 'shell invoker with a single-quoted script'
assert_blocked 'eval "terraform apply"' 'eval of a quoted apply'

# An operand the hook cannot resolve could expand to anything, -auto-approve
# included, so it does not count as a reviewed plan file.
assert_blocked 'A=-auto-approve; terraform apply $A' \
    'a plan-file-shaped operand that is really a variable'
assert_blocked 'terraform apply $PLAN' 'unresolved variable operand'
assert_blocked 'terraform apply "$PLAN"' 'unresolved variable operand, quoted'
assert_blocked 'terraform apply $(ls tfplan)' 'command-substitution operand'

# A here-string is not a heredoc: arming body suppression on `<<<` would swallow
# every later line of a multi-line command.
assert_blocked "$(printf '%s\n' 'cat <<<"$V"' 'terraform apply')" \
    'apply on the line after a here-string'

# Guard integrity for this section: the invoker and substitution rules must not
# blanket-block, or every assertion above passes for the wrong reason.
assert_allowed 'bash -c "echo hi"' 'shell invoker running something unrelated'
assert_allowed 'echo "$(date)"' 'command substitution running something unrelated'
assert_allowed 'terraform apply "tfplan"' 'a quoted plan file is still an operand'

echo "=== unrelated commands are untouched ==="

assert_allowed 'terraform plan -out=tfplan' 'plan only (control)'
assert_allowed 'echo hello' 'unrelated command'
assert_allowed 'terraform show tfplan' 'terraform subcommand other than apply'
assert_allowed 'ansible-playbook apply.yml' 'a different program named ...apply'

run_hook ''
if [ "$RC" -eq 0 ]; then pass; else fail "empty command — expected exit 0, got $RC"; fi

echo
echo "Passed: $PASS, Failed: $FAIL"
[ "$FAIL" -eq 0 ]
