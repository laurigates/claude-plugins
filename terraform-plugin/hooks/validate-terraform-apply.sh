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
# --search` query. None of those execute anything. So the command is projected
# before matching: heredoc bodies dropped, trailing `#` comments dropped, quoted
# spans collapsed to a placeholder, then split into statements at unquoted shell
# separators. A statement counts only when the program it INVOKES resolves to
# `terraform`.
#
# Masking a span is correct for text and wrong for code, so two spans inside
# quotes are still parsed as shell — the shell runs them, and the old
# whole-string matcher caught them: a `$(…)`/backtick substitution, and the
# script argument of `bash -c` / `eval`. An operand the hook cannot resolve
# (`$VAR`, a substitution) is never accepted as a reviewed plan file.
#
# ── Why not ast-grep ─────────────────────────────────────────────────────────
#
# `hooks-plugin/hooks/bash-antipatterns.sh` classifies its read/write detectors
# structurally with `ast-grep --lang bash` (#2008), which is a better parse than
# anything below. It is deliberately not used here, for the reason that file
# states about its own split: ast-grep is an opt-in dev tool that is NOT assumed
# present, so a structural rule FAILS OPEN when it is missing. That is the right
# trade for a style nudge and the wrong one for a safety gate — a terraform apply
# slipping through unguarded on a box without ast-grep is exactly the outcome
# this hook exists to prevent. The projection below is pure bash/awk and fires
# everywhere.
#
# ── Why this stays a hard block (.claude/rules/hook-block-vs-nudge.md) ───────
#
# An unreviewed apply is irreversible mutation of shared infrastructure, and the
# block does not exempt the dangerous variant — `-auto-approve` is refused
# harder, in every form, including alongside a plan file. That is the opposite
# of the find/grep/ls demotions, so the exit 2 is earned.

set -euo pipefail

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty')

if [ -z "$COMMAND" ]; then exit 0; fi

block() {
    echo "$1" >&2
    exit 2
}

