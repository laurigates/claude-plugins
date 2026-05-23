#!/usr/bin/env bash
# Stop hook — soft suggestion that the agent restate work in tokens / effort
# tier rather than human calendar time. AI work doesn't map to hours, days,
# weeks, or months; quoting calendar estimates is consistently misleading.
#
# Shape: one nudge per response. Fires {"decision":"block","reason":"..."} on
# first detection; the agent revises; the stop_hook_active guard accepts the
# revised response silently. The reason text carries the positive guidance
# inline so it ships self-contained with the plugin — consumers don't need a
# separate .claude/rules/ file.
#
# Opt-in: set CLAUDE_HOOKS_ENABLE_CALENDAR_ESTIMATES=1 to enable.
set -uo pipefail

# Opt-in guard — disabled by default
if [ "${CLAUDE_HOOKS_ENABLE_CALENDAR_ESTIMATES:-0}" != "1" ]; then
    exit 0
fi

INPUT=$(cat)
STOP_HOOK_ACTIVE=$(echo "$INPUT" | jq -r '.stop_hook_active // false')
TRANSCRIPT_PATH=$(echo "$INPUT" | jq -r '.transcript_path // empty')

# One nudge per response: after the agent revises, stop_hook_active=true and
# the second pass accepts silently. Prevents loops.
if [ "$STOP_HOOK_ACTIVE" = "true" ]; then
    exit 0
fi

if [ -z "$TRANSCRIPT_PATH" ] || [ ! -f "$TRANSCRIPT_PATH" ]; then
    exit 0
fi

if ! command -v jq >/dev/null 2>&1; then
    exit 0
fi

# Extract the last assistant message's text content from the JSONL transcript.
LAST_RESPONSE=$(jq -Rs '
    split("\n")
    | map(select(length > 0))
    | map(try fromjson catch null)
    | map(select(. != null))
    | map(select(.message.role == "assistant"))
    | last
    | if . == null then "" else
        (.message.content
         | if type == "string" then .
           else map(select(.type == "text") | .text) | join("\n")
         end)
      end
' "$TRANSCRIPT_PATH" 2>/dev/null || echo "")

if [ -z "$LAST_RESPONSE" ]; then
    exit 0
fi

# Calendar-time estimation regexes. Two carefully-scoped patterns:
#
#   PATTERN_FUTURE — future-tense modal + estimation verb + number + time unit.
#     Catches: "this'll take 3 hours", "would take roughly 5 minutes",
#              "should require 2 weeks", "will need about 30 minutes".
#     Skips:   "took 2 minutes" (past tense), "every 3 hours" (frequency),
#              "modified 2 days ago" (observation), "30s timeout" (config).
#
#   PATTERN_MARKER — explicit estimation marker + number + time unit.
#     Catches: "ETA: 30 minutes", "estimated 2 days", "approximately 5 hours",
#              "expect this in 2 weeks".
#     Skips:   "about 30 minutes ago" (we drop "about" — too ambiguous past/future).
#
# Time-unit floor is "minute" — seconds are usually config (timeouts, sleeps,
# retries) rather than effort estimates.
#
# Regex uses [^.!?]* (unbounded, but sentence-terminator-anchored) rather than
# bounded {0,N} repetition. GNU grep's NFA implementation can hit catastrophic
# backtracking on long bounded patterns with multiple groups; the unbounded
# form stays linear and naturally stops at sentence boundaries.
PATTERN_FUTURE="(will|would|should|could|may|might|'ll|going to|gonna)[^.!?]*(take|takes|taking|require|requires|need|needs)[^.!?]*([0-9]+|a few|several|many|couple)[^.!?]*(minute|hour|day|week|month|year)s?"
PATTERN_MARKER="(ETA|estimate|estimated|estimating|expect|expects|expected|approximately|roughly|around)[^.!?]*([0-9]+|a few|several|many|couple)[^.!?]*(minute|hour|day|week|month|year)s?"

if echo "$LAST_RESPONSE" | grep -qiE "$PATTERN_FUTURE|$PATTERN_MARKER"; then
    REASON="Avoid quoting AI work in calendar time (hours, days, weeks, months). The honest units for agent work are: tokens consumed, context-window share remaining, effort tier (low / medium / high / max), tool-call count, or files / lines to touch. Restate the estimate in one of those units."
    # shellcheck disable=SC2016  # jq expression, not shell expansion
    jq -n --arg reason "$REASON" '{"decision": "block", "reason": $reason}'
    exit 0
fi

exit 0
