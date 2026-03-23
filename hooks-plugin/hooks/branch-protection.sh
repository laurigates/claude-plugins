#!/usr/bin/env bash
# PreToolUse hook — guards write operations on protected branches (main, master)
#
# Behavior:
#   - Common operations (commit, push, add): denied with guidance for Claude
#     to consider branching. Claude can override by prefixing the command with
#     CLAUDE_HOOKS_DISABLE_BRANCH_PROTECTION=1 after evaluating the context.
#   - Destructive operations (reset, rebase): prompts user to approve via "ask"
#   - Read-only operations: always allowed silently
#
# Toggle: set CLAUDE_HOOKS_DISABLE_BRANCH_PROTECTION=1 to skip this hook entirely
#
# Matches: Bash
# Detects: git commit, git push, git rebase on main/master
# Allows: read-only git operations, git merge (local, reversible)

set -euo pipefail

# Toggle off via environment variable
[ "${CLAUDE_HOOKS_DISABLE_BRANCH_PROTECTION:-}" = "1" ] && exit 0

INPUT=$(cat)

TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // empty')
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty')

# Only applies to Bash tool
[ "$TOOL_NAME" != "Bash" ] && exit 0
[ -z "$COMMAND" ] && exit 0

# Allow inline override: CLAUDE_HOOKS_DISABLE_BRANCH_PROTECTION=1 git ...
if echo "$COMMAND" | grep -Eq '(^|\s)CLAUDE_HOOKS_DISABLE_BRANCH_PROTECTION=1\s+'; then
  exit 0
fi

# Only check git commands
echo "$COMMAND" | grep -Eq '^\s*git\s+' || exit 0

# Deny with guidance — Claude sees the reason and decides to branch or override
deny() {
  local reason="$1"
  local json_reason
  json_reason=$(printf '%s' "$reason" | jq -Rs .)
  cat <<EOF
{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":${json_reason}}}
EOF
  exit 0
}

# Prompt the user to approve or deny — for destructive operations
ask() {
  local reason="$1"
  local json_reason
  json_reason=$(printf '%s' "$reason" | jq -Rs .)
  cat <<EOF
{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"ask","permissionDecisionReason":${json_reason}}}
EOF
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
# Deny (with guidance): commit, push, cherry-pick, revert, add/rm/mv, stash pop/apply
# Ask (user approves): rebase, reset

# Extract the git subcommand (handle global flags like -C <path>)
GIT_SUBCMD=$(echo "$COMMAND" | grep -oE 'git\s+(-[A-Za-z]\s+\S+\s+)*[a-z-]+' | awk '{print $NF}' || true)

case "$GIT_SUBCMD" in
  # Read-only operations — always allowed
  status|diff|log|show|branch|remote|fetch|pull|stash|tag|blame|shortlog|describe|ls-files|ls-tree|rev-parse|rev-list|name-rev|reflog)
    # Allow stash list but guard stash pop/apply/drop
    if [ "$GIT_SUBCMD" = "stash" ]; then
      if echo "$COMMAND" | grep -Eq 'stash\s+(pop|apply|drop|clear)'; then
        STASH_OP=$(echo "$COMMAND" | grep -oE '(pop|apply|drop|clear)')
        deny "You're on '${CURRENT_BRANCH}'. Consider switching to a feature branch before 'git stash ${STASH_OP}'. If committing to ${CURRENT_BRANCH} is intentional, re-run with: CLAUDE_HOOKS_DISABLE_BRANCH_PROTECTION=1 git stash ${STASH_OP}"
      fi
    fi
    exit 0
    ;;
  # Merge — allowed on protected branches (local, reversible operation)
  merge)
    exit 0
    ;;
  # Destructive operations — require explicit user approval
  rebase|reset)
    ask "You're about to run 'git ${GIT_SUBCMD}' on '${CURRENT_BRANCH}'. This is a destructive operation on a protected branch. Approve to proceed, or deny to work on a feature branch instead."
    ;;
  # Common write operations — deny with guidance for Claude
  commit|cherry-pick|revert)
    deny "You're on '${CURRENT_BRANCH}'. If this repo uses PR workflows, create a feature branch: git checkout -b feature/your-change. If committing directly to ${CURRENT_BRANCH} is appropriate (e.g. personal repo, dotfiles), re-run with: CLAUDE_HOOKS_DISABLE_BRANCH_PROTECTION=1 git ${GIT_SUBCMD} ..."
    ;;
  push)
    # Allow push to specific remote branch via explicit refspec
    if echo "$COMMAND" | grep -q ':'; then
      exit 0
    fi
    deny "You're about to push directly to '${CURRENT_BRANCH}'. In collaborative repos, changes go through a PR on a feature branch. If pushing to ${CURRENT_BRANCH} is intentional, re-run with: CLAUDE_HOOKS_DISABLE_BRANCH_PROTECTION=1 git push ..."
    ;;
  # Staging operations
  add|rm|mv|restore|checkout|switch)
    # Allow checkout/switch to another branch
    if [ "$GIT_SUBCMD" = "checkout" ] || [ "$GIT_SUBCMD" = "switch" ]; then
      exit 0
    fi
    # Allow restore (it's a safety operation)
    if [ "$GIT_SUBCMD" = "restore" ]; then
      exit 0
    fi
    # Staging implies committing — deny with guidance
    deny "You're staging changes on '${CURRENT_BRANCH}'. If this repo uses PR workflows, switch to a feature branch: git checkout -b feature/your-change. If committing to ${CURRENT_BRANCH} is intentional, re-run with: CLAUDE_HOOKS_DISABLE_BRANCH_PROTECTION=1 git ${GIT_SUBCMD} ..."
    ;;
esac

exit 0
