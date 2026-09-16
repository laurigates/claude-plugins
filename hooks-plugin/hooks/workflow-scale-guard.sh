#!/usr/bin/env bash
# PreToolUse hook for the Workflow tool — asks the user to confirm before a
# multi-agent workflow spawns more agents than the configured limit.
#
# Problem it prevents: a Workflow script's cost is set almost entirely by how
# many agents it creates, and that number is a property of the script's shape,
# not of the prompt that asked for it. Claude Code ships two things that look
# like they cover this and do not:
#
#   * `workflowSizeGuideline` is injected into the system prompt as advisory
#     text and ends with "This is a guideline, not a hard limit — follow it
#     unless the user's prompt calls for a different scale." A sweep-shaped
#     prompt reads exactly like a call for a different scale, so the model can
#     reason past it without ever being wrong on its face.
#   * `skipWorkflowUsageWarning` is a ONE-TIME acceptance ("whether the user has
#     accepted the multi-agent workflow usage warning"). Once set, auto mode
#     stops prompting before every workflow, at every scale, forever.
#
# Observed 2026-09-15: five Workflow runs in a single session spawned 496
# subagents against a `medium` guideline of 10, and cost $528 in one afternoon —
# 67% of the day's spend and ~8x the entire GitHub Actions bill. Nothing
# prompted, because the acceptance flag had been set months earlier. The spend
# was driven by cache CREATION (55.2M tokens at 1.25x input price): every fresh
# agent builds its own prompt cache and most do not live long enough to amortise
# it through reads.
#
# Strategy:
#   1. Guards: opt-out env var, jq/python3 availability, tool_name == Workflow.
#   2. Skip a resume (`resumeFromRunId`) — the original invocation was already
#      gated and a resume re-runs only what changed.
#   3. Obtain the script text: inline `script`, else read `scriptPath`. A saved
#      workflow referenced by `name` has no text here — fail open.
#   4. Hand the text to lib/workflow-scale-estimate.py, which returns a
#      KEY=VALUE rollup (VERDICT / ESTIMATE / SITES / SOURCE). Bounded fan-outs
#      are counted exactly; a fan-out over a runtime-length list is costed at
#      CLAUDE_HOOKS_WORKFLOW_ASSUMED_WIDTH items so the limit still governs it.
#   5. VERDICT=OVER_LIMIT -> `ask`, surfacing the estimate and the two cheap
#      remedies. Everything else exits 0 silently.
#
# ASK, NOT BLOCK — on purpose. The failure here is not "this workflow is
# forbidden", it is "nobody was asked". A hard block would force the agent to
# judge whether the scale is justified, which is the judgment it already got
# wrong; `ask` puts the number in front of the person paying for it and lets
# them approve in one keystroke. Declining returns the agent to the script with
# a concrete reason.
#
# Fails OPEN by design. Never asks: a script the analyzer cannot parse, a saved
# workflow with no inline script, a resume, an absent python3/jq, or any script
# whose agent() sites are all bounded and within the limit. Template-literal
# interpolations are treated as string content, so an agent() call written
# inside one is invisible — prompts live in templates, calls do not.
#
# Tunables (read from the hook's own process environment):
#   CLAUDE_HOOKS_WORKFLOW_MAX_AGENTS      limit before asking (default 10)
#   CLAUDE_HOOKS_WORKFLOW_ASSUMED_WIDTH   items per unbounded fan-out (default 8)
#   CLAUDE_HOOKS_DISABLE_WORKFLOW_SCALE_GUARD=1   disable entirely
#
# The agent cannot set these for this process: a hook runs as its own process
# spawned by Claude Code with the session environment, so there is no inline
# prefix that reaches it. Raising the limit is an operator action — exporting it
# from a shell, or editing settings — which is visible and reviewable.

set -uo pipefail

