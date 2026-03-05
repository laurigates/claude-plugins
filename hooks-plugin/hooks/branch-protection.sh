#!/usr/bin/env bash
# PreToolUse hook — blocks write operations on protected branches (main, master)
#
# Toggle: set CLAUDE_HOOKS_DISABLE_BRANCH_PROTECTION=1 to skip this hook
#
# Matches: Bash
# Detects: git commit, git push, git merge on main/master
# Allows: read-only git operations (status, diff, log, branch, etc.)

set -euo pipefail

# Toggle off
[ "${CLAUDE_HOOKS_DISABLE_BRANCH_PROTECTION:-}" = "1" ] && exit 0

INPUT=$(cat)

TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // empty')
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty')

# Only applies to Bash tool
[ "$TOOL_NAME" != "Bash" ] && exit 0
[ -z "$COMMAND" ] && exit 0

# Only check git commands
echo "$COMMAND" | grep -Eq '^\s*git\s+' || exit 0

block() {
  echo "$1" >&2
  exit 2
}

# Get current branch (silently fail if not in a git repo)
CURRENT_BRANCH=$(git branch --show-current 2>/dev/null || echo "")
[ -z "$CURRENT_BRANCH" ] && exit 0

# Only protect main and master
if [ "$CURRENT_BRANCH" != "main" ] && [ "$CURRENT_BRANCH" != "master" ]; then
  exit 0
fi

# Protected branches: block write operations
# Allow: status, diff, log, show, branch (list), remote, fetch, pull, stash list, tag (list)
# Block: commit, push, merge, rebase, reset, cherry-pick, revert, stash pop/apply

# Extract the git subcommand (handle global flags like -C <path>)
GIT_SUBCMD=$(echo "$COMMAND" | grep -oE 'git\s+(-[A-Za-z]\s+\S+\s+)*[a-z-]+' | awk '{print $NF}' || true)

case "$GIT_SUBCMD" in
  # Read-only operations — always allowed
  status|diff|log|show|branch|remote|fetch|pull|stash|tag|blame|shortlog|describe|ls-files|ls-tree|rev-parse|rev-list|name-rev|reflog)
    # Allow stash list but block stash pop/apply/drop
    if [ "$GIT_SUBCMD" = "stash" ]; then
      if echo "$COMMAND" | grep -Eq 'stash\s+(pop|apply|drop|clear)'; then
        block "BLOCKED: 'git stash $( echo "$COMMAND" | grep -oE '(pop|apply|drop|clear)')' on protected branch '$CURRENT_BRANCH'.
Switch to a feature branch first: git checkout -b feature/your-change
Set CLAUDE_HOOKS_DISABLE_BRANCH_PROTECTION=1 to override."
      fi
    fi
    exit 0
    ;;
  # Write operations — blocked on protected branches
  commit|merge|rebase|cherry-pick|revert)
    block "BLOCKED: 'git $GIT_SUBCMD' on protected branch '$CURRENT_BRANCH'.
Create a feature branch first:
  git checkout -b feature/your-change
Then make your changes and push:
  git push -u origin feature/your-change
Set CLAUDE_HOOKS_DISABLE_BRANCH_PROTECTION=1 to override."
    ;;
  push)
    # Block push from protected branch (but allow push to specific remote branch via refspec)
    if echo "$COMMAND" | grep -q ':'; then
      # Explicit refspec like main:feature-branch — allow
      exit 0
    fi
    block "BLOCKED: 'git push' from protected branch '$CURRENT_BRANCH'.
Create a feature branch first, or use an explicit refspec:
  git push origin $CURRENT_BRANCH:feature/your-change
Set CLAUDE_HOOKS_DISABLE_BRANCH_PROTECTION=1 to override."
    ;;
  reset)
    block "BLOCKED: 'git reset' on protected branch '$CURRENT_BRANCH'.
This is a destructive operation on a protected branch.
Switch to a feature branch first: git checkout -b feature/your-change
Set CLAUDE_HOOKS_DISABLE_BRANCH_PROTECTION=1 to override."
    ;;
  # Staging operations — warn but allow (needed for branch switches)
  add|rm|mv|restore|checkout|switch)
    # Allow checkout/switch to another branch
    if [ "$GIT_SUBCMD" = "checkout" ] || [ "$GIT_SUBCMD" = "switch" ]; then
      exit 0
    fi
    # Allow restore (it's a safety operation)
    if [ "$GIT_SUBCMD" = "restore" ]; then
      exit 0
    fi
    # Block add/rm/mv as they imply committing on protected branch
    block "BLOCKED: 'git $GIT_SUBCMD' on protected branch '$CURRENT_BRANCH'.
Staging changes on a protected branch implies you'll commit here.
Switch to a feature branch first: git checkout -b feature/your-change
Set CLAUDE_HOOKS_DISABLE_BRANCH_PROTECTION=1 to override."
    ;;
esac

exit 0
