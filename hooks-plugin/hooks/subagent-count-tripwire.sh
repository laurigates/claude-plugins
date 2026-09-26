#!/usr/bin/env bash
# SubagentStart + Stop hook — an after-the-fact tripwire on how many subagents
# a session has started.
#
# Why after the fact: a SubagentStart hook cannot stop or alter a subagent.
# Probed on 2.1.283 — exit 2, {"decision":"block"}, {"continue":false} and
# updatedPrompt were all ignored. What it can do is count. Each fresh agent
# costs ~66k tokens of prompt-cache creation even when trivial, so the count
# is the cost, and nothing in the UI shows it.
#
#   SubagentStart: append "<agent_id>\t<agent_type>" to a per-session file.
#                  Silent, never blocks, always exits 0.
#   Stop:          count distinct agent_ids (SubagentStart also re-fires on a
#                  subagent resume and per teammate message). When the count
#                  reaches the next unreported threshold — the limit, then each
#                  doubling (10, 20, 40, ...) — print one systemMessage, which
#                  Stop shows to the user without continuing the turn.
#
# Timing gap: a workflow's agents start after the Stop of the turn that
# launched it, so the count is reported at a later Stop (in an interactive
# session, the turn that handles the workflow's completion). A headless
# `claude -p` run can end before any Stop sees the full count.
#
# Tunables:
#   CLAUDE_HOOKS_WORKFLOW_MAX_AGENTS         first threshold (default 10)
#   CLAUDE_HOOKS_DISABLE_SUBAGENT_COUNT=1    disable entirely
#   CLAUDE_HOOKS_SUBAGENT_COUNT_DIR          state dir (tests)

# Observability hook: -e omitted so a failed write can never become a non-zero exit.
set -uo pipefail

[ "${CLAUDE_HOOKS_DISABLE_SUBAGENT_COUNT:-0}" = "1" ] && exit 0
command -v jq >/dev/null 2>&1 || exit 0

DIR="${CLAUDE_HOOKS_SUBAGENT_COUNT_DIR:-${TMPDIR:-/tmp}/claude-subagent-count}"

# \x1f, not a tab: read collapses runs of whitespace IFS, shifting empty fields.
IFS=$'\x1f' read -r EVENT SID AID ATYPE < <(jq -r '[.hook_event_name, .session_id, .agent_id, .agent_type] | map(. // "" | tostring | gsub("[\t\n\u001f]"; " ")) | join("\u001f")' 2>/dev/null)
case "$SID" in ''|*[!A-Za-z0-9._-]*) exit 0 ;; esac
LOG="$DIR/$SID.log"

case "$EVENT" in
SubagentStart)
    [ -n "$AID" ] || exit 0
    if [ ! -f "$LOG" ]; then
        # First subagent of this session: the only time we pay for cleanup.
        # Only this hook's own files, top level only. A session's log is
        # appended on every start, so its mtime is the activity signal: drop a
        # stale log together with its marker, and a marker only once its log
        # is gone (a long session's marker can be old while its log is fresh).
        mkdir -p "$DIR" 2>/dev/null || exit 0
        find "$DIR" -maxdepth 1 -type f -name '*.log' -mtime +3 2>/dev/null |
            while IFS= read -r f; do rm -f "$f" "${f%.log}.reported"; done
        find "$DIR" -maxdepth 1 -type f -name '*.reported' -mtime +3 2>/dev/null |
            while IFS= read -r f; do [ -f "${f%.reported}.log" ] || rm -f "$f"; done
    fi
    printf '%s\t%s\n' "$AID" "${ATYPE:-unknown}" >>"$LOG" 2>/dev/null
    ;;
Stop)
    [ -f "$LOG" ] || exit 0
    LIMIT="${CLAUDE_HOOKS_WORKFLOW_MAX_AGENTS:-10}"
    case "$LIMIT" in ''|*[!0-9]*) LIMIT=10 ;; esac
    # Base 10: "08" is not octal, and "00" must not reach the doubling loop.
    LIMIT=$((10#$LIMIT))
    [ "$LIMIT" -gt 0 ] || LIMIT=10
    read -r TOTAL WF < <(sort -u -t$'\t' -k1,1 "$LOG" | awk -F'\t' '{n++; if ($2=="workflow-subagent") w++} END {print n+0, w+0}')
    [ "$TOTAL" -ge "$LIMIT" ] || exit 0
    T=$LIMIT
    while [ $((T * 2)) -le "$TOTAL" ]; do T=$((T * 2)); done
    LAST=$(cat "$DIR/$SID.reported" 2>/dev/null)
    case "$LAST" in ''|*[!0-9]*) LAST=0 ;; esac
    [ "$T" -gt "$LAST" ] || exit 0
    printf '%s\n' "$T" >"$DIR/$SID.reported" 2>/dev/null
    MSG="This session has started ${TOTAL} subagents (${WF} workflow, $((TOTAL - WF)) agent-tool); limit is ${LIMIT}."
    jq -nc --arg m "$MSG" '{systemMessage: $m}'
    ;;
esac
exit 0
