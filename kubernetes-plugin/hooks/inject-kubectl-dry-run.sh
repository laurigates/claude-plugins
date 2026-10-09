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
#   - the node's text has none of $ ` { < > * ? [ (an expansion, substitution,
#     redirection, brace expansion or glob can become a flag, a `--` or a file
#     write that the parse does not show);
#   - its command_name is literally `kubectl` and the very next word is
#     literally apply, delete or patch;
#   - once quotes and backslashes are dropped and `_` reads as `-` (kubectl's
#     flag normalizer), no word contains --dry-run (so the --dry-run=none
#     bypass, --dry_run=none and --dry-r''un=none all count; a comment after
#     the node does not), no word is `--` (it would end option parsing), and
#     no word is --raw (kubectl sends the raw request before it reads
#     --dry-run) or a --profile / --cache-dir flag (a dry run still writes
#     those files);
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
id: word
language: bash
rule:
  kind: word
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
NAME_END=-1
NAME_COUNT=0
VERB_END=-1
COVERED=()
LINE_RE='^(0|[1-9][0-9]*) (0|[1-9][0-9]*) (cmd|err|cmt|name|word|csub|psub|exp|sexp|fredir|hstr)$'
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
        name)
            NAME_COUNT=$((NAME_COUNT + 1))
            if [ "${COMMAND:start:end-start}" = "kubectl" ]; then NAME_END=$end; fi
            ;;
        word)
            # The verb: the first word after the name, separated only by blanks.
            if [ "$NAME_END" -ge 0 ] && [ "$VERB_END" -lt 0 ] && [ "$start" -gt "$NAME_END" ]; then
                VERB_END=-2
                gap=${COMMAND:NAME_END:start-NAME_END}
                case ${COMMAND:start:end-start} in
                    apply | delete | patch)
                        if [[ $gap =~ ^[[:blank:]]+$ ]]; then VERB_END=$end; fi
                        ;;
                esac
            fi
            ;;
    esac
done <<<"$NODES"

# Exactly one non-empty command node whose program is kubectl and verb mutates.
if [ "$CMD_COUNT" -ne 1 ] || [ "$NAME_COUNT" -ne 1 ] || [ "$CMD_START" -ge "$CMD_END" ]; then exit 0; fi
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

NODE_TEXT=${COMMAND:CMD_START:CMD_END-CMD_START}

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
