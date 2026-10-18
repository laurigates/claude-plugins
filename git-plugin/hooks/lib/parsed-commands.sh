#!/usr/bin/env bash
# parsed-commands.sh — decide a Bash hook's trigger on parsed command nodes,
# not on regex over the raw command string (issue #2737).
#
# Usage (sourced by a git-plugin PreToolUse hook):
#   # shellcheck source=git-plugin/hooks/lib/parsed-commands.sh
#   . "$(dirname "$0")/lib/parsed-commands.sh" 2>/dev/null || PC_LIB_MISSING=1
#   pc_scan "$COMMAND"   # 0 = parsed, 1 = no parser / parse failed
#   pc_find_git 'push'   # PC_HIT_* arrays hold every `git … push` invocation
#
# ── Why ──────────────────────────────────────────────────────────────────────
#
# `grep -E '(^|\s)git\s+push\b'` over the whole command fires on every mention:
# a `gh issue comment --body "run git push later"`, a `git commit -m "…git
# push…"`, a heredoc body describing the workflow. None of those executes a
# push. A parse settles it as a class: tree-sitter-bash (via `ast-grep --lang
# bash`, the classifier bash-antipatterns.sh adopted in #2008 and
# terraform-plugin's validate-terraform-apply.sh in #2506) yields one `command`
# node per invocation the shell would run — including ones inside `$(…)`,
# backticks, loops, conditionals and function bodies — and never one for a
# heredoc body or a quoted argument's contents.
#
# Each node is then split into the argument vector the shell would build
# (quotes REMOVED, as the shell removes them), so a quoted `--body "run git
# push"` is one argument whose value is the whole sentence, and carries no
# `git` argument to find. Any argument delivered as `git` (or `…/git`) is the
# program of the node or of the command its wrapper execs — `sudo`, `env X=1`,
# `timeout 5`, `xargs`, `FOO=1` — so no wrapper allowlist is needed. A shell
# invoker's quoted script argument (`bash -c 'cd x && git push'`) is text to
# tree-sitter but shell to the shell, so it is re-entered and parsed again.
#
# ── Why vendored here, not sourced from hooks-plugin ─────────────────────────
#
# Plugins install independently; a git-plugin hook cannot assume hooks-plugin
# (or terraform-plugin) is installed. The tokenizer below is a copy of the one
# in terraform-plugin/hooks/validate-terraform-apply.sh (#2506), kept
# behaviourally honest by each plugin's own tests.
#
# ── No parser ────────────────────────────────────────────────────────────────
#
# These hooks are nudges/checks, and every one of them fired everywhere before
# this change. pc_scan returns 1 when ast-grep is absent, errors, or answers in
# a shape that is not a JSON array; the caller then keeps its original raw-text
# regex, so a box without ast-grep behaves exactly as before — false positives
# included — rather than going silent on the true positives.
# CLAUDE_HOOKS_PARSED_TRIGGER_NO_ASTGREP=1 forces that path (tests).
#
# Shell options: consumers set their own options before sourcing; the line
# below exists because lint-shell-scripts.sh requires `set` flags on every file
# under a hooks/ directory. It deliberately omits -e so that sourcing it from
# check-branch-sync-on-push.sh (`set -uo pipefail`) does not turn -e on there.
set -uo pipefail

PC_ASTGREP=""
if [ "${CLAUDE_HOOKS_PARSED_TRIGGER_NO_ASTGREP:-}" != "1" ]; then
    # `sg` collides with shadow-utils' sg(1) on Debian/Ubuntu; adopt it only
    # when it really is ast-grep (#2451).
    if command -v ast-grep >/dev/null 2>&1; then
        PC_ASTGREP="ast-grep"
    elif command -v sg >/dev/null 2>&1 && sg --version 2>/dev/null | grep -qi '^ast-grep'; then
        PC_ASTGREP="sg"
    fi
fi

