#!/usr/bin/env bash
# PreToolUse hook for Bash tool - gates terraform apply behind terraform plan
#
# Blocks an apply that has not been reviewed, to prevent unintended resource
# creation, modification, or destruction:
#
#   terraform plan -out=tfplan     # generate and save the execution plan
#   terraform show tfplan          # inspect every planned change
#   terraform apply tfplan         # apply exactly that plan — ALLOWED
#
# An apply naming a saved plan file is allowed; a bare apply is not, and
# -auto-approve is blocked in every form.
#
# ── Why the match is command-position aware (#2506) ──────────────────────────
#
# The original matcher was `grep -qE '(^|\s)terraform\s+apply(\s|$)'` over the
# whole command string, which fires on any occurrence of the phrase — inside a
# quoted `gh pr edit --body`, inside a heredoc body, inside a `gh issue list
# --search` query. None of those execute anything, and an apply naming a saved
# plan file matched the same pattern, so the hook refused its own remedy.
#
# ── Why ast-grep, following bash-antipatterns.sh (#2008) ─────────────────────
#
# Command position is decided by `ast-grep --lang bash` (tree-sitter-bash), the
# same classifier `hooks-plugin/hooks/bash-antipatterns.sh` adopted in #2008. A
# real parse settles quoting, redirection, loops, conditionals and wrappers as a
# class:
#
#   - a heredoc body is a heredoc_body node, never a command
#   - `terraform apply 2>&1 | tee log` yields the command `terraform apply`;
#     the fd digit belongs to a file_redirect node, not to the argument list
#   - `for d in a b; do terraform apply; done` yields the inner command, with no
#     `do`/`then` keyword left glued to its front
#   - `timeout 300 terraform apply`, `env -i terraform apply`, `uv run terraform
#     apply` are one command node each, so neither a wrapper allowlist nor a
#     flag-arity table is needed to find the program
#   - `$(…)` and backticks, including inside double quotes, are their own
#     command nodes — the shell runs them, so the hook sees them
#
# A first draft hand-rolled this projection in awk. It produced six bypasses (a
# quoted `-auto-approve` counted as a plan file, a redirection fd digit counted
# as a plan file, `do`/`then` broke the walk, and any wrapper outside a
# seven-name allowlist made the statement invisible), each wanting its own
# patch. The parse removes the class rather than the instances.
#
# FAIL OPEN where ast-grep is absent, exactly as bash-antipatterns.sh does. A
# safety block that hard-fails without its parser is worse than one that defers.
# The cost is stated plainly: on a box with no ast-grep this hook does not fire
# at all, and plan-before-apply is back to being a convention. Set
# CLAUDE_HOOKS_TERRAFORM_APPLY_NO_ASTGREP=1 to force the no-op path (tests).
#
# ── What it still does not see ───────────────────────────────────────────────
#
# A program name assembled from an expansion — `A='terraform apply
# -auto-approve'; $A`, `TF=terra; ${TF}form apply` — carries no `terraform`
# token, so no version of this hook has ever caught it (verified: the pre-#2506
# whole-string regex, the awk draft and this parse all exit 0 on both). Closing
# it would mean re-entering every assignment's VALUE as shell, which blocks a
# bare `NOTE='we ran terraform apply'` — the #2506 false positive again. The
# gate is evadable by string-splitting, as the issue itself notes; it stops the
# unreviewed apply an agent writes by habit, not one written to evade it.
#
# ── Why this stays a hard block (.claude/rules/hook-block-vs-nudge.md) ───────
#
# An unreviewed apply is irreversible mutation of shared infrastructure, and the
# block does not exempt the dangerous variant — `-auto-approve` is refused in
# every form, including alongside a plan file. That is the opposite of the
# find/grep/ls demotions, so the exit 2 is earned where the parser is present.

set -euo pipefail

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null || true)

if [ -z "$COMMAND" ]; then exit 0; fi

block() {
    echo "$1" >&2
    exit 2
}

# `sg` is ast-grep's short binary name, but it collides with shadow-utils' sg(1)
# on essentially every Debian/Ubuntu box. Verify the resolved `sg` really is
# ast-grep before adopting it (#2451): `ast-grep --version` prints
# `ast-grep x.y.z`; shadow-utils' `sg --version` prints usage and exits non-zero.
ASTGREP=""
if [ "${CLAUDE_HOOKS_TERRAFORM_APPLY_NO_ASTGREP:-}" != "1" ]; then
    if command -v ast-grep >/dev/null 2>&1; then
        ASTGREP="ast-grep"
    elif command -v sg >/dev/null 2>&1 && sg --version 2>/dev/null | grep -qi '^ast-grep'; then
        ASTGREP="sg"
    fi
fi
[ -n "$ASTGREP" ] || exit 0

AST_RULE='id: shell-command
language: bash
rule:
  kind: command
'

# A command node's text can legitimately contain a newline (a quoted multi-line
# `--body`), so the node list is separated by SOH rather than by newlines — a
# line split would let a quoted body's second line pose as its own command.
CMD_SEP=$'\001'

