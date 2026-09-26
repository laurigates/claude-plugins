#!/usr/bin/env bash
# Tests for subagent-count-tripwire.sh — feeds synthetic SubagentStart / Stop
# payloads and asserts the counter and the once-per-threshold reporting.
#
# Run: bash hooks-plugin/hooks/test-subagent-count-tripwire.sh
# Exit 0 = all pass, 1 = failures
set -uo pipefail

HOOK="$(dirname "$0")/subagent-count-tripwire.sh"
PASS=0
FAIL=0

if ! command -v jq >/dev/null 2>&1; then
    echo "SKIP: jq not installed"
    exit 0
fi

STATE=$(mktemp -d)
trap 'rm -rf "$STATE"' EXIT
export CLAUDE_HOOKS_SUBAGENT_COUNT_DIR="$STATE"
unset CLAUDE_HOOKS_DISABLE_SUBAGENT_COUNT CLAUDE_HOOKS_WORKFLOW_MAX_AGENTS

check() { # name expected actual
    if [ "$2" = "$3" ]; then PASS=$((PASS + 1)); else
        FAIL=$((FAIL + 1)); echo "FAIL: $1"; echo "  expected: $2"; echo "  actual:   $3"
    fi
}

start() { # sid agent_id agent_type -> hook stdout
    jq -nc --arg s "$1" --arg a "$2" --arg t "$3" \
        '{hook_event_name:"SubagentStart", session_id:$s, agent_id:$a, agent_type:$t, cwd:"/tmp"}' | bash "$HOOK"
}
stop() { # sid -> hook stdout
    jq -nc --arg s "$1" '{hook_event_name:"Stop", session_id:$s, stop_hook_active:false}' | bash "$HOOK"
}
spawn() { # sid first last type
    local i out=""
    for i in $(seq "$2" "$3"); do out="$out$(start "$1" "a$i" "$4")"; done
    printf '%s' "$out"
}

# SubagentStart is silent and exits 0, and records one line per agent.
check "SubagentStart silent" "" "$(spawn s1 1 6 workflow-subagent)"
check "SubagentStart exit 0" "0" "$(start s1 a7 general-purpose >/dev/null; echo $?)"
check "counter lines" "7" "$(wc -l <"$STATE/s1.log" | tr -d ' ')"

# Below the limit: Stop is silent.
check "below limit silent" "" "$(stop s1)"

# Crossing 10 reports once, with the workflow / agent-tool split.
spawn s1 8 10 general-purpose >/dev/null
check "report at 10" \
    '{"systemMessage":"This session has started 10 subagents (6 workflow, 4 agent-tool); limit is 10."}' \
    "$(stop s1)"
check "no repeat at 10" "" "$(stop s1)"

# Re-fired SubagentStart for the same agent_id (resume) does not inflate the count.
spawn s1 1 10 workflow-subagent >/dev/null
check "duplicate ids ignored" "" "$(stop s1)"

# 11..19 stay silent; 20 reports; 39 silent; 40 reports.
spawn s1 11 19 workflow-subagent >/dev/null
check "19 silent" "" "$(stop s1)"
spawn s1 20 20 workflow-subagent >/dev/null
check "report at 20" "20 subagents" "$(stop s1 | grep -o '20 subagents')"
spawn s1 21 39 workflow-subagent >/dev/null
check "39 silent" "" "$(stop s1)"
spawn s1 40 45 workflow-subagent >/dev/null
check "report at 40 (count 45)" "45 subagents" "$(stop s1 | grep -o '45 subagents')"
check "no repeat at 45" "" "$(stop s1)"

# Jumping past several thresholds at once reports once, for the highest.
spawn s2 1 25 workflow-subagent >/dev/null
check "jump reports once" "1" "$(stop s2 | grep -c systemMessage)"
check "jump records 20" "20" "$(cat "$STATE/s2.reported")"
check "jump then silent" "" "$(stop s2)"

# Sessions are independent.
check "no log, Stop silent" "" "$(stop s3)"

# Custom limit.
spawn s4 1 3 general-purpose >/dev/null
check "custom limit" "limit is 3." "$(CLAUDE_HOOKS_WORKFLOW_MAX_AGENTS=3 stop s4 | grep -o 'limit is 3.')"

# Opt-out: nothing recorded, nothing reported.
check "disabled start" "" "$(CLAUDE_HOOKS_DISABLE_SUBAGENT_COUNT=1 start s5 a1 general-purpose)"
check "disabled records nothing" "no" "$([ -f "$STATE/s5.log" ] && echo yes || echo no)"

# Unsafe session_id is ignored rather than used as a path.
start "../evil" a1 general-purpose >/dev/null
check "path traversal ignored" "no" "$([ -f "$STATE/../evil.log" ] && echo yes || echo no)"

# Garbage input exits 0 silently.
check "garbage input" "0:" "$(echo 'not json' | bash "$HOOK"; echo "$?:")"

# Stale per-session files are removed when a new session starts counting.
touch -t 202001010000 "$STATE/old.log"
start s6 a1 general-purpose >/dev/null
check "stale file cleaned" "no" "$([ -f "$STATE/old.log" ] && echo yes || echo no)"
check "live file kept" "yes" "$([ -f "$STATE/s1.log" ] && echo yes || echo no)"

echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
