#!/usr/bin/env bash
# PreToolUse hook for the Bash tool: a tofu/terraform run piped into an
# early-closing reader can orphan the remote state lock (#3849).
#
# ── The hazard ───────────────────────────────────────────────────────────────
#
# `tofu plan` (and apply, destroy, refresh, import, and the state subcommands
# that write) holds the backend lock for its whole run; -lock=true is the
# default. A reader that exits before end of input (`head`, `sed …q`,
# `grep -m N`, `grep -q`) closes the pipe, the next write delivers SIGPIPE, and
# tofu dies mid-run without releasing the lock. In the incident behind #3849
# (2026-11-24), `just plan | head -20` left a GCS lock (Operation:
# OperationTypePlan) that failed every later plan, CI applies included, with
# `Error acquiring the state lock … 412 conditionNotMet` until someone ran
# `tofu force-unlock` by hand.
#
# ── Verdicts (Lauri's decision on #3849, 2026-11-28) ─────────────────────────
#
#   BLOCK (exit 2)  a direct tofu/terraform lock-taking invocation whose stdout
#                   reaches an early-closing reader through a pipe. The lock
#                   blocks other actors (CI), which is the shared-state harm
#                   .claude/rules/hook-block-vs-nudge.md reserves exit 2 for.
#   NUDGE (exit 0)  a wrapper (`just plan`, `make plan`, `mise run tf:plan`,
#                   `terragrunt plan`, `task plan`) piped the same way. The
#                   recipe body is not visible here, so the hook warns through
#                   additionalContext and lets the command run.
#   ALLOW           everything else, silently.
#
# Not lock-taking, so never flagged: `-lock=false`, `state list|show|pull`,
# validate, fmt, output, providers, version, show. Readers that drain their
# input (tail, tee, wc, plain grep, sed without q) are not early-closing.
#
# ── How the pipe is found ────────────────────────────────────────────────────
#
# Command position comes from `ast-grep --lang bash` (tree-sitter-bash), the
# same classifier validate-terraform-apply.sh uses (#2506): heredoc bodies and
# quoted strings carry no command nodes, so `gh pr comment --body "tofu plan |
# head"` is data. The pipe itself is NOT read off tree-sitter's `pipeline` node:
# tree-sitter-bash parses `a && b | c` as `(a && b) | c`, while bash runs
# `a && (b | c)`, so `tofu plan > f 2>&1 && grep -m1 x f | head` would look like
# tofu feeding head. Instead, for each command node the hook reads the source
# text between it and the next command node. That gap must be a pipe (`|` or
# `|&`), optionally after redirections that do not send stdout to a file and
# after the closers `)`, `}`, `done`, `fi`, `esac` — so `(cd x && tofu plan) |
# head` and `while …; do tofu plan; done | head` are found. Both nodes must
# share their innermost enclosing command node, which keeps `echo $(tofu plan)
# | head` (the substitution captures everything first) apart from `echo "$(tofu
# plan | head)"` (a real pipe inside the substitution).
#
# Known gaps: a tofu stage that is not the last command of a group before the
# pipe (`(tofu plan; echo done) | head`), process substitution (`grep -m1 x <(
# tofu plan)`), readers other than head/sed/grep (`awk 'NR==5{exit}'`, `rg -m`),
# and a program name assembled from an expansion.
#
# FAIL OPEN where ast-grep is absent, as validate-terraform-apply.sh and
# bash-antipatterns.sh do: a PreToolUse hook that hard-fails without its parser
# breaks every Bash call. Set CLAUDE_HOOKS_TERRAFORM_LOCK_PIPE_NO_ASTGREP=1 to
# force the no-op path (tests).

set -euo pipefail

# Byte offsets from ast-grep index the command string; under the C locale bash
# substring expansion counts bytes too, so a multi-byte character cannot shift
# a gap.
export LC_ALL=C

INPUT=$(cat)
COMMAND=$(jq -r '.tool_input.command // empty' <<<"$INPUT" 2>/dev/null || true)

if [ -z "$COMMAND" ]; then exit 0; fi

