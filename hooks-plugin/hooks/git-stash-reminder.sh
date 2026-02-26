#!/bin/bash
# Stop hook - reminds about orphaned git stashes before Claude exits
# Prevents stashes created during a session from being forgotten
set -euo pipefail

# Stash age threshold in seconds (2 hours)
STALE_THRESHOLD=7200

# Read JSON input from stdin and extract working directory
INPUT=$(cat)
CWD=$(echo "$INPUT" | jq -r '.cwd // empty')

# Guard: no working directory provided
if [ -z "$CWD" ]; then
    exit 0
fi

# Guard: not a git repository
if ! git -C "$CWD" rev-parse --git-dir >/dev/null 2>&1; then
    exit 0
fi

# Guard: no stashes exist
STASH_LIST=$(git -C "$CWD" stash list --format='%gd|%ct|%gs' 2>/dev/null || true)
if [ -z "$STASH_LIST" ]; then
    exit 0
fi

NOW=$(date +%s)
RECENT_STASHES=""
STALE_STASHES=""
TOTAL=0

while IFS='|' read -r ref ts subject; do
    [ -z "$ref" ] && continue
    TOTAL=$((TOTAL + 1))
    AGE=$((NOW - ts))

    if [ "$AGE" -lt "$STALE_THRESHOLD" ]; then
        HOURS=$((AGE / 3600))
        MINS=$(( (AGE % 3600) / 60 ))
        if [ "$HOURS" -gt 0 ]; then
            AGE_STR="${HOURS}h ${MINS}m ago"
        else
            AGE_STR="${MINS}m ago"
        fi
        RECENT_STASHES="${RECENT_STASHES}  ${ref} (${AGE_STR}): ${subject} → git stash pop\n"
    else
        DAYS=$((AGE / 86400))
        if [ "$DAYS" -gt 0 ]; then
            AGE_STR="${DAYS}d ago"
        else
            HOURS=$((AGE / 3600))
            AGE_STR="${HOURS}h ago"
        fi
        STALE_STASHES="${STALE_STASHES}  ${ref} (${AGE_STR}): ${subject} → git stash drop ${ref}\n"
    fi
done <<< "$STASH_LIST"

# Build the reason message
REASON="Found ${TOTAL} git stash(es) in ${CWD}. Review before exiting:\n"

if [ -n "$RECENT_STASHES" ]; then
    REASON="${REASON}\nRecent stashes (< 2h) — likely from this session, pop them:\n${RECENT_STASHES}"
fi

if [ -n "$STALE_STASHES" ]; then
    REASON="${REASON}\nStale stashes (>= 2h) — probably orphaned, consider dropping:\n${STALE_STASHES}"
fi

REASON="${REASON}\nRun 'git stash list' to inspect, or 'git stash show -p stash@{N}' to review contents."

# Output block decision with proper JSON escaping via jq
FORMATTED_REASON=$(printf '%b' "$REASON")
jq -n --arg reason "$FORMATTED_REASON" '{"decision": "block", "reason": $reason}'
