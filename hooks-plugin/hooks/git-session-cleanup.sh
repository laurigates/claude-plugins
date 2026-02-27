#!/bin/bash
# SessionEnd hook - commits staged changes, switches to main/master, and pulls
# Runs when a Claude Code session ends in a git repository
#
# Safety: skips branch switch and pull when running inside a git worktree,
# because switching branches in a worktree could disrupt other sessions
# working in the main checkout or other worktrees.
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

# Detect if running inside a git worktree by comparing --git-dir and
# --git-common-dir. In a worktree these differ; in the main checkout
# they are the same.
GIT_DIR=$(git -C "$CWD" rev-parse --git-dir 2>/dev/null)
GIT_COMMON_DIR=$(git -C "$CWD" rev-parse --git-common-dir 2>/dev/null)
IS_WORKTREE=false
if [ "$GIT_DIR" != "$GIT_COMMON_DIR" ]; then
    IS_WORKTREE=true
fi

# Commit staged changes if any exist
STAGED=$(git -C "$CWD" diff --cached --name-only 2>/dev/null || true)
if [ -n "$STAGED" ]; then
    git -C "$CWD" commit -m "chore: auto-commit staged changes" >/dev/null 2>&1 || true
fi

# Skip branch switch and pull in worktrees — switching branches here would
# affect the main checkout, potentially disrupting other active sessions.
if [ "$IS_WORKTREE" = true ]; then
    exit 0
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
