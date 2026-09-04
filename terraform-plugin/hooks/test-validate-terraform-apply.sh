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

echo "=== the six bypasses the awk projection had (wave-1 review) ==="

# Each of these executed a real, unreviewed apply while the awk tokenizer
# reported exit 0. They are pinned individually so the parse cannot regress into
# any one of them; a stub terraform confirmed the shell delivers `[apply]
# [-auto-approve]` for the quoted spellings.

# 1. A quoted argument collapsed to the `__Q__` placeholder was counted as a
#    saved plan file, so quoting the flag disabled the -auto-approve branch.
assert_blocked 'terraform apply "-auto-approve"' 'double-quoted -auto-approve'
assert_blocked "terraform apply '-auto-approve'" 'single-quoted -auto-approve'

# 2. The same rule made ANY quoted argument look like a reviewed plan.
assert_blocked 'terraform apply "-refresh=false"' \
    'a quoted flag is not a plan file'
assert_blocked "terraform apply '-refresh=false'" \
    'a single-quoted flag is not a plan file'

# 3. `<`/`>` were plain separators, so a redirection left its fd digit behind as
#    a positional operand that read as a plan file.
assert_blocked 'terraform apply 2>&1 | tee /tmp/tf.log' \
    'a redirection fd digit is not a plan file'
assert_blocked 'terraform apply 2> /dev/null' \
    'a redirection target is not a plan file'
assert_blocked 'terraform apply > /tmp/tf.log' \
    'stdout redirection leaves a bare apply'

# 4. Splitting at `;` left `do`/`then` as the first token and the walker broke
#    on the unknown word rather than skipping it.
assert_blocked 'for d in a b; do terraform apply -auto-approve; done' \
    'apply inside a for loop body'
assert_blocked 'if [ -f x ]; then terraform apply -auto-approve; fi' \
    'apply inside an if body'
assert_blocked 'while read -r d; do terraform apply; done < envs.txt' \
    'apply inside a while loop body'

# 5. The wrapper allowlist was a closed seven-name set, so any other leading
#    word made the whole statement invisible.
assert_blocked 'timeout 300 terraform apply -auto-approve' 'apply behind timeout'
assert_blocked 'nice terraform apply -auto-approve' 'apply behind nice'
assert_blocked 'stdbuf -oL terraform apply -auto-approve' 'apply behind stdbuf'
assert_blocked 'echo x | xargs terraform apply -auto-approve' 'apply behind xargs'
assert_blocked 'uv run terraform apply -auto-approve' 'apply behind uv run'
assert_blocked 'eval terraform apply' 'apply behind an unquoted eval'

# 6. After a wrapper, a bare short flag unconditionally consumed the next token,
#    which was the program itself.
assert_blocked 'env -i terraform apply' "env -i must not swallow the program"
assert_blocked 'time -p terraform apply' "time -p must not swallow the program"
assert_blocked 'sudo -u ci terraform apply' "sudo -u's value must not swallow it"

# The nit from the same review: a shell invoker behind a wrapper.
assert_blocked 'sudo -u tf bash -c "terraform apply"' \
    'shell invoker reached through a wrapper'

# Controls for this section. Each new mechanism above could be satisfied by
# blocking everything, so each one is paired with a shape that must still pass.
assert_allowed 'timeout 300 terraform plan -out=tfplan' \
    'a wrapper around a non-apply subcommand'
assert_allowed 'timeout 300 terraform apply tfplan' \
    'a wrapper around an apply naming a plan file'
assert_allowed 'for d in a b; do terraform plan -out=tfplan; done' \
    'a loop body running plan'
assert_allowed 'echo "then run terraform apply -auto-approve" > /tmp/tf-note.txt' \
    'the phrase quoted in a redirected echo'
assert_allowed 'terraform apply "tfplan" 2> /dev/null' \
    'a redirection alongside a real plan file'
assert_allowed 'gh pr comment 1 --body "for d in envs; do terraform apply; done"' \
    'a loop quoted inside a PR comment body'

echo "=== unrelated commands are untouched ==="

assert_allowed 'terraform plan -out=tfplan' 'plan only (control)'
assert_allowed 'echo hello' 'unrelated command'
assert_allowed 'terraform show tfplan' 'terraform subcommand other than apply'
assert_allowed 'ansible-playbook apply.yml' 'a different program named ...apply'

run_hook ''
if [ "$RC" -eq 0 ]; then pass; else fail "empty command — expected exit 0, got $RC"; fi

echo "=== the parser is really the classifier (fail-open, and it is present) ==="

# Two halves of one claim. Without the first, every green row above could come
# from a hook that no-ops; without the second, the fail-open path is prose.
FAILOPEN_JSON=$(jq -n --arg c 'terraform apply -auto-approve' '{tool_input: {command: $c}}')
if printf '%s' "$FAILOPEN_JSON" \
    | CLAUDE_HOOKS_TERRAFORM_APPLY_NO_ASTGREP=1 bash "$HOOK" >/dev/null 2>&1; then
    pass
else
    fail "with the parser suppressed the hook must fail open (exit 0)"
fi

run_hook 'terraform apply -auto-approve'
if [ "$RC" -eq 2 ]; then
    pass
else
    fail "the same command blocks only when the parser is available — it was not, so every assertion above is vacuous"
fi

# `"${arr[@]}"` on an EMPTY array is a fatal unbound-variable error under
# `set -u` before bash 4.4, and `#!/usr/bin/env bash` finds bash 3.2 on a stock
# macOS. The symptom is exit 1 on every command the hook means to ALLOW, so it
# never shows up in a blocked-case assertion. `BASH_COMPAT` does not restore the
# old behaviour, so the only way to pin it is to run the real interpreter: this
# is a live pin wherever /bin/bash is 3.x (every un-Homebrewed macOS) and a
# second pass under an equivalent shell on Linux, where /bin/bash is 5.x.
SYSTEM_BASH_VERSION=$(/bin/bash -c 'echo "${BASH_VERSINFO[0]}.${BASH_VERSINFO[1]}"' 2>/dev/null || echo unknown)
echo "system /bin/bash: $SYSTEM_BASH_VERSION"
for legacy_case in 'echo hello' 'terraform apply tfplan' 'terraform plan -out=tfplan'; do
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
