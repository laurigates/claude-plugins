#!/usr/bin/env bash
# SessionEnd hook - cleans up session temp files
# Runs when a Claude Code session ends
set -euo pipefail

# Read JSON input from stdin and extract working directory
INPUT=$(cat)

# Clean up stash baseline file for this session
SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // empty')
SESSION_ID=$(echo "$SESSION_ID" | tr -cd 'a-zA-Z0-9_-')
if [ -n "$SESSION_ID" ]; then
    rm -f "/tmp/claude-stash-baselines/${SESSION_ID}" 2>/dev/null || true
fi

exit 0
