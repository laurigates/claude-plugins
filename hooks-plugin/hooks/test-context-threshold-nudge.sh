#!/usr/bin/env bash
# Tests for context-threshold-nudge.sh — writes synthetic transcripts, feeds
# PostToolUse payloads, and asserts when the hook injects additionalContext.
#
# Run: bash hooks-plugin/hooks/test-context-threshold-nudge.sh
# Exit 0 = all pass, 1 = failures
set -uo pipefail

HOOK="$(cd "$(dirname "$0")" && pwd)/context-threshold-nudge.sh"
PASS=0
FAIL=0

if ! command -v jq >/dev/null 2>&1; then
    echo "SKIP: jq not installed"
    exit 0
fi

ROOT=$(mktemp -d)
trap 'rm -rf "$ROOT"' EXIT
# Not created here: the hook must create its own state dir on first use.
STATE="$ROOT/state"
export CLAUDE_HOOKS_CONTEXT_THRESHOLD_DIR="$STATE"
unset CLAUDE_HOOKS_DISABLE_CONTEXT_THRESHOLD CLAUDE_HOOKS_CONTEXT_THRESHOLDS

check() { # name expected actual
    if [ "$2" = "$3" ]; then PASS=$((PASS + 1)); else
        FAIL=$((FAIL + 1)); echo "FAIL: $1"; echo "  expected: $2"; echo "  actual:   $3"
    fi
}

# usage <file> <model> <prompt-tokens>: append one assistant entry whose
# input + cache_creation + cache_read sums to <prompt-tokens>, plus the
# user/attachment noise a real transcript carries.
usage() {
    local third=$(($3 / 3))
    {
        jq -nc '{type:"user", message:{role:"user", content:"x"}}'
        jq -nc --arg m "$2" --argjson a 2 --argjson w "$third" --argjson r "$(($3 - third - 2))" \
            '{type:"assistant", message:{model:$m, usage:{input_tokens:$a, cache_creation_input_tokens:$w, cache_read_input_tokens:$r, output_tokens:10}}}'
        jq -nc '{type:"attachment", attachment:{type:"x"}}'
    } >>"$1"
}
fire() { # sid transcript [agent_id] -> hook stdout
    jq -nc --arg s "$1" --arg t "$2" --arg a "${3:-}" \
        '{hook_event_name:"PostToolUse", session_id:$s, transcript_path:$t, tool_name:"Bash", cwd:"/tmp"}
         + (if $a == "" then {} else {agent_id:$a, agent_type:"general-purpose"} end)' | bash "$HOOK"
}
ctx() { jq -r '.hookSpecificOutput.additionalContext // empty'; }

H=claude-haiku-5-5
T1="$ROOT/s1.jsonl"

# Below the first threshold: silent, exit 0.
usage "$T1" "$H" 50000
check "50k silent" "" "$(fire s1 "$T1")"
check "exit 0" "0" "$(fire s1 "$T1" >/dev/null; echo $?)"
check "state dir private" "drwx------" "$(stat -c '%A' "$STATE" 2>/dev/null || stat -f '%Sp' "$STATE")"

# Crossing 80k: one PostToolUse additionalContext naming the size and threshold.
usage "$T1" "$H" 81234
OUT=$(fire s1 "$T1")
check "80k event name" "PostToolUse" "$(jq -r '.hookSpecificOutput.hookEventName' <<<"$OUT")"
check "80k names size" "1" "$(ctx <<<"$OUT" | grep -c 'sent 81,234 prompt tokens')"
check "80k names threshold" "1" "$(ctx <<<"$OUT" | grep -c '80,000-token')"
check "haiku names price cliff" "1" "$(ctx <<<"$OUT" | grep -c '100,000')"
check "no repeat at 80k" "" "$(fire s1 "$T1")"
usage "$T1" "$H" 90000
check "90k silent" "" "$(fire s1 "$T1")"

# Crossing 95k reports once; growing further stays silent.
usage "$T1" "$H" 96000
check "95k reports" "1" "$(fire s1 "$T1" | ctx | grep -c '95,000-token')"
usage "$T1" "$H" 130000
check "past last threshold silent" "" "$(fire s1 "$T1")"

