#!/bin/bash
# SessionStart hook - records current git stash hashes as a session baseline
# Used by git-stash-reminder.sh to only flag stashes created during this session
set -euo pipefail

# Read JSON input from stdin and extract fields
INPUT=$(cat)
CWD=$(echo "$INPUT" | jq -r '.cwd // empty')
SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // empty')

# Sanitize session_id to prevent path traversal (keep only alnum, hyphens, underscores)
SESSION_ID=$(echo "$SESSION_ID" | tr -cd 'a-zA-Z0-9_-')

# Guard: no working directory or session ID
if [ -z "$CWD" ] || [ -z "$SESSION_ID" ]; then
    exit 0
fi

# Guard: not a git repository
if ! git -C "$CWD" rev-parse --git-dir >/dev/null 2>&1; then
    exit 0
fi

# Record current stash commit hashes as the session baseline
# Uses %H (full commit hash) because stash indices (%gd) shift when stashes
# are added or removed. Hashes are stable identifiers.
BASELINE_DIR="/tmp/claude-stash-baselines"
mkdir -p "$BASELINE_DIR"
BASELINE_FILE="${BASELINE_DIR}/${SESSION_ID}"

# Write all current stash hashes, one per line (empty file if no stashes)
git -C "$CWD" stash list --format='%H' 2>/dev/null > "$BASELINE_FILE" || true

exit 0
