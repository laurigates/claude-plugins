#!/usr/bin/env bash
# check-pr-issue-link-prompt.sh — semantic guard for the git-plugin PreToolUse
# prompt hook on mcp__github__create_pull_request.
#
# THE BEHAVIOUR THIS PINS (issue #3404)
# The prompt let infrastructure, documentation and dependency PRs through and
# blocked every other PR whose body had no `Closes #N`. A feature requested
# directly in a session has no issue, so the only way past was to file an
# issue whose sole purpose was to be closed by the PR — even after the body
# said "No linked issue: …". The prompt now accepts an explicit opt-out line
# (`No linked issue: <reason>`), and its block reason names that line, so a
# blocked agent learns the way through on the first refusal.
#
# THE BEHAVIOUR THIS ALSO PINS (issue #3413)
# A PR that is one part of a larger issue should reference that issue without
# closing it. The prompt blocked `Refs #N` / `Part of #N` bodies and pushed
# agents toward a premature `Closes #N`. It now accepts a non-closing reference
# (`Refs`, `Part of`, `Related to`, with `#N` or `owner/repo#N`) as a valid
# link, and its block reason names that option too.
#
# WHY A DEDICATED SCRIPT
# The artefact is a prompt string inside git-plugin/hooks.json, so neither
# plugin-compliance-check.sh (SKILL.md files) nor the bash hook's suite
# (git-plugin/hooks/test-validate-pr-issue-links.sh) reaches it.
#
# Each rule is a concept with accepted spellings, so a reword passes and a
# revert fails (.claude/rules/regression-testing.md).
#
# Output: KEY=VALUE per .claude/rules/structured-script-output.md.
#   --hooks-json PATH  file to inspect (default: git-plugin/hooks.json)
#   --strict           exit 1 when ISSUE_COUNT > 0
# Exit: 0 clean (or non-strict with findings), 1 strict with findings,
#       2 unknown argument.

set -uo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HOOKS_JSON="$ROOT_DIR/git-plugin/hooks.json"
STRICT=0
MATCHER="mcp__github__create_pull_request"

while [ $# -gt 0 ]; do
    case "$1" in
        --strict) STRICT=1 ;;
        --hooks-json)
            shift
            [ $# -gt 0 ] || { echo "check-pr-issue-link-prompt.sh: --hooks-json needs a value" >&2; exit 2; }
            HOOKS_JSON="$1"
            ;;
        --hooks-json=*) HOOKS_JSON="${1#--hooks-json=}" ;;
        -h|--help) echo "Usage: check-pr-issue-link-prompt.sh [--hooks-json PATH] [--strict]"; exit 0 ;;
        *) echo "check-pr-issue-link-prompt.sh: unknown argument: $1" >&2; exit 2 ;;
    esac
    shift
done

issue_count=0
declare -a issues=()
first_finding=""
add_issue() {
    issue_count=$((issue_count + 1))
    [ -n "$first_finding" ] || first_finding="$1: $2"
    issues+=("  - SEVERITY=ERROR TYPE=$1 MSG=$2")
}

emit() {
    local status="OK"
    [ "$issue_count" -gt 0 ] && status="ERROR"
    echo "=== PR ISSUE-LINK PROMPT CHECK ==="
    echo "HOOKS_JSON=$HOOKS_JSON"
    echo "STATUS=$status"
    if [ "$issue_count" -gt 0 ]; then
        local reason="${first_finding:0:180}"
        [ "$issue_count" -gt 1 ] && reason="$reason (+$((issue_count - 1)) more)"
        echo "REASON=$reason"
    fi
    echo "ISSUE_COUNT=$issue_count"
    if [ "$issue_count" -gt 0 ]; then
        echo "ISSUES:"
        for line in "${issues[@]}"; do echo "$line"; done
    fi
    echo "=== END PR ISSUE-LINK PROMPT CHECK ==="
    if [ "$STRICT" -eq 1 ] && [ "$issue_count" -gt 0 ]; then exit 1; fi
    exit 0
}

if [ ! -f "$HOOKS_JSON" ]; then
    add_issue hooks_json_missing "file not found"
    emit
fi

# shellcheck disable=SC2016  # $m is a jq variable bound by --arg, not a shell one
filter='[.hooks.PreToolUse[]? | select(.matcher == $m) | .hooks[]? | select(.type == "prompt") | .prompt]'
prompts=$(jq -r --arg m "$MATCHER" "$filter | length" "$HOOKS_JSON" 2>/dev/null) || {
    add_issue hooks_json_invalid "jq could not parse the file"
    emit
}
if [ "$prompts" != "1" ]; then
    add_issue prompt_count "expected exactly 1 PreToolUse prompt hook for $MATCHER, found ${prompts:-0}"
    emit
fi

prompt=$(jq -r --arg m "$MATCHER" "${filter}[0]" "$HOOKS_JSON")
# The block reason is the text after the ok:false verdict.
reason_text=$(sed -nE 's/.*"ok"[^a-z]{0,6}false(.*)/\1/p' <<<"$prompt")

# require RULE MSG REGEX [TEXT] -- case-insensitive ERE over the prompt (or TEXT).
require() {
    local text="${4-$prompt}"
    grep -Eiq -- "$3" <<<"$text" || add_issue "$1" "$2"
}

# The opt-out line is recognised: `No linked issue:` followed by a reason.
require optout_phrase "the prompt does not recognise a 'No linked issue: <reason>' opt-out line" \
    'no linked issue:'
# Recognising it lets the PR through: the opt-out sits on the ok:true side.
require optout_passes "the opt-out line is not tied to an {\"ok\": true} verdict" \
    'no linked issue[^{]*\{\\?"ok\\?": true\}'
# A blocked agent is told about the opt-out in the block reason itself.
require reason_names_optout "the ok:false reason does not name the 'No linked issue:' opt-out" \
    'no linked issue:' "$reason_text"

# A non-closing reference to an existing issue is recognised (issue #3413).
require nonclosing_ref_phrase "the prompt does not recognise a non-closing 'Refs #N' / 'Part of #N' reference" \
    "(refs|references|part of|related to)[ :'\"]*#n"
# Recognising it lets the PR through: the reference sits on the ok:true side.
require nonclosing_ref_passes "the non-closing reference is not tied to an {\"ok\": true} verdict" \
    '(refs|references|part of|related to)[^{]*\{\\?"ok\\?": true\}'
# A blocked agent is told about the non-closing reference in the block reason.
require reason_names_nonclosing_ref "the ok:false reason does not name the 'Refs #N' / 'Part of #N' option" \
    "(refs|references|part of|related to)[ :'\"]*#n" "$reason_text"

# Existing contract and checks must survive (issue scope: add the opt-out only).
require contract_ok_true "the {\"ok\": true} response shape is gone" '\{\\?"ok\\?": true\}'
require contract_ok_false "the {\"ok\": false, \"reason\": ...} response shape is gone" '\{\\?"ok\\?": false, \\?"reason\\?"'
require closing_keywords "the closes/fixes/resolves keyword check is gone" 'closes, fixes, resolves'
require infra_docs_deps_pass "the infrastructure/documentation/dependency pass is gone" \
    'infrastructure, documentation, or dependency'

emit