ASTGREP=""
if [ "${CLAUDE_HOOKS_TERRAFORM_LOCK_PIPE_NO_ASTGREP:-}" != "1" ]; then
    if command -v ast-grep >/dev/null 2>&1; then
        ASTGREP="ast-grep"
    elif command -v sg >/dev/null 2>&1 && sg --version 2>/dev/null | grep -qi '^ast-grep'; then
        # `sg` collides with shadow-utils' sg(1); accept it only when it is
        # really ast-grep (#2451).
        ASTGREP="sg"
    fi
fi
[ -n "$ASTGREP" ] || exit 0

AST_RULE='id: shell-command
language: bash
rule:
  kind: command
'

BACKSLASH=$'\\'

# Start and end byte offsets of every `command` node, one "start end" pair per
# line, in source order. Any ast-grep or jq error yields nothing: fail open.
command_ranges() {
    printf '%s' "$1" \
        | "$ASTGREP" scan --inline-rules "$AST_RULE" --stdin --json=compact 2>/dev/null \
        | jq -r 'sort_by(.range.byteOffset.start) | .[] | "\(.range.byteOffset.start) \(.range.byteOffset.end)"' 2>/dev/null \
        || true
}

# Split one command node into the argument vector the shell would build. A copy
# of the tokenizer in validate-terraform-apply.sh (#2506): quotes are removed,
# a quoted span does not split, TOK_Q marks a quoted token (a shell invoker's
# script), TOK_E marks an unresolvable expansion.
TOK_VAL=()
TOK_Q=()
TOK_E=()
tokenize() {
    local s=$1
    local n=${#s}
    local c depth
    local i=0
    local cur="" started=0 q=0 e=0
    TOK_VAL=()
    TOK_Q=()
    TOK_E=()
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
            # A backslash-newline is a line continuation, not an argument.
            if [ "${s:i:1}" != $'\n' ]; then
                cur+=${s:i:1}
                started=1
            fi
            i=$((i + 1))
            continue
        fi
        if [ "$c" = '$' ]; then
            e=1
            started=1
            cur+=$c
            i=$((i + 1))
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

# Set LOCK_PROG / LOCK_SUB when the tokenized command runs a lock-taking
# tofu/terraform subcommand. Returns 1 otherwise.
LOCK_PROG=""
LOCK_SUB=""
lock_op() {
    local n=${#TOK_VAL[@]} i j k prog sub
    for ((i = 0; i < n; i++)); do
        prog=${TOK_VAL[i]##*/}
        if [ "$prog" != "tofu" ] && [ "$prog" != "terraform" ]; then continue; fi
        # Skip global options (-chdir=…).
        j=$((i + 1))
        while [ "$j" -lt "$n" ] && [ "${TOK_VAL[j]:0:1}" = "-" ]; do
            j=$((j + 1))
        done
        [ "$j" -lt "$n" ] || continue
        sub=${TOK_VAL[j]}
        case $sub in
            plan | apply | destroy | refresh | import) ;;
            state)
                # list/show/pull read state without locking; these write it.
                case ${TOK_VAL[j + 1]:-} in
                    mv | rm | push | replace-provider) sub="state ${TOK_VAL[j + 1]}" ;;
                    *) continue ;;
                esac
                ;;
            *) continue ;;
        esac
        for ((k = j + 1; k < n; k++)); do
            case ${TOK_VAL[k]} in
                -lock=false | --lock=false) continue 2 ;;
            esac
        done
        LOCK_PROG=$prog
        LOCK_SUB=$sub
        return 0
    done
    return 1
}

# Returns 0 when the tokenized command runs a wrapper whose arguments name a
# plan-like recipe or tofu/terraform. Sets WRAP_PROG.
WRAP_PROG=""
wrapper_op() {
    local n=${#TOK_VAL[@]} i k base a
    for ((i = 0; i < n; i++)); do
        base=${TOK_VAL[i]##*/}
        case $base in
            just | make | mise | task | terragrunt) ;;
            *) continue ;;
        esac
        for ((k = i + 1; k < n; k++)); do
            a=${TOK_VAL[k]}
            if [[ $a =~ (^|[-_:/.])(plan|apply|destroy|refresh|import)([-_:/.]|$) ]] \
                || [[ $a == *tofu* ]] || [[ $a == *terraform* ]]; then
                WRAP_PROG=$base
                return 0
            fi
        done
    done
    return 1
}

