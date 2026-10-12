#!/usr/bin/env bash
# PreToolUse hook for Bash tool - injects --dry-run=client into kubectl destructive commands
#
# Rewrites a lone `kubectl apply|delete|patch …` that carries no --dry-run flag
# so it carries --dry-run=client, and allows the rewritten (read-only) command.
# This creates a natural checkpoint: the model sees the dry-run output and must
# explicitly re-run with --dry-run=none to apply for real.
#
# Bypass: add --dry-run=none (or any --dry-run…) to the kubectl invocation.
# The validate-kubectl-context.sh hook runs in parallel and enforces --context presence.
#
# Decided on the parse, not the raw string (#2734). The pre-fix hook matched
# `kubectl apply` anywhere in the text and appended the flag to the END of the
# whole command with an allow, so `kubectl apply -f x && echo done` became
# `… && echo done --dry-run=client`: the apply ran for real, auto-approved.
# Now `ast-grep --lang bash` locates the command node, and the hook rewrites
# only when ALL of these hold:
#   - `bash -n` accepts the text (tree-sitter papers over an unterminated
#     quote with a MISSING node), the parse has no ERROR node and exactly one
#     `command` node, and nothing
#     outside that node but whitespace and comments (so no list, pipeline,
#     trailing redirection, heredoc, subshell, loop or second statement);
#   - the parse has no substitution, expansion, file redirect or herestring
#     ANYWHERE, including inside the node: tree-sitter puts a LEADING redirect
#     (`>f kubectl apply …`) inside the command node, and a redirect-only
#     `$(>f)` or `<(>f)` has no inner command node to count (#2887);
#   - no environment assignment but KUBECONFIG=… precedes kubectl (PATH= or
#     LD_PRELOAD= can run another binary or library);
#   - once every backslash-newline is joined (bash deletes it before splitting
#     words, so `--ra\<NL>w` reaches kubectl as --raw), the node's text has
#     none of $ ` { < > * ? [ (an expansion, substitution, redirection, brace
#     expansion or glob can become a flag, a `--` or a file write that the
#     parse does not show);
#   - its program is literally `kubectl`, optionally behind `timeout DURATION`
#     or `env KUBECONFIG=…` (not sudo, not a path, no other env assignment);
#     between kubectl and the verb sit only bare words from a bounded list of
#     global flags (--context, --kubeconfig, -n/--namespace, --cluster,
#     --user, --as, --as-group, --request-timeout, -s/--server, --token, -v,
#     as --flag=value or --flag value), and the verb is literally apply,
#     delete or patch (#2888);
#   - under apply, no word is view-last-applied or edit-last-applied: those
#     subcommands register no --dry-run and would fail on the rewrite (#2888);
#   - once lines are joined, quotes and backslashes are dropped and `_` reads
#     as `-` (kubectl's flag normalizer), no word contains --dry-run (so the
#     --dry-run=none bypass, --dry_run=none, --dry-r''un=none and
#     --dry-r\<NL>un=none all count; a comment after the node does not), no
#     word is `--` (it would end option parsing), and no word is --raw
#     (kubectl sends the raw request before it reads --dry-run) or a
#     --profile / --cache-dir flag (a dry run still writes those files);
#   - the node's last word is not a flag without `=`: it may take a value,
#     and would swallow the injected trailing --dry-run=client as that value.
# The flag is inserted at the END of the node (inside its byte range, so before
# any trailing comment) and again right after the verb: kubectl takes the last
# --dry-run, and the after-verb copy still holds if the trailing one were ever
# read as a positional argument. In every other case, and whenever ast-grep is
# missing, fails, or answers something unexpected, the hook emits nothing and
# exits 0: no allow, no rewrite — the command goes through the user's normal
# permission flow as written. Deferring beats guessing.
#
# Self-contained on purpose: plugins ship independently, so nothing here is
# sourced from hooks-plugin/hooks/lib.

set -euo pipefail

INPUT=$(cat)
COMMAND=$(printf '%s' "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null || true)

case $COMMAND in
    *kubectl*) ;;
    *) exit 0 ;;
esac

# `sg` is ast-grep's short name but collides with shadow-utils' sg(1) (#2451).
ASTGREP=""
if command -v ast-grep >/dev/null 2>&1; then
    ASTGREP="ast-grep"
elif command -v sg >/dev/null 2>&1 && sg --version 2>/dev/null | grep -qi '^ast-grep'; then
    ASTGREP="sg"
fi
[ -n "$ASTGREP" ] || exit 0

# tree-sitter recovers from an unterminated quote, `$(`, `${` or backtick with a
# zero-width MISSING node that ast-grep cannot report, so let bash's own parser
# confirm the text is complete. -n reads without executing anything.
"$BASH" -n -c "$COMMAND" >/dev/null 2>&1 || exit 0

# ast-grep reports BYTE offsets; make every length and slice below byte-indexed.
LC_ALL=C
export LC_ALL

