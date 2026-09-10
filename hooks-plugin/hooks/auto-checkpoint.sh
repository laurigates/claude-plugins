#!/usr/bin/env bash
# PreToolUse hook — auto-creates a git stash checkpoint before destructive operations
#
# Toggle: set CLAUDE_HOOKS_DISABLE_AUTO_CHECKPOINT=1 to skip this hook
#
# Matches: Bash
# Triggers on: git reset, git checkout -- (file restore), rm -rf, file overwrites
# Creates: a named git stash as a recovery checkpoint

set -euo pipefail

# Toggle off
[ "${CLAUDE_HOOKS_DISABLE_AUTO_CHECKPOINT:-}" = "1" ] && exit 0

INPUT=$(cat)

TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // empty')
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty')

# Only applies to Bash tool
[ "$TOOL_NAME" != "Bash" ] && exit 0
[ -z "$COMMAND" ] && exit 0

# Must be in a git repo
git rev-parse --is-inside-work-tree >/dev/null 2>&1 || exit 0

# Check if there are uncommitted changes worth checkpointing
has_changes() {
  [ -n "$(git status --porcelain 2>/dev/null)" ]
}

create_checkpoint() {
  local reason="$1"
  if has_changes; then
    local timestamp commit
    timestamp=$(date '+%Y%m%d-%H%M%S' 2>/dev/null || date '+%s')
    commit=$(git stash create --include-untracked 2>/dev/null || true)
    if [ -n "$commit" ]; then
      if git stash store -m "auto-checkpoint before ${reason} (${timestamp})" "$commit" 2>/dev/null; then
        echo "Created checkpoint stash before ${reason}. Recover with: git stash list" >&2
      fi
    fi
  fi
}

# Detect destructive operations and checkpoint before allowing them

# git reset (any form)
if echo "$COMMAND" | grep -Eq '^\s*git\s+reset\b'; then
  create_checkpoint "git reset"
  exit 0
fi

# git checkout -- <files> (discarding changes)
if echo "$COMMAND" | grep -Eq 'git\s+checkout\s+--\s+'; then
  create_checkpoint "git checkout file restore"
  exit 0
fi

# git restore (discarding changes)
if echo "$COMMAND" | grep -Eq 'git\s+restore\s+' && ! echo "$COMMAND" | grep -q -- '--staged'; then
  create_checkpoint "git restore"
  exit 0
fi

# rm -rf with multiple files or directories (not just build artifacts)
if echo "$COMMAND" | grep -Eq 'rm\s+(-rf|-fr)\s+' && \
   ! echo "$COMMAND" | grep -Eq 'rm\s+(-rf|-fr)\s+(node_modules|dist|build|\.next|\.cache|__pycache__|\.pytest_cache|target|\.build)\b'; then
  create_checkpoint "rm -rf"
  exit 0
fi

# git clean (removes untracked files)
if echo "$COMMAND" | grep -Eq 'git\s+clean\s+-[a-z]*f'; then
  create_checkpoint "git clean"
  exit 0
fi

exit 0