[ "${CLAUDE_HOOKS_DISABLE_WORKFLOW_SCALE_GUARD:-0}" = "1" ] && exit 0
command -v jq >/dev/null 2>&1 || exit 0
command -v python3 >/dev/null 2>&1 || exit 0

PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
ESTIMATOR="$PLUGIN_ROOT/hooks/workflow-scale-estimate.py"
[ -f "$ESTIMATOR" ] || ESTIMATOR="$(dirname "${BASH_SOURCE[0]}")/lib/workflow-scale-estimate.py"
[ -f "$ESTIMATOR" ] || exit 0

INPUT=$(cat)
[ -n "$INPUT" ] || exit 0

TOOL_NAME=$(printf '%s' "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null)
[ "$TOOL_NAME" = "Workflow" ] || exit 0

RESUME=$(printf '%s' "$INPUT" | jq -r '.tool_input.resumeFromRunId // empty' 2>/dev/null)
[ -n "$RESUME" ] && exit 0

SCRIPT_TEXT=$(printf '%s' "$INPUT" | jq -r '.tool_input.script // empty' 2>/dev/null)
if [ -z "$SCRIPT_TEXT" ]; then
    SCRIPT_PATH=$(printf '%s' "$INPUT" | jq -r '.tool_input.scriptPath // empty' 2>/dev/null)
    if [ -n "$SCRIPT_PATH" ] && [ -f "$SCRIPT_PATH" ]; then
        SCRIPT_TEXT=$(cat "$SCRIPT_PATH" 2>/dev/null)
    fi
fi
[ -n "$SCRIPT_TEXT" ] || exit 0

LIMIT="${CLAUDE_HOOKS_WORKFLOW_MAX_AGENTS:-10}"
WIDTH="${CLAUDE_HOOKS_WORKFLOW_ASSUMED_WIDTH:-8}"
case "$LIMIT" in ''|*[!0-9]*) LIMIT=10 ;; esac
case "$WIDTH" in ''|*[!0-9]*) WIDTH=8 ;; esac

ROLLUP=$(printf '%s' "$SCRIPT_TEXT" | python3 "$ESTIMATOR" "$LIMIT" "$WIDTH" 2>/dev/null) || exit 0
[ -n "$ROLLUP" ] || exit 0

field() { printf '%s\n' "$ROLLUP" | grep "^$1=" | head -1 | cut -d= -f2-; }

VERDICT=$(field VERDICT)
[ "$VERDICT" = "OVER_LIMIT" ] || exit 0

ESTIMATE=$(field ESTIMATE)
SITES=$(field SITES)
SOURCE=$(field SOURCE)
NAME=$(printf '%s' "$INPUT" | jq -r '.tool_input.name // empty' 2>/dev/null)
[ -n "$NAME" ] || NAME=$(field NAME)
[ -n "$NAME" ] || NAME=$(printf '%s' "$SCRIPT_TEXT" | grep -o "name:[[:space:]]*'[^']*'" | head -1 | cut -d"'" -f2)
[ -n "$NAME" ] || NAME="(unnamed)"

REASON="This workflow is estimated to spawn ~${ESTIMATE} agents, over the limit of ${LIMIT}.

  workflow:  ${NAME}
  agent() call sites: ${SITES}"

if [ -n "$SOURCE" ]; then
    REASON="${REASON}
  unbounded fan-out over: ${SOURCE}  (costed at ${WIDTH} items each)"
fi

REASON="${REASON}

Agent count is what sets a workflow's cost, and most of it is prompt-cache
creation: every fresh agent builds its own cache, and short-lived ones never
read it back. A run of this size is worth a deliberate yes.

Cheaper shapes, if the scale is not actually needed:
  - cap the fan-out where its length is decided, e.g. .slice(0, 6) — the
    estimator reads an explicit cap as the bound
  - reduce agents per item: reuse one agent across stages rather than one
    agent per stage per item

Approve to run it as written."

printf '%s' "$REASON" | jq -Rs '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"ask",permissionDecisionReason:.}}'
exit 0