PC_AST_RULE='id: shell-command
language: bash
rule:
  kind: command
'
# Node texts may contain newlines (a quoted multi-line --body), so nodes are
# separated by SOH, never by newlines.
PC_SEP=$'\001'
PC_BACKSLASH=$'\\'
PC_SHELL_INVOKERS='sh|bash|zsh|ksh|dash|ash|eval'
PC_MAX_DEPTH=3

# Every command node of every executed snippet, SOH-terminated, in PC_NODES.
PC_NODES=()

# Print the SOH-terminated command nodes of one snippet. Returns 1 when the
# parser errors or answers with anything but a JSON array.
pc_commands_of() {
    local out
    out=$(printf '%s' "$1" | "$PC_ASTGREP" scan --inline-rules "$PC_AST_RULE" --stdin --json=compact 2>/dev/null) || return 1
    printf '%s' "$out" | jq -e 'type == "array"' >/dev/null 2>&1 || return 1
    printf '%s' "$out" | jq -j --arg sep "$PC_SEP" '.[] | .text, $sep' 2>/dev/null || return 1
}

# Split one command node into the argument vector the shell would build.
# PC_TOK_VAL = delivered value; PC_TOK_Q = 1 when any part was quoted.
PC_TOK_VAL=()
PC_TOK_Q=()
pc_tokenize() {
    local s=$1
    local n=${#s}
    local c depth
    local i=0
    local cur="" started=0 q=0
    PC_TOK_VAL=()
    PC_TOK_Q=()
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
                if [ "$c" = "$PC_BACKSLASH" ]; then
                    i=$((i + 1))
                    cur+=${s:i:1}
                    i=$((i + 1))
                    continue
                fi
                cur+=$c
                i=$((i + 1))
            done
            i=$((i + 1))
            continue
        fi
        if [ "$c" = "$PC_BACKSLASH" ]; then
            i=$((i + 1))
            cur+=${s:i:1}
            i=$((i + 1))
            started=1
            continue
        fi
        if [ "$c" = '$' ] && [ "${s:i+1:1}" = "(" ]; then
            # Keep a balanced $(…) inside one token: its contents are a
            # separate command node of their own, never further arguments here.
            started=1
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
            continue
        fi
        if [ "$c" = '`' ]; then
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
                    PC_TOK_VAL+=("$cur")
                    PC_TOK_Q+=("$q")
                    cur=""
                    started=0
                    q=0
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
        PC_TOK_VAL+=("$cur")
        PC_TOK_Q+=("$q")
    fi
    return 0
}

# Parse $1 into PC_NODES, re-entering shell invokers' quoted script arguments.
# Returns 1 (and leaves PC_NODES empty) when no parser is usable.
pc_scan() {
    local depth=0 snippet cmd nodes i n base invoker
    local queue next
    PC_NODES=()
    [ -n "$PC_ASTGREP" ] || return 1
    queue=("$1")
    while [ "${#queue[@]}" -gt 0 ] && [ "$depth" -le "$PC_MAX_DEPTH" ]; do
        next=()
        for snippet in "${queue[@]}"; do
            if ! nodes=$(pc_commands_of "$snippet"); then
                PC_NODES=()
                return 1
            fi
            while IFS= read -r -d "$PC_SEP" cmd; do
                [ -n "$cmd" ] || continue
                PC_NODES+=("$cmd")
                pc_tokenize "$cmd"
                n=${#PC_TOK_VAL[@]}
                invoker=0
                for ((i = 0; i < n; i++)); do
                    base=${PC_TOK_VAL[i]##*/}
                    if [[ $base =~ ^($PC_SHELL_INVOKERS)$ ]]; then
                        invoker=1
                        break
                    fi
                done
                if [ "$invoker" = 1 ]; then
                    for ((i = 0; i < n; i++)); do
                        if [ "${PC_TOK_Q[i]}" = 1 ]; then next+=("${PC_TOK_VAL[i]}"); fi
                    done
                fi
            done <<<"$nodes"
        done
        # "${next[@]}" on an empty array is fatal under `set -u` on bash 3.2.
        if [ "${#next[@]}" -gt 0 ]; then
            queue=("${next[@]}")
        else
            queue=()
        fi
        depth=$((depth + 1))
    done
    return 0
}

# Hits from the last pc_find_* call, one entry per matching invocation, in
# parse order. PC_HIT_ARGS[k] holds the arguments after the subcommand, each
# terminated by SOH; PC_HIT_C[k] the last `git -C <dir>` value (or empty).
PC_HIT_SUB=()
PC_HIT_C=()
PC_HIT_ARGS=()

# Collect every `git [global options] <sub> …` invocation whose subcommand
# matches the ERE $1 (anchored). Returns 0 when at least one was found.
pc_find_git() {
    local re=$1 node n i j sub cdir args k
    PC_HIT_SUB=()
    PC_HIT_C=()
    PC_HIT_ARGS=()
    for node in ${PC_NODES[@]+"${PC_NODES[@]}"}; do
        pc_tokenize "$node"
        n=${#PC_TOK_VAL[@]}
        for ((i = 0; i < n; i++)); do
            [ "${PC_TOK_VAL[i]##*/}" = "git" ] || continue
            cdir=""
            j=$((i + 1))
            # git's own global options; the listed ones take a separate value.
            while [ "$j" -lt "$n" ] && [ "${PC_TOK_VAL[j]:0:1}" = "-" ]; do
                case ${PC_TOK_VAL[j]} in
                    -C)
                        cdir=${PC_TOK_VAL[j + 1]:-}
                        j=$((j + 2))
                        ;;
                    -c | --git-dir | --work-tree | --namespace | --super-prefix | --config-env)
                        j=$((j + 2))
                        ;;
                    *) j=$((j + 1)) ;;
                esac
            done
            [ "$j" -lt "$n" ] || continue
            sub=${PC_TOK_VAL[j]}
            [[ $sub =~ ^($re)$ ]] || continue
            args=""
            for ((k = j + 1; k < n; k++)); do args+="${PC_TOK_VAL[k]}$PC_SEP"; done
            PC_HIT_SUB+=("$sub")
            PC_HIT_C+=("$cdir")
            PC_HIT_ARGS+=("$args")
            break
        done
    done
    [ "${#PC_HIT_SUB[@]}" -gt 0 ]
}

# Collect every `gh pr [-R <repo>] create …` invocation. Returns 0 when found.
pc_find_gh_pr_create() {
    local node n i j args k
    PC_HIT_SUB=()
    PC_HIT_C=()
    PC_HIT_ARGS=()
    for node in ${PC_NODES[@]+"${PC_NODES[@]}"}; do
        pc_tokenize "$node"
        n=${#PC_TOK_VAL[@]}
        for ((i = 0; i < n; i++)); do
            [ "${PC_TOK_VAL[i]##*/}" = "gh" ] || continue
            [ "${PC_TOK_VAL[i + 1]:-}" = "pr" ] || continue
            j=$((i + 2))
            # `-R/--repo` is a persistent flag of `gh pr`, legal before `create`.
            while [ "$j" -lt "$n" ]; do
                case ${PC_TOK_VAL[j]} in
                    -R | --repo) j=$((j + 2)) ;;
                    -R?* | --repo=*) j=$((j + 1)) ;;
                    *) break ;;
                esac
            done
            [ "${PC_TOK_VAL[j]:-}" = "create" ] || continue
            args=""
            for ((k = j + 1; k < n; k++)); do args+="${PC_TOK_VAL[k]}$PC_SEP"; done
            PC_HIT_SUB+=("create")
            PC_HIT_C+=("")
            PC_HIT_ARGS+=("$args")
            break
        done
    done
    [ "${#PC_HIT_SUB[@]}" -gt 0 ]
}
