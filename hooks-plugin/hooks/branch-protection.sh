#!/usr/bin/env bash
# PreToolUse hook — guards write operations on protected branches (main, master)
#
# Behavior:
#   - Common operations (commit, push, add): prompts user to approve via "ask"
#   - Destructive operations (reset, rebase): hard-blocked via "deny"
#   - Read-only operations: always allowed silently
#
# Toggle: set CLAUDE_HOOKS_DISABLE_BRANCH_PROTECTION=1 to skip this hook
#
# Matches: Bash
# Detects: git commit, git push, git rebase on main/master
# Allows: read-only git operations, git merge (local, reversible)

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

# Prompt the user to approve or deny — soft guard for common operations
ask() {
  local reason="$1"
  # Use jq to safely escape the reason string into JSON
  local json_reason
  json_reason=$(printf '%s' "$reason" | jq -Rs .)
  cat <<ASKEOF
{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"ask","permissionDecisionReason":${json_reason}}}
ASKEOF
  exit 0
}

# Get current branch (silently fail if not in a git repo)
CURRENT_BRANCH=$(git branch --show-current 2>/dev/null || echo "")
[ -z "$CURRENT_BRANCH" ] && exit 0

# Only protect main and master
if [ "$CURRENT_BRANCH" != "main" ] && [ "$CURRENT_BRANCH" != "master" ]; then
  exit 0
fi

# Protected branches: guard write operations
# Allow: status, diff, log, show, branch (list), remote, fetch, pull, stash list, tag (list), merge
# Ask (user approves): commit, push, cherry-pick, revert, add/rm/mv, stash pop/apply
# Block (hard deny): rebase, reset

# Extract the git subcommand (handle global flags like -C <path>)
GIT_SUBCMD=$(echo "$COMMAND" | grep -oE 'git\s+(-[A-Za-z]\s+\S+\s+)*[a-z-]+' | awk '{print $NF}' || true)

case "$GIT_SUBCMD" in
  # Read-only operations — always allowed
  status|diff|log|show|branch|remote|fetch|pull|stash|tag|blame|shortlog|describe|ls-files|ls-tree|rev-parse|rev-list|name-rev|reflog)
    # Allow stash list but block stash pop/apply/drop
    if [ "$GIT_SUBCMD" = "stash" ]; then
      if echo "$COMMAND" | grep -Eq 'stash\s+(pop|apply|drop|clear)'; then
        STASH_OP=$(echo "$COMMAND" | grep -oE '(pop|apply|drop|clear)')
        ask "You're about to run 'git stash ${STASH_OP}' on '${CURRENT_BRANCH}'. Consider switching to a feature branch if this repo uses PR workflows."
      fi
    fi
    exit 0
    ;;
  # Merge — allowed on protected branches (local, reversible operation)
  merge)
    exit 0
    ;;
  # Destructive history rewrites — hard-blocked on protected branches
  rebase)
    block "BLOCKED: 'git rebase' on protected branch '$CURRENT_BRANCH'.
Rebasing a protected branch rewrites shared history.
Switch to a feature branch first: git checkout -b feature/your-change
Set CLAUDE_HOOKS_DISABLE_BRANCH_PROTECTION=1 to override."
    ;;
  # Common write operations — prompt user to approve
  commit|cherry-pick|revert)
    ask "You're about to run 'git ${GIT_SUBCMD}' on '${CURRENT_BRANCH}'. If this repo uses PR workflows, consider creating a feature branch first: git checkout -b feature/your-change"
    ;;
  push)
    # Allow push to specific remote branch via explicit refspec
    if echo "$COMMAND" | grep -q ':'; then
      exit 0
    fi
    ask "You're about to push directly to '${CURRENT_BRANCH}'. In collaborative repos, changes usually go through a PR on a feature branch. Approve to push, or deny to create a branch instead."
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
    # Staging operations — prompt user since they imply committing on protected branch
    ask "You're about to run 'git ${GIT_SUBCMD}' on '${CURRENT_BRANCH}'. If this repo uses PR workflows, consider switching to a feature branch first: git checkout -b feature/your-change"
    ;;
esac

exit 0