# Project the command into executable statements, one per line.
#
# Per line: a heredoc opener (never a `<<<` here-string) arms body suppression
# until its terminator; a trailing unquoted `#` ends the line; everything else is
# split at unquoted `; & | ( ) ` { } < >`.
#
# A quoted span collapses to the placeholder token `__Q__`, which keeps the
# ARGUMENT (so `terraform apply "tfplan"` still has an operand) while dropping
# its CONTENT (so a `--body` quoting the phrase carries no command). Two spans
# are not data and are parsed as shell instead:
#
#   - `$(…)` and backticks inside double quotes — the shell runs them
#   - the argument of a shell invoker (`bash -c "…"`, `eval '…'`) — it is a
#     script, and the old whole-string matcher blocked it
#
# A double-quoted span holding a `$` expansion becomes `__Q$V__` so the caller
# can see it is unresolvable.
statements_of() {
    printf '%s\n' "$1" | awk -v SQ="'" '
    function flush() { if (buf ~ /[^[:space:]]/) print buf; buf = "" }
    function cmdword(s,   arr, m, k, t) {
        m = split(s, arr, /[[:space:]]+/)
        for (k = 1; k <= m; k++) {
            t = arr[k]
            if (t == "") continue
            if (t ~ /^[A-Za-z_][A-Za-z_0-9]*=/) continue
            if (t ~ /^(sudo|doas|env|command|nohup|time|exec)$/) continue
            sub(/^.*\//, "", t)
            return t
        }
        return ""
    }
    function is_shell(t) { return (t ~ /^(sh|bash|zsh|ksh|dash|ash|eval)$/) }
    BEGIN { ih = 0; buf = "" }
    {
        line = $0
        if (ih == 1) {
            t = line; gsub(/^[[:space:]]+/, "", t); gsub(/[[:space:]]+$/, "", t)
            if (t == delim) ih = 0
            next
        }
        if (match(line, /<<-?[[:space:]]*[^[:space:]]*[A-Za-z_][A-Za-z_0-9]*/)) {
            s = substr(line, RSTART)
            if (s !~ /^<<</) {
                gsub(/<<-?[[:space:]]*/, "", s)
                gsub(/^[^A-Za-z_]+/, "", s)
                gsub(/[^A-Za-z_0-9].*/, "", s)
                if (s != "") { delim = s; ih = 1 }
            }
        }
        n = length(line); in_s = 0; in_d = 0; dvar = 0; sp = 0
        for (i = 1; i <= n; i++) {
            c = substr(line, i, 1)
            if (in_s == 1) {
                if (c == SQ) { in_s = 0; buf = buf "__Q__" }
                continue
            }
            if (in_d == 1) {
                if (c == "\\") { i++; continue }
                if (c == "$" && substr(line, i + 1, 1) == "(") {
                    flush(); sp++; sv[sp] = 1; cl[sp] = ")"; in_d = 0; i++
                    continue
                }
                if (c == "`") { flush(); sp++; sv[sp] = 1; cl[sp] = "`"; in_d = 0; continue }
                if (c == "$") { dvar = 1; continue }
                if (c == "\"") { in_d = 0; buf = buf (dvar ? "__Q$V__" : "__Q__"); dvar = 0 }
                continue
            }
            if (sp > 0 && c == cl[sp]) { flush(); in_d = sv[sp]; sp--; continue }
            if (c == "\\") { i++; buf = buf substr(line, i, 1); continue }
            if (c == SQ || c == "\"") {
                if (is_shell(cmdword(buf))) {
                    flush(); sp++; sv[sp] = 0; cl[sp] = c
                    continue
                }
                if (c == SQ) { in_s = 1 } else { in_d = 1; dvar = 0 }
                continue
            }
            if (c == "#") {
                p = (i == 1) ? " " : substr(line, i - 1, 1)
                if (p ~ /[[:space:]]/ || p == ";" || p == "|" || p == "&" || p == "(") break
                buf = buf c
                continue
            }
            if (index(";&|()`{}<>", c) > 0) { flush(); continue }
            buf = buf c
        }
        flush()
    }
    END { flush() }
'
}

STATEMENTS=$(statements_of "$COMMAND")

while IFS= read -r stmt; do
    [ -n "$stmt" ] || continue

    read -r -a toks <<<"$stmt" || true
    n=${#toks[@]}
    [ "$n" -gt 0 ] || continue

    # Walk to the invoked program: leading VAR=value assignments and a small
    # wrapper set are transparent. After a wrapper, its own flags are skipped
    # too (a bare short flag such as `sudo -u ci` also consumes its value).
    i=0
    seen_wrapper=0
    while [ "$i" -lt "$n" ]; do
        t=${toks[$i]}
        case "$t" in
            sudo | doas | env | command | nohup | time | exec)
                seen_wrapper=1
                i=$((i + 1))
                ;;
            -*)
                [ "$seen_wrapper" = 1 ] || break
                i=$((i + 1))
                case "$t" in
                    -[A-Za-z]) i=$((i + 1)) ;;
                esac
                ;;
            *)
                if [[ $t =~ ^[A-Za-z_][A-Za-z_0-9]*= ]]; then
                    i=$((i + 1))
                else
                    break
                fi
                ;;
        esac
    done

    [ "$i" -lt "$n" ] || continue
    prog=${toks[$i]}
    [ "${prog##*/}" = "terraform" ] || continue

    # Skip terraform's own global options (-chdir=…, -help, …) to reach the
    # subcommand.
    j=$((i + 1))
    while [ "$j" -lt "$n" ]; do
        case "${toks[$j]}" in
            -*) j=$((j + 1)) ;;
            *) break ;;
        esac
    done
    [ "$j" -lt "$n" ] || continue
    [ "${toks[$j]}" = "apply" ] || continue

    # Classify the apply's arguments. A saved plan file is a positional operand
    # that carries no `=` (so `-var foo=bar` is not one) and is not the value of
    # a preceding bare flag (so `-target aws_x.y` is not one either).
    #
    # An operand the hook cannot resolve — `$VAR`, a command substitution, a
    # quoted span holding an expansion — is NOT accepted as a plan file. It
    # could expand to anything, `-auto-approve` included, so the apply is
    # treated as unreviewed and blocked. Name the plan file literally.
    auto_approve=0
    plan_file=0
    prev="apply"
    k=$((j + 1))
    while [ "$k" -lt "$n" ]; do
        a=${toks[$k]}
        case "$a" in
            -auto-approve | -auto-approve=* | --auto-approve | --auto-approve=*)
                auto_approve=1
                ;;
            -*) ;;
            *'$'* | *'`'*) ;;
            *)
                if [ "${a#*=}" = "$a" ]; then
                    case "$prev" in
                        -*=*) plan_file=1 ;;
                        -*) ;;
                        *) plan_file=1 ;;
                    esac
                fi
                ;;
        esac
        prev=$a
        k=$((k + 1))
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
        continue
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
done <<<"$STATEMENTS"

exit 0
