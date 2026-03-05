#!/usr/bin/env bash
# Stop hook - reminds about git stashes created DURING the current session
# Uses a baseline file written by git-stash-session-init.sh at SessionStart
# to distinguish session stashes from pre-existing ones
set -euo pipefail

# Read JSON input from stdin and extract fields
INPUT=$(cat)
CWD=$(echo "$INPUT" | jq -r '.cwd // empty')
SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // empty')
STOP_HOOK_ACTIVE=$(echo "$INPUT" | jq -r '.stop_hook_active // false')

# Guard: stop_hook_active - prevent infinite loops
# When Claude is already acting on a previous stop hook's feedback,
# do not block again
if [ "$STOP_HOOK_ACTIVE" = "true" ]; then
    exit 0
fi

# Guard: no working directory provided
if [ -z "$CWD" ]; then
    exit 0
fi

# Guard: not a git repository
if ! git -C "$CWD" rev-parse --git-dir >/dev/null 2>&1; then
    exit 0
fi

# Guard: no stashes exist at all (fast path)
CURRENT_STASHES=$(git -C "$CWD" stash list --format='%H|%gd|%ct|%gs' 2>/dev/null || true)
if [ -z "$CURRENT_STASHES" ]; then
    exit 0
fi

# Sanitize session_id (keep only alnum, hyphens, underscores)
SESSION_ID=$(echo "$SESSION_ID" | tr -cd 'a-zA-Z0-9_-')

# Load baseline (stash hashes that existed at session start)
BASELINE_FILE="/tmp/claude-stash-baselines/${SESSION_ID}"
BASELINE_HASHES=""
if [ -n "$SESSION_ID" ] && [ -f "$BASELINE_FILE" ]; then
    BASELINE_HASHES=$(cat "$BASELINE_FILE" 2>/dev/null || true)
fi

# If no baseline file exists (e.g., plugin just installed mid-session),
# exit silently to avoid false positives on first use
if [ -z "$SESSION_ID" ] || [ ! -f "$BASELINE_FILE" ]; then
    exit 0
fi

# Compare: find stashes whose hashes are NOT in the baseline
NOW=$(date +%s)
NEW_STASHES=""
NEW_COUNT=0

while IFS='|' read -r hash ref ts subject; do
    [ -z "$hash" ] && continue
    [ -z "$ts" ] && continue

    # Skip stashes that existed at session start (in the baseline)
    if [ -n "$BASELINE_HASHES" ] && echo "$BASELINE_HASHES" | grep -qF "$hash" 2>/dev/null; then
        continue
    fi

    # This is a new stash created during the session
    NEW_COUNT=$((NEW_COUNT + 1))
    AGE=$((NOW - ts))
    HOURS=$((AGE / 3600))
    MINS=$(( (AGE % 3600) / 60 ))
    if [ "$HOURS" -gt 0 ]; then
        AGE_STR="${HOURS}h ${MINS}m ago"
    else
        AGE_STR="${MINS}m ago"
    fi
    NEW_STASHES="${NEW_STASHES}  ${ref} (${AGE_STR}): ${subject} → git stash pop\n"
done <<< "$CURRENT_STASHES"

# No new stashes → exit silently
if [ "$NEW_COUNT" -eq 0 ]; then
    exit 0
fi

# Build the reason message for new session stashes only
REASON="Found ${NEW_COUNT} git stash(es) created during this session in ${CWD}. Review before exiting:\n"
REASON="${REASON}\nSession stashes — pop or apply them:\n${NEW_STASHES}"
REASON="${REASON}\nRun 'git stash list' to inspect, or 'git stash show -p stash@{N}' to review contents."

# Output block decision with proper JSON escaping via jq
FORMATTED_REASON=$(printf '%b' "$REASON")
jq -n --arg reason "$FORMATTED_REASON" '{"decision": "block", "reason": $reason}'
