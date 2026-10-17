#!/usr/bin/env bash
# PostToolUse hook — tells the agent when its context crosses a size threshold.
#
# Why: Claude Haiku 5.5 is priced by prompt length. A request whose prompt is
# over 100,000 tokens (cache reads and writes included) pays 5x the input,
# cache and output rates, and every later request does too until the context
# shrinks. Nothing tells the model where it stands, so a Haiku worker or a
# /loop session drifts across the line unnoticed. No hook event carries a
# token count, so this reads the newest usage record from the transcript.
#
#   Prompt size = input_tokens + cache_creation_input_tokens
#                 + cache_read_input_tokens of the newest assistant entry.
#   Thresholds  = 80000,95000 when that entry's model is claude-haiku-5-5;
#                 other models stay silent unless CLAUDE_HOOKS_CONTEXT_THRESHOLDS
#                 is set, which then applies to every model.
#   Reporting   = the highest threshold the prompt has reached, once. A prompt
#                 back under the lowest threshold (after /compact) re-arms it.
#   Subagents   = a payload with agent_id reads
#                 <transcript dir>/<session>/subagents/agent-<id>.jsonl and keeps
#                 its own state, so each Haiku worker is warned about itself.
#
# Lag: the transcript is written after the request, and a subagent's file can
# trail the live conversation by a request, so the warning may arrive one tool
# call late. The gap between the thresholds and 100,000 absorbs that.
#
# Output: hookSpecificOutput.additionalContext (seen by the model; the tool
# call itself is never blocked). Always exits 0.
#
# Tunables:
#   CLAUDE_HOOKS_CONTEXT_THRESHOLDS        comma-separated token counts; applies
#                                          to every model when it has a valid entry
#   CLAUDE_HOOKS_DISABLE_CONTEXT_THRESHOLD=1  disable entirely
#   CLAUDE_HOOKS_CONTEXT_THRESHOLD_DIR     state dir (tests); default
#                                          ${TMPDIR:-/tmp}/claude-context-threshold-<uid>

# Advisory hook: -e omitted so a failed read or write can never become a non-zero exit.
set -uo pipefail

[ "${CLAUDE_HOOKS_DISABLE_CONTEXT_THRESHOLD:-0}" = "1" ] && exit 0
command -v jq >/dev/null 2>&1 || exit 0

IFS=$'\x1f' read -r SID TPATH AID < <(jq -r '[.session_id, .transcript_path, .agent_id] | map(. // "" | tostring | gsub("[\t\n\u001f]"; " ")) | join("\u001f")' 2>/dev/null)
case "$SID" in ''|*[!A-Za-z0-9._-]*) exit 0 ;; esac
case "$AID" in *[!A-Za-z0-9._-]*) exit 0 ;; esac
[ -n "$TPATH" ] || exit 0

TRANSCRIPT="$TPATH"
KEY="$SID"
if [ -n "$AID" ]; then
    TRANSCRIPT="${TPATH%.jsonl}/subagents/agent-$AID.jsonl"
    KEY="$SID.$AID"
fi
[ -f "$TRANSCRIPT" ] || exit 0

# Newest assistant entry with usage. tail bounds the work on a long transcript;
# fromjson? skips the line tail may cut and any other unparseable line.
IFS=$'\t' read -r MODEL PROMPT < <(tail -n 500 "$TRANSCRIPT" 2>/dev/null |
    jq -nrR '[inputs | fromjson? | select(.type == "assistant" and (.message.usage | type) == "object")] | last // empty
        | .message | [(.model // ""), ((.usage.input_tokens // 0) + (.usage.cache_creation_input_tokens // 0) + (.usage.cache_read_input_tokens // 0))]
        | @tsv' 2>/dev/null)
case "$PROMPT" in ''|*[!0-9]*) exit 0 ;; esac

HAIKU=0
case "$MODEL" in claude-haiku-5-5*) HAIKU=1 ;; esac

THRESHOLDS=""
if [ -n "${CLAUDE_HOOKS_CONTEXT_THRESHOLDS:-}" ]; then
    THRESHOLDS=$(tr ',' '\n' <<<"$CLAUDE_HOOKS_CONTEXT_THRESHOLDS" | tr -d ' ' |
        grep -E '^[0-9]+$' | sed 's/^0*//' | grep -E '^[0-9]+$' | sort -n -u | tr '\n' ' ')
fi
if [ -z "$THRESHOLDS" ]; then
    [ "$HAIKU" = "1" ] || exit 0
    THRESHOLDS="80000 95000"
fi
read -r -a LEVELS <<<"$THRESHOLDS"

DIR="${CLAUDE_HOOKS_CONTEXT_THRESHOLD_DIR:-${TMPDIR:-/tmp}/claude-context-threshold-$EUID}"
if [ ! -e "$DIR" ] && [ ! -L "$DIR" ]; then
    # shellcheck disable=SC2174  # only the leaf is ours; parents keep their modes
    mkdir -p -m 700 "$DIR" 2>/dev/null || exit 0
fi
# Write only into a real directory this user owns: in one another user created,
# a planted symlink would turn our writes into clobbers of its target.
{ [ -d "$DIR" ] && [ ! -L "$DIR" ] && [ -O "$DIR" ]; } || exit 0
STATE="$DIR/$KEY.level"

if [ "$PROMPT" -lt "${LEVELS[0]}" ]; then
    rm -f "$STATE" 2>/dev/null
    exit 0
fi
HIT=0
for t in "${LEVELS[@]}"; do [ "$PROMPT" -ge "$t" ] && HIT=$t; done
LAST=$(cat "$STATE" 2>/dev/null)
case "$LAST" in ''|*[!0-9]*) LAST=0 ;; esac
[ "$HIT" -gt "$LAST" ] || exit 0
printf '%s\n' "$HIT" 2>/dev/null >"$STATE"

commas() {
    local n=$1 out=""
    while [ "${#n}" -gt 3 ]; do out=",${n: -3}$out"; n=${n:0:${#n}-3}; done
    printf '%s' "$n$out"
}

MSG="Context check: your last request sent $(commas "$PROMPT") prompt tokens, past the $(commas "$HIT")-token warning threshold."
if [ "$HAIKU" = "1" ]; then
    MSG="$MSG Claude Haiku 5.5 bills every request whose prompt exceeds 100,000 tokens (cache reads included) at 5x its normal rates."
fi
MSG="$MSG Finish the current step and keep further reads small. If more work remains, hand it off with a short written brief, or compact the conversation."
jq -nc --arg m "$MSG" '{hookSpecificOutput: {hookEventName: "PostToolUse", additionalContext: $m}}'
exit 0
