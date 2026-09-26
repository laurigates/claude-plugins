#!/usr/bin/env bash
# Tests for subagent-count-tripwire.sh — feeds synthetic SubagentStart / Stop
# payloads and asserts the counter and the once-per-threshold reporting.
#
# Run: bash hooks-plugin/hooks/test-subagent-count-tripwire.sh
# Exit 0 = all pass, 1 = failures
set -uo pipefail

# Absolute: one case runs the hook from another CWD.
HOOK="$(cd "$(dirname "$0")" && pwd)/subagent-count-tripwire.sh"
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
check "state dir created" "yes" "$([ -d "$STATE" ] && echo yes || echo no)"
# shellcheck disable=SC2012  # mode string of one known path, not a listing
check "state dir private" "drwx------" "$(ls -ld "$STATE" | cut -c1-10)"

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
# ...and covers Stop: a session over the limit gets no report and no marker.
spawn s10 1 10 general-purpose >/dev/null
check "disabled Stop silent" "" "$(CLAUDE_HOOKS_DISABLE_SUBAGENT_COUNT=1 stop s10)"
check "disabled Stop writes no marker" "no" "$([ -f "$STATE/s10.reported" ] && echo yes || echo no)"
check "enabled Stop then reports" "10 subagents" "$(stop s10 | grep -o '10 subagents')"

# Default state dir is per user, ${TMPDIR}/claude-subagent-count-<uid>, and is
# created on first use.
mkdir -p "$ROOT/tmp"
for i in $(seq 1 10); do
    jq -nc --arg a "d$i" '{hook_event_name:"SubagentStart", session_id:"sdef", agent_id:$a, agent_type:"general-purpose"}' |
        env -u CLAUDE_HOOKS_SUBAGENT_COUNT_DIR TMPDIR="$ROOT/tmp" bash "$HOOK"
done
check "default dir records" "10" "$(wc -l <"$ROOT/tmp/claude-subagent-count-$EUID/sdef.log" 2>/dev/null | tr -d ' ')"
check "default dir reports" "10 subagents" \
    "$(jq -nc '{hook_event_name:"Stop", session_id:"sdef"}' |
        env -u CLAUDE_HOOKS_SUBAGENT_COUNT_DIR TMPDIR="$ROOT/tmp" bash "$HOOK" | grep -o '10 subagents')"

# Unsafe session_id is ignored rather than used as a path. The name is unique
# per run so a leftover file in the shared parent cannot fail (or pass) it.
EVIL="evil-$$-$RANDOM"
start "../$EVIL" a1 general-purpose >/dev/null
check "path traversal ignored" "no" "$([ -f "$STATE/../$EVIL.log" ] && echo yes || echo no)"
rm -f "$STATE/../$EVIL.log"

# Limit is read in base 10 and a zero limit falls back to 10, so Stop cannot hang.
spawn s7 1 12 general-purpose >/dev/null
# Bounded by timeout where available: the pre-fix hook looped forever here.
TO=$(command -v timeout || command -v gtimeout || true)
check "limit 00 falls back to 10" "limit is 10." \
    "$(jq -nc '{hook_event_name:"Stop", session_id:"s7"}' |
        CLAUDE_HOOKS_WORKFLOW_MAX_AGENTS=00 ${TO:+$TO 5} bash "$HOOK" | grep -o 'limit is 10.')"
rm -f "$STATE/s7.reported"
check "limit 08 is eight" "limit is 8." \
    "$(CLAUDE_HOOKS_WORKFLOW_MAX_AGENTS=08 stop s7 2>&1 | grep -o 'limit is 8.')"

# Garbage input exits 0 silently.
check "garbage input" "0:" "$(echo 'not json' | bash "$HOOK"; echo "$?:")"

# Stale per-session files are removed when a new session starts counting.
touch -t 202001010000 "$STATE/old.log"
start s6 a1 general-purpose >/dev/null
check "stale file cleaned" "no" "$([ -f "$STATE/old.log" ] && echo yes || echo no)"
check "live file kept" "yes" "$([ -f "$STATE/s1.log" ] && echo yes || echo no)"

# Cleanup touches only this hook's top-level files, and keeps a live session's
# marker even when the marker itself is old.
mkdir -p "$STATE/sub"
touch -t 202001010000 "$STATE/unrelated.txt" "$STATE/sub/nested.log" "$STATE/s1.reported"
touch -t 202001010000 "$STATE/gone.reported"
start s8 a1 general-purpose >/dev/null
check "unrelated file kept" "yes" "$([ -f "$STATE/unrelated.txt" ] && echo yes || echo no)"
check "nested file kept" "yes" "$([ -f "$STATE/sub/nested.log" ] && echo yes || echo no)"
check "live session marker kept" "yes" "$([ -f "$STATE/s1.reported" ] && echo yes || echo no)"
check "orphan marker cleaned" "no" "$([ -f "$STATE/gone.reported" ] && echo yes || echo no)"
check "live session not re-reported" "" "$(stop s1)"