# Returns 0 when the tokenized command is a reader that exits before end of
# input. Sets READER.
READER=""
early_reader() {
    local n=${#TOK_VAL[@]} k a prog
    [ "$n" -gt 0 ] || return 1
    prog=${TOK_VAL[0]##*/}
    case $prog in
        head)
            READER="head"
            return 0
            ;;
        grep | egrep | fgrep)
            for ((k = 1; k < n; k++)); do
                a=${TOK_VAL[k]}
                case $a in
                    --) break ;;
                    --max-count | --max-count=* | --quiet | --silent)
                        READER="$prog $a"
                        return 0
                        ;;
                    --*) ;;
                    -*)
                        # A short-flag cluster: -q, -m1, -Eq, -im5.
                        if [[ ${a:1} =~ ^[A-Za-z]*[qm] ]]; then
                            READER="$prog $a"
                            return 0
                        fi
                        ;;
                esac
            done
            ;;
        sed)
            # A `q`/`Q` command in any script operand: `30q`, `/re/q`,
            # `1,40p;40q`. A q inside s/…/…/ is followed by a delimiter, not
            # by end of command, so `s/q/x/` does not match.
            for ((k = 1; k < n; k++)); do
                a=${TOK_VAL[k]}
                case $a in
                    -e | --expression=* | -n | --quiet | --silent | -E | -r) continue ;;
                esac
                if [[ $a =~ (^|[0-9$/;{}[:space:]])[qQ][0-9]*[[:space:]]*(;|\}|$) ]]; then
                    READER="sed …q"
                    return 0
                fi
            done
            ;;
    esac
    return 1
}

