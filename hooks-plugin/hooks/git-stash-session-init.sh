#!/usr/bin/env bash
# SessionStart hook - records git baselines for session-scoped tracking
#
# Two baselines are written, both keyed by session_id:
#   - stash baseline (used by git-stash-reminder.sh)
#   - HEAD commit baseline (used by test-verification.sh to skip when no
#     commits have landed since the session began)
#
# The script keeps its historical name for plugin.json compatibility even
# though it now records more than stashes.
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
STASH_BASELINE_DIR="/tmp/claude-stash-baselines"
mkdir -p "$STASH_BASELINE_DIR"
STASH_BASELINE_FILE="${STASH_BASELINE_DIR}/${SESSION_ID}"
git -C "$CWD" stash list --format='%H' 2>/dev/null > "$STASH_BASELINE_FILE" || true

# Record HEAD commit at session start. Used by test-verification.sh to skip
# the test run when HEAD has not advanced (no commits landed → nothing new
# to verify). Empty file if HEAD cannot be resolved (unborn branch, etc.).
TEST_BASELINE_DIR="/tmp/claude-test-baselines"
mkdir -p "$TEST_BASELINE_DIR"
TEST_BASELINE_FILE="${TEST_BASELINE_DIR}/${SESSION_ID}"
git -C "$CWD" rev-parse HEAD 2>/dev/null > "$TEST_BASELINE_FILE" || true

exit 0
