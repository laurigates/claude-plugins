#!/usr/bin/env bash
# SubagentStart + Stop hook — an after-the-fact tripwire on how many subagents
# a session has started.
#
# Why after the fact: a SubagentStart hook cannot block or stop a subagent; it
# can only add context to one (additionalContext). Probed on 2.1.283 — exit 2,
# {"decision":"block"}, {"continue":false} and updatedPrompt were all ignored.
# What it can do is count. Each fresh agent costs ~66k tokens of prompt-cache
# creation even when trivial, so the count is the cost, and nothing in the UI
# shows it.
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
#   CLAUDE_HOOKS_SUBAGENT_COUNT_DIR          state dir (tests); default
#                                            ${TMPDIR:-/tmp}/claude-subagent-count-<uid>

# Observability hook: -e omitted so a failed write can never become a non-zero exit.
set -uo pipefail

[ "${CLAUDE_HOOKS_DISABLE_SUBAGENT_COUNT:-0}" = "1" ] && exit 0
command -v jq >/dev/null 2>&1 || exit 0

# Per user: one shared /tmp name would be created 0755 by whoever came first,
# and every other user's appends would fail.
DIR="${CLAUDE_HOOKS_SUBAGENT_COUNT_DIR:-${TMPDIR:-/tmp}/claude-subagent-count-$EUID}"
# Present only in a directory this hook created; cleanup runs nowhere else.
OWNED="$DIR/.subagent-count-tripwire"

# \x1f, not a tab: read collapses runs of whitespace IFS, shifting empty fields.
IFS=$'\x1f' read -r EVENT SID AID ATYPE < <(jq -r '[.hook_event_name, .session_id, .agent_id, .agent_type] | map(. // "" | tostring | gsub("[\t\n\u001f]"; " ")) | join("\u001f")' 2>/dev/null)
case "$SID" in ''|*[!A-Za-z0-9._-]*) exit 0 ;; esac
LOG="$DIR/$SID.log"

# Write only into a real directory this user owns. In one another user
# created, a planted symlink would turn our writes into clobbers of its target.
own_dir() { [ -d "$DIR" ] && [ ! -L "$DIR" ] && [ -O "$DIR" ]; }

case "$EVENT" in
SubagentStart)
    [ -n "$AID" ] || exit 0
    if [ ! -e "$DIR" ] && [ ! -L "$DIR" ]; then
        # shellcheck disable=SC2174  # only the leaf is ours; parents keep their modes
        mkdir -p -m 700 "$DIR" 2>/dev/null || exit 0
        own_dir && : 2>/dev/null >"$OWNED"
    fi
    own_dir || exit 0
    if [ ! -f "$LOG" ] && [ -f "$OWNED" ]; then
        # First subagent of this session: the only time we pay for cleanup.
        # Top-level *.log / *.reported only. A session's log is appended on
        # every start, so its mtime is the activity signal: drop a log idle
        # over 3 days (-mmin; GNU -mtime +3 would mean 4) together with its
        # marker, and a marker idle as long only once its log is gone (a long
        # session's marker can be old while its log is fresh). -print0: a
        # newline in a name must not split it into a path outside $DIR.
        find "$DIR" -maxdepth 1 -type f -name '*.log' -mmin +4320 -print0 2>/dev/null |
            while IFS= read -r -d '' f; do rm -f "$f" "${f%.log}.reported"; done
        find "$DIR" -maxdepth 1 -type f -name '*.reported' -mmin +4320 -print0 2>/dev/null |
            while IFS= read -r -d '' f; do [ -f "${f%.reported}.log" ] || rm -f "$f"; done
    fi
    printf '%s\t%s\n' "$AID" "${ATYPE:-unknown}" 2>/dev/null >>"$LOG"
    ;;
Stop)
    own_dir || exit 0
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
    printf '%s\n' "$T" 2>/dev/null >"$DIR/$SID.reported"
    MSG="This session has started ${TOTAL} subagents (${WF} workflow, $((TOTAL - WF)) agent-tool); limit is ${LIMIT}."
    jq -nc --arg m "$MSG" '{systemMessage: $m}'
    ;;
esac
exit 0
