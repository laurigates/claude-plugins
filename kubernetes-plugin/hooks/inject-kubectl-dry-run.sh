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
#     redirection, heredoc, substitution, subshell, loop or second statement);
#   - its command_name is literally `kubectl` and the very next word is
#     literally apply, delete or patch;
#   - `--dry-run` appears nowhere in that node's own text (a comment after the
#     node does not count).
# The flag is inserted right after the verb word — inside the node's byte
# range, so before any trailing comment. In every other case, and whenever
# ast-grep is missing, fails, or answers something unexpected, the hook emits
# nothing and exits 0: no allow, no rewrite — the command goes through the
# user's normal permission flow as written. Deferring beats guessing.
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
LINE_RE='^(0|[1-9][0-9]*) (0|[1-9][0-9]*) (cmd|err|cmt|name|word)$'
while IFS= read -r line; do
    # Anything but a well-formed node line: distrust the whole answer.
    [[ $line =~ $LINE_RE ]] || exit 0
    start=${BASH_REMATCH[1]}
    end=${BASH_REMATCH[2]}
    if [ "$end" -gt "${#COMMAND}" ] || [ "$start" -gt "$end" ]; then exit 0; fi
    case ${BASH_REMATCH[3]} in
        err) exit 0 ;;
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

# The node's own --dry-run (including the --dry-run=none bypass): leave it alone.
case ${COMMAND:CMD_START:CMD_END-CMD_START} in
    *--dry-run*) exit 0 ;;
esac

UPDATED="${COMMAND:0:VERB_END} --dry-run=client${COMMAND:VERB_END}"

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