# 0 when the source text between two command nodes is a pipe that carries the
# first node's stdout.
gap_is_pipe() {
    local g=$1
    # Quoted: an unquoted backslash in a ${…//pattern/} is a glob escape.
    g=${g//"$BACKSLASH"$'\n'/ }
    # stdout sent to a file: the pipe receives nothing from this stage.
    if [[ $g =~ (^|[[:space:]])(1?>>?|&>>?|>\|)[[:space:]]*[^[:space:]\&|] ]]; then
        return 1
    fi
    # Drop fd duplications (2>&1, >&2) and redirections of other fds.
    g=$(sed -E \
        -e 's/[0-9]*[<>]&[0-9]+-?//g' \
        -e 's/[0-9]+>>?[[:space:]]*[^[:space:]|;&<>]+//g' \
        -e 's/[0-9]*<[[:space:]]*[^[:space:]|;&<>]+//g' <<<"$g")
    g=${g//$'\n'/;}
    g=${g//[[:space:]]/}
    [[ $g =~ ^(\;*(\)|\}|done|fi|esac))*\|\&?$ ]]
}

block() {
    echo "$1" >&2
    exit 2
}

NUDGE_MSG=""

# One snippet: find every lock-taking stage whose output reaches an early
# reader. Blocks on the first direct hit; records a nudge for a wrapper hit.
# Appends the quoted arguments of shell invokers to REENTER for the next pass.
REENTER=()
scan_snippet() {
    local snip=$1
    local -a S=() E=() TXT=() CONT=()
    local s e i j m n best len
    while read -r s e; do
        [ -n "$s" ] || continue
        S+=("$s")
        E+=("$e")
        TXT+=("${snip:s:e-s}")
    done < <(command_ranges "$snip")
    m=${#S[@]}
    [ "$m" -gt 0 ] || return 0

    # Innermost enclosing command node of each node, or -1.
    for ((i = 0; i < m; i++)); do
        best=-1
        len=-1
        for ((j = 0; j < m; j++)); do
            [ "$j" -ne "$i" ] || continue
            if [ "${S[j]}" -le "${S[i]}" ] && [ "${E[j]}" -ge "${E[i]}" ] \
                && { [ "${S[j]}" -ne "${S[i]}" ] || [ "${E[j]}" -ne "${E[i]}" ]; }; then
                if [ "$best" -eq -1 ] || [ $((E[j] - S[j])) -lt "$len" ]; then
                    best=$j
                    len=$((E[j] - S[j]))
                fi
            fi
        done
        CONT+=("$best")
    done

    local kind stage cur next nxt
    for ((i = 0; i < m; i++)); do
        tokenize "${TXT[i]}"
        n=${#TOK_VAL[@]}
        [ "$n" -gt 0 ] || continue

        # A shell invoker's quoted arguments are shell, not data.
        for ((j = 0; j < n; j++)); do
            if [[ ${TOK_VAL[j]##*/} =~ ^(sh|bash|zsh|ksh|dash|ash|eval)$ ]]; then
                for ((next = 0; next < n; next++)); do
                    if [ "${TOK_Q[next]}" = 1 ]; then REENTER+=("${TOK_VAL[next]}"); fi
                done
                break
            fi
        done

        kind=""
        if lock_op; then
            kind="direct"
        elif wrapper_op; then
            kind="wrapper"
        fi
        [ -n "$kind" ] || continue
        stage=${TXT[i]//"$BACKSLASH"$'\n'/ }
        stage=$(sed -E -e 's/[[:space:]]+/ /g' -e 's/^ //' -e 's/ $//' <<<"$stage")

        # Follow the pipe: each successor is the next node that starts after the
        # current one ends and shares its enclosing node.
        cur=$i
        while :; do
            nxt=-1
            for ((next = cur + 1; next < m; next++)); do
                if [ "${S[next]}" -ge "${E[cur]}" ]; then
                    nxt=$next
                    break
                fi
            done
            [ "$nxt" -ge 0 ] || break
            [ "${CONT[nxt]}" -eq "${CONT[i]}" ] || break
            gap_is_pipe "${snip:E[cur]:S[nxt]-E[cur]}" || break
            tokenize "${TXT[nxt]}"
            if early_reader; then
                if [ "$kind" = "direct" ]; then
                    block "TERRAFORM STATE LOCK: '$LOCK_PROG $LOCK_SUB' piped into an early-closing reader ($READER) can orphan the remote state lock.

$LOCK_PROG holds the backend lock for its whole run (-lock=true is the
default). When the reader exits early, $LOCK_PROG is killed by SIGPIPE mid-run
and leaves the lock behind; the next plan, and CI applies, then fail with
\"Error acquiring the state lock\" until the lock is force-unlocked by hand.

Write the complete output to a file, run from the same directory:

  mkdir -p tmp && $stage > tmp/tf-${LOCK_SUB// /-}.txt 2>&1

then open tmp/tf-${LOCK_SUB// /-}.txt with the Read tool (head or grep on the
finished file kills nothing).

If a lock is already orphaned: confirm nothing holds it with
'pgrep -x $LOCK_PROG' (not pgrep -f), then run
'$LOCK_PROG force-unlock -force <LOCK_ID>' with the ID from the error, and only
for a lock whose Who is your own user@host. See terraform-plugin's
infrastructure-terraform skill."
                fi
                if [ -z "$NUDGE_MSG" ]; then
                    NUDGE_MSG="TERRAFORM STATE LOCK (nudge): '$stage' is piped into an early-closing reader ($READER). If that $WRAP_PROG recipe runs tofu/terraform plan, apply, refresh or import, the reader's early exit kills it with SIGPIPE mid-run and can orphan the remote state lock, which then blocks every later plan and CI apply until a manual force-unlock. This hook cannot see the recipe body, so the command runs. Safer: \`mkdir -p tmp && $stage > tmp/tf-output.txt 2>&1\`, then open tmp/tf-output.txt with the Read tool."
                fi
                break
            fi
            cur=$nxt
        done
    done
}

QUEUE=("$COMMAND")
MAX_DEPTH=3
depth=0
while [ "${#QUEUE[@]}" -gt 0 ] && [ "$depth" -le "$MAX_DEPTH" ]; do
    REENTER=()
    for snippet in "${QUEUE[@]}"; do
        scan_snippet "$snippet"
    done
    # `"${arr[@]}"` on an empty array is fatal under `set -u` on bash 3.2.
    if [ "${#REENTER[@]}" -gt 0 ]; then
        QUEUE=("${REENTER[@]}")
    else
        QUEUE=()
    fi
    depth=$((depth + 1))
done

if [ -n "$NUDGE_MSG" ]; then
    jq -nc --arg m "$NUDGE_MSG" '{hookSpecificOutput: {hookEventName: "PreToolUse", additionalContext: $m}}'
fi
exit 0