AST_RULES='id: cmd
language: bash
rule: { kind: command }
---
id: err
language: bash
rule: { kind: ERROR }
---
id: cmt
language: bash
rule: { kind: comment }
---
id: name
language: bash
rule: { kind: command_name }
---
id: csub
language: bash
rule: { kind: command_substitution }
---
id: psub
language: bash
rule: { kind: process_substitution }
---
id: exp
language: bash
rule: { kind: expansion }
---
id: sexp
language: bash
rule: { kind: simple_expansion }
---
id: fredir
language: bash
rule: { kind: file_redirect }
---
id: hstr
language: bash
rule: { kind: herestring_redirect }
---
id: asgn
language: bash
rule: { kind: variable_assignment }
---
id: word
language: bash
rule:
  any: [ { kind: word }, { kind: number } ]
  inside: { kind: command, stopBy: neighbor }'

PARSED=$(printf '%s' "$COMMAND" \
    | "$ASTGREP" scan --inline-rules "$AST_RULES" --stdin --json=compact 2>/dev/null) || exit 0

# One node per line, sorted by start: "<start> <end> <rule-id>". Node text is
# sliced from COMMAND by offset, never read from the answer.
NODES=$(jq -r '.[] | "\(.range.byteOffset.start) \(.range.byteOffset.end) \(.ruleId)"' \
    <<<"$PARSED" 2>/dev/null | sort -n -k1,1) || exit 0
[ -n "$NODES" ] || exit 0

CMD_COUNT=0
CMD_START=-1
CMD_END=-1
NAME_COUNT=0
# The command name and the node's own bare words, in order, as "<start> <end>".
TOKENS=()
COVERED=()
LINE_RE='^(0|[1-9][0-9]*) (0|[1-9][0-9]*) (cmd|err|cmt|name|word|csub|psub|exp|sexp|fredir|hstr|asgn)$'
while IFS= read -r line; do
    # Anything but a well-formed node line: distrust the whole answer.
    [[ $line =~ $LINE_RE ]] || exit 0
    start=${BASH_REMATCH[1]}
    end=${BASH_REMATCH[2]}
    if [ "$end" -gt "${#COMMAND}" ] || [ "$start" -gt "$end" ]; then exit 0; fi
    case ${BASH_REMATCH[3]} in
        # A substitution, expansion, file redirect or herestring anywhere (a
        # leading redirect sits INSIDE the command node): defer (#2887).
        err | csub | psub | exp | sexp | fredir | hstr) exit 0 ;;
        cmd)
            CMD_COUNT=$((CMD_COUNT + 1))
            CMD_START=$start
            CMD_END=$end
            COVERED+=("$start $end")
            ;;
        cmt) COVERED+=("$start $end") ;;
        # An environment prefix other than KUBECONFIG can swap the binary or
        # load a library (PATH=…, LD_PRELOAD=…): defer.
        asgn)
            case ${COMMAND:start:end-start} in
                KUBECONFIG=*) ;;
                *) exit 0 ;;
            esac
            ;;
        name)
            NAME_COUNT=$((NAME_COUNT + 1))
            TOKENS=("$start $end")
            ;;
        word)
            if [ "${#TOKENS[@]}" -gt 0 ]; then TOKENS+=("$start $end"); fi
            ;;
    esac
done <<<"$NODES"

# Exactly one non-empty command node with one name.
if [ "$CMD_COUNT" -ne 1 ] || [ "$NAME_COUNT" -ne 1 ] || [ "$CMD_START" -ge "$CMD_END" ]; then exit 0; fi

# Walk the tokens from the name to the verb (#2888). Each step reads the next
# token, which must be a bare word separated from the previous one by blanks
# only: a quoted or concatenated argument in between leaves a non-blank gap.
TOK_I=0
TOK=""
TOK_END=-1
next_token() {
    local s e
    [ "$TOK_I" -lt "${#TOKENS[@]}" ] || return 1
    read -r s e <<<"${TOKENS[TOK_I]}"
    if [ "$TOK_END" -ge 0 ]; then
        [[ ${COMMAND:TOK_END:s-TOK_END} =~ ^[[:blank:]]+$ ]] || return 1
    fi
    TOK=${COMMAND:s:e-s}
    TOK_END=$e
    TOK_I=$((TOK_I + 1))
}

# Transparent prefixes that run the same kubectl from PATH: `timeout DURATION`
# (no options) and `env` followed only by KUBECONFIG=… words. sudo, a path to
# kubectl (any binary can be named kubectl), an env option and any other env
# assignment (PATH=, LD_PRELOAD=) are not targets: no output.
next_token || exit 0
for _ in 1 2 3; do
    case $TOK in
        timeout)
            next_token || exit 0
            [[ $TOK =~ ^[0-9]+(\.[0-9]+)?[smhd]?$ ]] || exit 0
            next_token || exit 0
            ;;
        env)
            next_token || exit 0
            while [[ $TOK == KUBECONFIG=* ]]; do next_token || exit 0; done
            ;;
        *) break ;;
    esac
done
[ "$TOK" = "kubectl" ] || exit 0