# After compaction the prompt drops below the first threshold: re-arm.
usage "$T1" "$H" 30000
check "post-compact silent" "" "$(fire s1 "$T1")"
usage "$T1" "$H" 82000
check "re-armed after compact" "1" "$(fire s1 "$T1" | ctx | grep -c '80,000-token')"

# Jumping past both thresholds at once reports once, for the higher.
T2="$ROOT/s2.jsonl"
usage "$T2" "$H" 99000
OUT=$(fire s2 "$T2")
check "jump reports highest" "1" "$(ctx <<<"$OUT" | grep -c '95,000-token')"
check "jump reports once" "" "$(fire s2 "$T2")"

# Other models: silent by default, even far past the Haiku thresholds.
T3="$ROOT/s3.jsonl"
usage "$T3" claude-opus-5-5 400000
check "opus silent by default" "" "$(fire s3 "$T3")"

# Explicit thresholds apply to every model, without the Haiku price note.
T4="$ROOT/s4.jsonl"
usage "$T4" claude-opus-5-5 210000
OUT=$(CLAUDE_HOOKS_CONTEXT_THRESHOLDS=200000,400000 fire s4 "$T4")
check "custom threshold on opus" "1" "$(ctx <<<"$OUT" | grep -c '200,000-token')"
check "no price note off haiku" "0" "$(ctx <<<"$OUT" | grep -c '100,000')"
# Garbage entries are dropped; an all-garbage list means the defaults.
T5="$ROOT/s5.jsonl"
usage "$T5" "$H" 85000
check "garbage list -> defaults" "1" "$(CLAUDE_HOOKS_CONTEXT_THRESHOLDS='x,,-5' fire s5 "$T5" | ctx | grep -c '80,000-token')"
T6="$ROOT/s6.jsonl"
usage "$T6" "$H" 85000
check "unsorted list sorted" "1" "$(CLAUDE_HOOKS_CONTEXT_THRESHOLDS='90000,x,60000' fire s6 "$T6" | ctx | grep -c '60,000-token')"

# Subagent: reads <transcript>/subagents/agent-<id>.jsonl, with its own state.
SUBDIR="$ROOT/s1/subagents"
mkdir -p "$SUBDIR"
usage "$SUBDIR/agent-a1.jsonl" "$H" 83000
check "subagent reads own transcript" "1" "$(fire s1 "$T1" a1 | ctx | grep -c 'sent 83,000 prompt tokens')"
check "subagent state separate" "" "$(fire s1 "$T1" a1)"
# Subagent transcript not flushed yet (no usage line): silent, not the parent's.
check "subagent unflushed silent" "" "$(fire s1 "$T1" a2)"

# Robustness: missing transcript, truncated/garbage lines, no usage, bad sid.
check "missing transcript" "" "$(fire s7 "$ROOT/nope.jsonl")"
T8="$ROOT/s8.jsonl"
printf '%s\n' 'cache_read_input_tokens":5}}}' 'not json' >"$T8"
usage "$T8" "$H" 86000
printf '%s\n' '{"type":"assistant","message":{"model":"claude-haiku-5-5"' >>"$T8"
check "garbage lines skipped" "1" "$(fire s8 "$T8" | ctx | grep -c 'sent 86,000 prompt tokens')"
check "unsafe sid ignored" "" "$(fire '../x' "$T1")"
check "empty stdin exit 0" "0" "$(: | bash "$HOOK" >/dev/null; echo $?)"

# Opt-out.
T9="$ROOT/s9.jsonl"
usage "$T9" "$H" 97000
check "disabled" "" "$(CLAUDE_HOOKS_DISABLE_CONTEXT_THRESHOLD=1 fire s9 "$T9")"

# A state dir that is a symlink is refused (no writes through it).
LINK="$ROOT/link"
mkdir -p "$ROOT/elsewhere"
ln -s "$ROOT/elsewhere" "$LINK"
T10="$ROOT/s10.jsonl"
usage "$T10" "$H" 97000
check "symlinked state dir refused" "" "$(CLAUDE_HOOKS_CONTEXT_THRESHOLD_DIR="$LINK" fire s10 "$T10")"
check "nothing written via symlink" "0" "$(find "$ROOT/elsewhere" -type f | wc -l | tr -d ' ')"

echo "context-threshold-nudge: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
