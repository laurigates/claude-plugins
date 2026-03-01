#!/bin/bash
# Development hook — logs all hook events to a file for debugging
#
# Toggle: set CLAUDE_HOOKS_ENABLE_EVENT_LOGGER=1 to enable (disabled by default)
#
# Matches: all events (matcher: "")
# Output: ~/.claude/hook-events.log
#
# Use this to understand what data flows through hooks while developing your own.

# Disabled by default — opt-in only
[ "${CLAUDE_HOOKS_ENABLE_EVENT_LOGGER:-}" != "1" ] && exit 0

INPUT=$(cat)
LOG_FILE="${CLAUDE_HOOKS_EVENT_LOG:-$HOME/.claude/hook-events.log}"

# Ensure log directory exists
mkdir -p "$(dirname "$LOG_FILE")"

TIMESTAMP=$(date -Iseconds 2>/dev/null || date '+%Y-%m-%dT%H:%M:%S')
EVENT=$(echo "$INPUT" | jq -r '.hook_event_name // "unknown"')
TOOL=$(echo "$INPUT" | jq -r '.tool_name // "-"')
SESSION=$(echo "$INPUT" | jq -r '.session_id // "-"' | head -c 12)

# Compact summary line
SUMMARY="${TIMESTAMP} | ${EVENT} | tool=${TOOL} | session=${SESSION}"

# Log tool input for PreToolUse/PostToolUse (abbreviated)
if [ "$EVENT" = "PreToolUse" ] || [ "$EVENT" = "PostToolUse" ]; then
  CMD=$(echo "$INPUT" | jq -r '.tool_input.command // .tool_input.file_path // "-"' | head -c 80)
  SUMMARY="${SUMMARY} | input=${CMD}"
fi

echo "$SUMMARY" >> "$LOG_FILE"

# Optionally log full JSON (verbose mode)
if [ "${CLAUDE_HOOKS_EVENT_LOGGER_VERBOSE:-}" = "1" ]; then
  echo "--- FULL INPUT ---" >> "$LOG_FILE"
  echo "$INPUT" | jq -c '.' >> "$LOG_FILE" 2>/dev/null || echo "$INPUT" >> "$LOG_FILE"
  echo "--- END ---" >> "$LOG_FILE"
fi

exit 0
