#!/bin/bash
# Stop hook - commits staged changes, switches to main/master, and pulls
# Runs after each Claude response in a git repository
set -euo pipefail

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

# Commit staged changes if any exist
STAGED=$(git -C "$CWD" diff --cached --name-only 2>/dev/null || true)
if [ -n "$STAGED" ]; then
    git -C "$CWD" commit -m "chore: auto-commit staged changes" >/dev/null 2>&1 || true
fi

# Detect main branch (main preferred, fall back to master)
MAIN_BRANCH=""
if git -C "$CWD" show-ref --verify --quiet refs/heads/main 2>/dev/null; then
    MAIN_BRANCH="main"
elif git -C "$CWD" show-ref --verify --quiet refs/heads/master 2>/dev/null; then
    MAIN_BRANCH="master"
fi

# No main/master branch found — nothing more to do
if [ -z "$MAIN_BRANCH" ]; then
    exit 0
fi

# Switch to main branch if not already on it
CURRENT_BRANCH=$(git -C "$CWD" branch --show-current 2>/dev/null || true)
if [ "$CURRENT_BRANCH" != "$MAIN_BRANCH" ]; then
    git -C "$CWD" switch "$MAIN_BRANCH" >/dev/null 2>&1 || true
fi

# Pull latest changes
git -C "$CWD" pull --ff-only >/dev/null 2>&1 || true

exit 0