# The staleness window is over 3 days of wall clock at both edges: GNU
# `find -mtime +3` kept an 80h-idle log. A marker idle under 3 days is kept
# even when its log is gone.
ago() { # hours file... -> set mtime <hours> ago (GNU or BSD date)
    local h=$1 ts
    shift
    ts=$(($(date +%s) - h * 3600))
    ts=$(date -d "@$ts" +%Y%m%d%H%M.%S 2>/dev/null || date -r "$ts" +%Y%m%d%H%M.%S)
    touch -t "$ts" "$@"
}
touch "$STATE/idle60h.log" "$STATE/idle80h.log" "$STATE/idle80h.reported" "$STATE/fresh-orphan.reported"
ago 60 "$STATE/idle60h.log"
ago 80 "$STATE/idle80h.log" "$STATE/idle80h.reported"
# A newline in a stale file's name must not split it into a path in the CWD.
mkdir -p "$ROOT/cwd"
touch "$ROOT/cwd/victim.log" "$ROOT/cwd/victim.reported"
NL_LOG="$STATE/x
victim.log"
touch -t 202001010000 "$NL_LOG"
(cd "$ROOT/cwd" && start s11 a1 general-purpose >/dev/null)
check "60h-idle log kept" "yes" "$([ -f "$STATE/idle60h.log" ] && echo yes || echo no)"
check "80h-idle log cleaned" "no" "$([ -f "$STATE/idle80h.log" ] && echo yes || echo no)"
check "80h-idle marker cleaned" "no" "$([ -f "$STATE/idle80h.reported" ] && echo yes || echo no)"
check "fresh orphan marker kept" "yes" "$([ -f "$STATE/fresh-orphan.reported" ] && echo yes || echo no)"
check "newline name: CWD files kept" "yes" \
    "$([ -f "$ROOT/cwd/victim.log" ] && [ -f "$ROOT/cwd/victim.reported" ] && echo yes || echo no)"
check "newline name: stale file cleaned" "no" "$([ -e "$NL_LOG" ] && echo yes || echo no)"

# A named dir the hook did not create is never cleaned: the *.log glob alone
# would delete a foreign log idle over 3 days.
mkdir -p "$ROOT/shared"
touch -t 202001010000 "$ROOT/shared/app.log" "$ROOT/shared/events.log" "$ROOT/shared/app.reported"
CLAUDE_HOOKS_SUBAGENT_COUNT_DIR="$ROOT/shared" start s12 a1 general-purpose >/dev/null
check "existing dir: foreign files kept" "yes" \
    "$([ -f "$ROOT/shared/app.log" ] && [ -f "$ROOT/shared/events.log" ] && [ -f "$ROOT/shared/app.reported" ] && echo yes || echo no)"
check "existing dir: still counts" "yes" "$([ -f "$ROOT/shared/s12.log" ] && echo yes || echo no)"

# A state dir that is a symlink, or owned by another user, is refused rather
# than written through: a planted symlink would turn writes into clobbers.
mkdir -p "$ROOT/target"
ln -s "$ROOT/target" "$ROOT/link"
check "symlinked dir: silent" "" "$(CLAUDE_HOOKS_SUBAGENT_COUNT_DIR="$ROOT/link" start s13 a1 general-purpose 2>&1)"
check "symlinked dir: nothing written" "0" "$(find "$ROOT/target" -mindepth 1 | wc -l | tr -d ' ')"
for i in $(seq 1 10); do printf 'l%s\tgeneral-purpose\n' "$i"; done >"$ROOT/target/s13.log"
check "symlinked dir: Stop silent" "" "$(CLAUDE_HOOKS_SUBAGENT_COUNT_DIR="$ROOT/link" stop s13 2>&1)"
check "symlinked dir: no marker" "no" "$([ -f "$ROOT/target/s13.reported" ] && echo yes || echo no)"
if [ "$EUID" -eq 0 ]; then
    mkdir -p "$ROOT/foreign"
    chown 65534 "$ROOT/foreign"
    check "foreign-owned dir: silent" "" \
        "$(CLAUDE_HOOKS_SUBAGENT_COUNT_DIR="$ROOT/foreign" start s14 a1 general-purpose 2>&1)"
    check "foreign-owned dir: nothing written" "no" "$([ -f "$ROOT/foreign/s14.log" ] && echo yes || echo no)"
else
    echo "SKIP: foreign-owned dir checks need root (chown)"
fi

echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
