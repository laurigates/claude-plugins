#!/usr/bin/env bash
# check-subagent-stop-background-wait.sh — semantic guard for the hooks-plugin
# SubagentStop "Output Quality Gate" prompt hook.
#
# THE BEHAVIOUR THIS PINS (issue #3194)
# Weekly friction reports showed the `stop:subagent-output-check` cluster
# re-blocking subagents 4.4x per session (66.7% same-session repeat). A sample
# block: the subagent's final message was only "Waiting for the test-run
# notification." while its task asked for a pushed PR. The generic "deliverable
# missing" reason did not tell it what to do, so it stopped again. The prompt
# now carries a dedicated check: output that says the subagent is waiting on its
# own background job or notification gets ok:false with a reason telling it to
# collect that result first.
#
# WHY A DEDICATED SCRIPT
# The artefact is a prompt string inside plugin.json, so
# plugin-compliance-check.sh (which iterates SKILL.md files) cannot reach it.
#
# Each rule is a concept with accepted spellings, so a reword passes and a
# revert fails (.claude/rules/regression-testing.md).
#
# Output: KEY=VALUE per .claude/rules/structured-script-output.md.
#   --plugin-json PATH  file to inspect (default: hooks-plugin's plugin.json)
#   --strict            exit 1 when ISSUE_COUNT > 0
# Exit: 0 clean (or non-strict with findings), 1 strict with findings,
#       2 unknown argument.

set -uo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PLUGIN_JSON="$ROOT_DIR/hooks-plugin/.claude-plugin/plugin.json"
STRICT=0

while [ $# -gt 0 ]; do
    case "$1" in
        --strict) STRICT=1 ;;
        --plugin-json)
            shift
            [ $# -gt 0 ] || { echo "check-subagent-stop-background-wait.sh: --plugin-json needs a value" >&2; exit 2; }
            PLUGIN_JSON="$1"
            ;;
        --plugin-json=*) PLUGIN_JSON="${1#--plugin-json=}" ;;
        -h|--help) echo "Usage: check-subagent-stop-background-wait.sh [--plugin-json PATH] [--strict]"; exit 0 ;;
        *) echo "check-subagent-stop-background-wait.sh: unknown argument: $1" >&2; exit 2 ;;
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
    echo "=== SUBAGENTSTOP BACKGROUND-WAIT CHECK ==="
    echo "PLUGIN_JSON=$PLUGIN_JSON"
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
    echo "=== END SUBAGENTSTOP BACKGROUND-WAIT CHECK ==="
    if [ "$STRICT" -eq 1 ] && [ "$issue_count" -gt 0 ]; then exit 1; fi
    exit 0
}

if [ ! -f "$PLUGIN_JSON" ]; then
    add_issue plugin_json_missing "file not found"
    emit
fi

prompts=$(jq -r '[.hooks.SubagentStop[]?.hooks[]? | select(.type == "prompt") | .prompt] | length' "$PLUGIN_JSON" 2>/dev/null) || {
    add_issue plugin_json_invalid "jq could not parse the file"
    emit
}
if [ "$prompts" != "1" ]; then
    add_issue prompt_count "expected exactly 1 SubagentStop prompt hook, found ${prompts:-0}"
    emit
fi

prompt=$(jq -r '[.hooks.SubagentStop[]?.hooks[]? | select(.type == "prompt") | .prompt][0]' "$PLUGIN_JSON")

# require RULE MSG REGEX -- case-insensitive ERE over the prompt text.
require() {
    grep -Eiq -- "$3" <<<"$prompt" || add_issue "$1" "$2"
}

# The check names the condition: the subagent is waiting on its OWN background
# job / task / notification.
require waiting_condition "no clause detects output saying the subagent is waiting" \
    '(waiting|wait(s)? (on|for))'
require background_job "the waiting clause does not name a background job, task or notification" \
    'background (job|task|process|run)|notification'
# The verdict for that condition is a block.
require block_verdict "no ok:false verdict tied to the waiting condition" \
    '(wait|background|notification)[^{]*ok[^a-z]{0,6}false|ok[^a-z]{0,6}false[^{]*(wait|background|notification)'
# The reason tells it to collect the result, then finish, rather than stop.
require collect_result "the reason does not tell the subagent to collect/retrieve the job's result" \
    '(collect|retrieve|read|fetch)[^.]{0,40}(result|output)'
require finish_deliverable "the reason does not tell the subagent to finish the deliverable before stopping" \
    '(finish|complete)[^.]{0,40}(deliverable|task)'

# Existing contract and checks must survive (issue scope: add one check only).
require contract_ok_true "the {\"ok\": true} response shape is gone" '\{\\?"ok\\?": true\}'
require contract_ok_false "the {\"ok\": false, \"reason\": ...} response shape is gone" '\{\\?"ok\\?": false, \\?"reason\\?"'
require existing_check_task "existing check 'addresses the original task' is gone" 'address the original task'
require existing_check_impl "existing check 'were the changes actually made' is gone" 'changes actually made'

emit