# A literal backslash. Written as an ANSI-C escape because a single-quoted `'\'`
# is a shellcheck SC1003 trip hazard for every later reader.
BACKSLASH=$'\\'

# Every `command` node of a shell snippet. Any ast-grep or jq error yields an
# empty set, so a snippet tree-sitter cannot parse fails open, never blocks.
commands_of() {
    printf '%s' "$1" \
        | "$ASTGREP" scan --inline-rules "$AST_RULE" --stdin --json=compact 2>/dev/null \
        | jq -j --arg sep "$CMD_SEP" '.[] | .text, $sep' 2>/dev/null || true
}

# Split one command node into the argument vector the shell would build.
#
# Quotes are REMOVED rather than masked, because the shell removes them: the
# process really does receive `-auto-approve` from `terraform apply
# "-auto-approve"`. A quoted span still does not split on whitespace, so
# `--body "we ran terraform apply"` stays ONE argument whose value is the whole
# sentence — which is why a PR body quoting the phrase carries no `terraform`
# argument to find.
#
# Per token: TOK_VAL is the delivered value, TOK_Q records whether any part of
# it was quoted (a shell invoker's script argument is re-entered as shell), and
# TOK_E records an unresolvable expansion — `$VAR`, `$(…)`, a backtick — whose
# value this hook cannot know. `'$VAR'` is single-quoted and therefore literal,
# so it carries no expansion, matching what the shell delivers.
TOK_VAL=()
TOK_Q=()
TOK_E=()
tokenize() {
    # `local a=$1 b=${#a}` evaluates every assignment word before any of them
    # binds, so ${#s} would read an unset s under `set -u`. Split the two.
    local s=$1
    local n=${#s}
    local c depth
    local i=0
    local cur="" started=0 q=0 e=0
    TOK_VAL=()
    TOK_Q=()
    TOK_E=()
    # A hand-advanced cursor rather than nested `for ((i…))` loops: each inner
    # scan consumes a span and leaves `i` past it, which a shared for-loop index
    # expresses only by overriding its own parent (shellcheck SC2165/SC2167).
    while [ "$i" -lt "$n" ]; do
        c=${s:i:1}
        if [ "$c" = "'" ]; then
            q=1
            started=1
            i=$((i + 1))
            while [ "$i" -lt "$n" ] && [ "${s:i:1}" != "'" ]; do
                cur+=${s:i:1}
                i=$((i + 1))
            done
            i=$((i + 1))
            continue
        fi
        if [ "$c" = '"' ]; then
            q=1
            started=1
            i=$((i + 1))
            while [ "$i" -lt "$n" ]; do
                c=${s:i:1}
                if [ "$c" = '"' ]; then break; fi
                if [ "$c" = "$BACKSLASH" ]; then
                    i=$((i + 1))
                    cur+=${s:i:1}
                    i=$((i + 1))
                    continue
                fi
                if [ "$c" = '$' ] || [ "$c" = '`' ]; then e=1; fi
                cur+=$c
                i=$((i + 1))
            done
            i=$((i + 1))
            continue
        fi
        if [ "$c" = "$BACKSLASH" ]; then
            i=$((i + 1))
            cur+=${s:i:1}
            i=$((i + 1))
            started=1
            continue
        fi
        if [ "$c" = '$' ]; then
            e=1
            started=1
            cur+=$c
            i=$((i + 1))
            # Consume a balanced $(…) so its contents cannot be mistaken for
            # further arguments — `terraform apply $(ls tfplan)` must not leave
            # a bare `tfplan)` looking like a reviewed plan file.
            if [ "${s:i:1}" = "(" ]; then
                depth=0
                while [ "$i" -lt "$n" ]; do
                    c=${s:i:1}
                    cur+=$c
                    i=$((i + 1))
                    if [ "$c" = "(" ]; then depth=$((depth + 1)); fi
                    if [ "$c" = ")" ]; then
                        depth=$((depth - 1))
                        if [ "$depth" -le 0 ]; then break; fi
                    fi
                done
            fi
            continue
        fi
        if [ "$c" = '`' ]; then
            e=1
            started=1
            cur+=$c
            i=$((i + 1))
            while [ "$i" -lt "$n" ]; do
                c=${s:i:1}
                cur+=$c
                i=$((i + 1))
                if [ "$c" = '`' ]; then break; fi
            done
            continue
        fi
        case $c in
            ' ' | $'\t' | $'\n')
                if [ "$started" = 1 ]; then
                    TOK_VAL+=("$cur")
                    TOK_Q+=("$q")
                    TOK_E+=("$e")
                    cur=""
                    started=0
                    q=0
                    e=0
                fi
                ;;
            *)
                cur+=$c
                started=1
                ;;
        esac
        i=$((i + 1))
    done
    if [ "$started" = 1 ]; then
        TOK_VAL+=("$cur")
        TOK_Q+=("$q")
        TOK_E+=("$e")
    fi
    return 0
}