# kubectl global flags between the name and the verb (#2888):
# validate-kubectl-context.sh asks for `kubectl --context=X <command>`. A
# bounded list, as `--flag=value` or `--flag value`; any other word before the
# verb means no output. A separate value never starts with `-`.
VERB=""
VERB_END=-1
while next_token; do
    case $TOK in
        --context=* | --kubeconfig=* | --namespace=* | -n=* | --cluster=* | --user=* | --as=* | \
            --as-group=* | --request-timeout=* | --server=* | -s=* | --token=* | -v=* | --v=*) ;;
        --context | --kubeconfig | --namespace | -n | --cluster | --user | --as | --as-group | \
            --request-timeout | --server | -s | --token | -v | --v)
            next_token || exit 0
            case $TOK in -*) exit 0 ;; esac
            ;;
        apply | delete | patch)
            VERB=$TOK
            VERB_END=$TOK_END
            break
            ;;
        *) exit 0 ;;
    esac
done
if [ "$VERB_END" -lt 0 ] || [ "$VERB_END" -gt "$CMD_END" ]; then exit 0; fi

# Nothing but whitespace outside the command node and comments: no operator,
# redirection, heredoc body or second statement anywhere.
REST=""
pos=0
while IFS=' ' read -r start end; do
    if [ "$start" -gt "$pos" ]; then REST+=${COMMAND:pos:start-pos}; fi
    if [ "$end" -gt "$pos" ]; then pos=$end; fi
done < <(printf '%s\n' "${COVERED[@]}" | sort -n -k1,1)
REST+=${COMMAND:pos}
[[ $REST =~ ^[[:space:]]*$ ]] || exit 0

# Bash deletes a backslash-newline before it splits words, so `--ra\<NL>w`
# reaches kubectl as --raw. Join every line continuation before the text and
# word guards, or they see two harmless words (#2887 review). Inside quotes
# joining never splits a word, and inside single quotes kubectl keeps the pair,
# so a guard can only fire more often than it must: still safe.
NODE_TEXT=${COMMAND:CMD_START:CMD_END-CMD_START}
NODE_TEXT=${NODE_TEXT//$'\\\n'/}

# Any expansion, substitution, redirection, brace expansion or glob in the node
# can become a flag, a `--` or a file write the parse does not show ($'--',
# {-,}-, ${X:-`cmd`}, *.yaml): defer to the user (#2887).
case $NODE_TEXT in
    *[\$\`\{\<\>*?[]*) exit 0 ;;
esac

# Word by word, once quotes and backslashes go and `_` reads as `-` (kubectl's
# flag normalizer maps --dry_run to --dry-run):
#   - any --dry-run (the --dry-run=none bypass, --dry_run=none, --dry-r''un):
#     the node already says what it wants, so leave it alone;
#   - `--` ends option parsing, so a flag after it is a positional name;
#   - --raw sends the request before kubectl reads --dry-run (a real DELETE);
#   - --profile / --profile-output / --cache-dir write files even in a dry run.
read -r -d '' -a NODE_WORDS <<<"$NODE_TEXT" || true
for word in "${NODE_WORDS[@]}"; do
    stripped=${word//[\'\"\\]/}
    flag=${stripped//_/-}
    case $flag in
        *--dry-run*) exit 0 ;;
        -- | --raw | --raw=* | --profile* | --cache-dir*) exit 0 ;;
    esac
    # view-last-applied and edit-last-applied register no --dry-run, so the
    # rewrite would fail with an unknown flag (#2888). cobra finds a
    # subcommand past flags, so any such word under apply defers;
    # set-last-applied accepts --dry-run and is rewritten.
    if [ "$VERB" = "apply" ]; then
        case $flag in view-last-applied | edit-last-applied) exit 0 ;; esac
    fi
done

# A trailing flag without `=` may take a value, and would swallow the injected
# trailing --dry-run=client as that value (--cache-dir, --as, -o): defer.
if [ "${#NODE_WORDS[@]}" -gt 0 ]; then
    last=${NODE_WORDS[${#NODE_WORDS[@]}-1]}
    last=${last//[\'\"\\]/}
    case $last in
        -*=*) ;;
        -*) exit 0 ;;
    esac
fi

# The flag goes at the END of the node, where kubectl's last-value-wins makes
# it beat any --dry-run override the word check could still miss, and right
# after the verb, so it still applies if the trailing copy were ever read as a
# positional argument.
UPDATED="${COMMAND:0:VERB_END} --dry-run=client${COMMAND:VERB_END:CMD_END-VERB_END}"
if [ "$VERB_END" -lt "$CMD_END" ]; then UPDATED+=" --dry-run=client"; fi
UPDATED+=${COMMAND:CMD_END}

# updatedInput replaces the tool input, so carry the call's other fields over.
printf '%s' "$INPUT" | jq --arg cmd "$UPDATED" '{
    "hookSpecificOutput": {
        "hookEventName": "PreToolUse",
        "permissionDecision": "allow",
        "permissionDecisionReason": "kubernetes-plugin added --dry-run=client to this kubectl call; re-run it with --dry-run=none to apply for real.",
        "updatedInput": ((.tool_input // {}) + {"command": $cmd})
    }
}'
exit 0
