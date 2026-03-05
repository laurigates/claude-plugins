#!/usr/bin/env bash
# Stop hook - surfaces pending todos before Claude exits and suggests GitHub issue creation
# Fires when the main agent finishes a response; blocks if unfinished todos exist so Claude
# can offer to create GitHub issues before the user ends the session.
#
# Install via /hooks:session-end-issue-hook or manually add to .claude/settings.json:
#   "Stop": [{"matcher":"*","hooks":[{"type":"command","command":"bash <path>/session-end-issue-hook.sh","timeout":15}]}]
set -euo pipefail

# Read JSON input from stdin
INPUT=$(cat)
TRANSCRIPT_PATH=$(echo "$INPUT" | jq -r '.transcript_path // empty')
CWD=$(echo "$INPUT" | jq -r '.cwd // empty')

# Guard: no transcript path provided
if [ -z "$TRANSCRIPT_PATH" ]; then
    exit 0
fi

# Guard: transcript file does not exist
if [ ! -f "$TRANSCRIPT_PATH" ]; then
    exit 0
fi

# Guard: jq not available (required for transcript parsing)
if ! command -v jq >/dev/null 2>&1; then
    exit 0
fi

# Parse the transcript (JSONL format: one JSON object per line).
# Find the LAST TodoWrite call and extract any todos with status pending or in_progress.
# Using jq -Rs to read the whole file as a single string, split on newlines, parse each
# line as JSON, then filter for TodoWrite tool_use blocks.
PENDING_TODOS=$(jq -Rs '
    split("\n")
    | map(select(length > 0))
    | map(try fromjson catch null)
    | map(select(. != null))
    | [
        .[].content[]?
        | select(type == "object")
        | select(.type == "tool_use")
        | select(.name == "TodoWrite")
      ]
    | last
    | if . == null then [] else (.input.todos // []) end
    | .[]?
    | select(.status == "pending" or .status == "in_progress")
    | .content
' "$TRANSCRIPT_PATH" 2>/dev/null || true)

# Guard: no pending todos
if [ -z "$PENDING_TODOS" ]; then
    exit 0
fi

# Count pending todos
TODO_COUNT=$(echo "$PENDING_TODOS" | jq -Rs 'split("\n") | map(select(length > 0)) | length')

# Build the gh issue create suggestion lines
GH_COMMANDS=""
while IFS= read -r todo; do
    [ -z "$todo" ] && continue
    # Strip surrounding quotes that jq adds to string values
    CLEAN=$(echo "$todo" | jq -r '.')
    GH_COMMANDS="${GH_COMMANDS}  gh issue create --title $(printf '%q' "$CLEAN") --label claude-deferred\n"
done <<< "$PENDING_TODOS"

# Build the block reason
REASON="Found ${TODO_COUNT} unfinished todo(s) at session end. Before finishing, consider creating GitHub issues for deferred work:\n"
REASON="${REASON}\nPending todos:\n"
while IFS= read -r todo; do
    [ -z "$todo" ] && continue
    CLEAN=$(echo "$todo" | jq -r '.')
    REASON="${REASON}  • ${CLEAN}\n"
done <<< "$PENDING_TODOS"

REASON="${REASON}\nSuggested commands (run or offer to run):\n${GH_COMMANDS}"
REASON="${REASON}\nAlternatively, mark todos as completed or cancelled if they are no longer relevant."

# Output block decision with proper JSON escaping via jq
FORMATTED_REASON=$(printf '%b' "$REASON")
jq -n --arg reason "$FORMATTED_REASON" '{"decision": "block", "reason": $reason}'
