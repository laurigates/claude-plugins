#!/usr/bin/env bash
# Stop hook — soft suggestion that the agent restate work in tokens / effort
# tier rather than human calendar time. AI work doesn't map to hours, days,
# weeks, or months; quoting calendar estimates is consistently misleading.
#
# Shape: one nudge per response. Fires {"decision":"block","reason":"..."} on
# first detection; the agent revises; the stop_hook_active guard accepts the
# revised response silently. The reason text carries the positive guidance
# inline so it ships self-contained with the plugin — consumers don't need a
# separate .claude/rules/ file. That guidance has two branches: agent *effort*
# restates in tokens / effort tier / tool calls; external machine work the agent
# *measured* (a CI run, build, model download, render, long test suite) really
# is wall-clock and restates as rate x quantity with the measurement named
# (#2574). The matcher stays deliberately broad — it still fires on a measured
# rate, and the message tells the reader how to phrase it honestly rather than
# offering only units that cannot express it. Which of the two branches is
# emitted is chosen per block (#2650): a measured rate in the matched text leads
# with rate x quantity; everything else keeps the generic effort-unit message.
#
# Match scope (#2650): only the text the *main* agent actually ended its turn
# with. Subagent/sidechain entries share the transcript file, and one assistant
# entry can hold several text blocks around tool calls — matching either of
# those made the hook block a visible message for words it never contained
# (the reported symptom: a block on the line "Seed hunt at 4 of 32."). The extractor
# therefore drops `isSidechain: true` entries and, within the chosen entry,
# keeps only the text blocks after the last tool_use. Both filters are written
# to fail *open* (absent field / no tool_use => today's behaviour), so a renamed
# transcript field degrades to "unchanged", never to "hook disabled".
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

# Extract the main agent's own trailing text from the JSONL transcript (#2650).
#
#   select(.isSidechain != true)  — drop subagent turns, which are appended to
#       the same transcript file. `!= true` (not `== false`) so an entry with no
#       isSidechain field is kept: absent field => unchanged behaviour.
#   rindex(true) over tool_use    — within the chosen entry, keep only the text
#       blocks after the last tool call. A turn's pre-tool-call narration is not
#       the message the user is looking at when the Stop hook fires. No tool_use
#       in the content array => the whole array is used, i.e. unchanged.
LAST_RESPONSE=$(jq -Rs '
    split("\n")
    | map(select(length > 0))
    | map(try fromjson catch null)
    | map(select(. != null))
    | map(select(.message.role == "assistant"))
    | map(select(.isSidechain != true))
    | last
    | if . == null then "" else
        (.message.content
         | if type == "string" then .
           else
             (. as $blocks
              | ($blocks | map(.type == "tool_use") | rindex(true)) as $last_tool
              | if $last_tool == null then $blocks else $blocks[($last_tool + 1):] end)
             | map(select(.type == "text") | .text)
             | join("\n")
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

# Message-branch selection (#2650). These two patterns do NOT gate the block —
# the matcher above stays exactly as broad as it was (#2574 control). They only
# choose *which* remediation text ships, because "restate as tokens / effort
# tier" is unusable advice for a render queue.
#
# Both must match, in either order: a numeric rate expression (N unit per thing)
# AND a word claiming the figure was measured. Requiring both keeps this
# conservative, and its two failure directions are both mild — a rate phrased
# unusually falls back to the generic message (today's behaviour), and prose
# that merely says "measured" near a rate gets machine-work guidance (a
# less-apt nudge, never an extra block).
PATTERN_RATE_UNIT="[0-9]+(\.[0-9]+)?[[:space:]]*(s|ms|sec|secs|second|seconds|min|mins|minute|minutes|h|hr|hrs|hour|hours)[[:space:]]*(/|per[[:space:]])[[:space:]]*[a-z]"
PATTERN_MEASUREMENT="(measured|measurement|median|average|benchmarked|observed|sampled|throughput)"

if echo "$LAST_RESPONSE" | grep -qiE "$PATTERN_FUTURE|$PATTERN_MARKER"; then
    REASON="Avoid quoting AI work in calendar time (hours, days, weeks, months) — it does not map to agent effort and consistently misleads. Restate the estimate as tokens consumed, effort tier (low / medium / high / xhigh / max), tool-call count, or files / lines to touch. Exception: external machine work you measured rather than paced yourself (a CI run, a build, a model download, a render, a long test suite) genuinely is wall-clock — state it as rate × quantity with the measurement named, e.g. \"3870 frames at a measured 1.0 s/frame, so about 65 minutes\"."

    if echo "$LAST_RESPONSE" | grep -qiE "$PATTERN_RATE_UNIT" \
        && echo "$LAST_RESPONSE" | grep -qiE "$PATTERN_MEASUREMENT"; then
        REASON="That names a measured rate, so it reads as external machine work you measured rather than paced yourself (a CI run, a build, a model download, a render, a long test suite). Wall-clock is the honest unit for that — keep it, but state it as rate × quantity with the measurement named, e.g. \"3870 frames at a measured 1.0 s/frame, so about 65 minutes\". A bare total hides whether the time is the hardware's or yours. If part of the figure is your own work rather than the machine's, restate that part as tokens consumed, tool-call count, or files / lines to touch."
    fi

    # shellcheck disable=SC2016  # jq expression, not shell expansion
    jq -n --arg reason "$REASON" '{"decision": "block", "reason": $reason}'
    exit 0
fi

exit 0