# Classify the arguments of one `terraform … apply …` invocation and block when
# the apply is unreviewed. $1 = index of the `apply` token, $2 = token count.
#
# A saved plan file is a positional operand that carries no `=` (so `-var
# foo=bar` is not one), is not the value of a preceding bare flag (so `-target
# aws_x.y` is not one either), and resolves to a literal name (so `$PLAN` or a
# substitution is not one — it could expand to `-auto-approve`).
classify_apply() {
    local j=$1 n=$2 k a prev
    local auto_approve=0 plan_file=0
    prev="apply"
    for ((k = j + 1; k < n; k++)); do
        a=${TOK_VAL[k]}
        case $a in
            -auto-approve | -auto-approve=* | --auto-approve | --auto-approve=*)
                auto_approve=1
                ;;
            -*) ;;
            *)
                if [ "${TOK_E[k]}" != 1 ] && [ "${a#*=}" = "$a" ]; then
                    case $prev in
                        -*=*) plan_file=1 ;;
                        -*) ;;
                        *) plan_file=1 ;;
                    esac
                fi
                ;;
        esac
        prev=$a
    done

    if [ "$auto_approve" = 1 ]; then
        block "TERRAFORM SAFETY: 'terraform apply -auto-approve' is blocked.

-auto-approve applies without any review of what will change. Save a plan,
inspect it, then apply that exact plan:

  terraform plan -out=tfplan
  terraform show tfplan
  terraform apply tfplan

'terraform apply tfplan' applies exactly the reviewed plan with no further
prompt, and is allowed by this hook. -auto-approve stays blocked in every form,
including alongside a plan file."
    fi

    if [ "$plan_file" = 1 ]; then
        return 0
    fi

    block "TERRAFORM SAFETY: Run 'terraform plan' before 'terraform apply'.

Review planned infrastructure changes first to prevent unintended modifications:

  terraform plan -out=tfplan
  terraform show tfplan
  terraform apply tfplan

An apply that names a saved plan file is allowed by this hook; a bare apply is
not. Rerun the apply referencing the plan file you reviewed, naming it
literally — a \$VAR or command substitution cannot be resolved here, so it does
not count as a plan file."
}

# Snippets still to scan. A shell invoker's script argument is text to
# tree-sitter but shell to the shell, so it is re-entered on the next pass.
QUEUE=("$COMMAND")
NEXT=()
SHELL_INVOKERS='sh|bash|zsh|ksh|dash|ash|eval'
MAX_DEPTH=3

depth=0
while [ "${#QUEUE[@]}" -gt 0 ] && [ "$depth" -le "$MAX_DEPTH" ]; do
    NEXT=()
    for snippet in "${QUEUE[@]}"; do
        while IFS= read -r -d "$CMD_SEP" cmd; do
            if [ -z "$cmd" ]; then continue; fi
            tokenize "$cmd"
            n=${#TOK_VAL[@]}
            if [ "$n" -eq 0 ]; then continue; fi

            # A shell invoker anywhere in this command's word list (so
            # `sudo -u tf bash -c '…'` counts too) makes every quoted argument
            # of the command a script rather than data.
            invoker=0
            for ((i = 0; i < n; i++)); do
                base=${TOK_VAL[i]##*/}
                if [[ $base =~ ^($SHELL_INVOKERS)$ ]]; then
                    invoker=1
                    break
                fi
            done
            if [ "$invoker" = 1 ]; then
                for ((i = 0; i < n; i++)); do
                    if [ "${TOK_Q[i]}" = 1 ]; then NEXT+=("${TOK_VAL[i]}"); fi
                done
            fi

            # Any token delivered as `terraform` (or `…/terraform`) is the
            # program of this command, or of the command its wrapper execs.
            for ((i = 0; i < n; i++)); do
                if [ "${TOK_VAL[i]##*/}" != "terraform" ]; then continue; fi
                # Skip terraform's own global options (-chdir=…, -help, …).
                j=$((i + 1))
                while [ "$j" -lt "$n" ] && [ "${TOK_VAL[j]:0:1}" = "-" ]; do
                    j=$((j + 1))
                done
                if [ "$j" -ge "$n" ]; then continue; fi
                if [ "${TOK_VAL[j]}" != "apply" ]; then continue; fi
                classify_apply "$j" "$n"
            done
        done < <(commands_of "$snippet")
    done
    # `"${NEXT[@]}"` on an EMPTY array is an unbound-variable fatal error under
    # `set -u` on bash 3.2, which is what `/usr/bin/env bash` finds on a stock
    # macOS. A PreToolUse hook runs on every Bash call, so that would surface as
    # exit 1 on every command the gate means to ALLOW.
    if [ "${#NEXT[@]}" -gt 0 ]; then
        QUEUE=("${NEXT[@]}")
    else
        QUEUE=()
    fi
    depth=$((depth + 1))
done

exit 0
