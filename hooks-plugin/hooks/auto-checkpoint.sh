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
    local timestamp commit new_tree old_tree prev_msg
    timestamp=$(date '+%Y%m%d-%H%M%S' 2>/dev/null || date '+%s')
    commit=$(git stash create --include-untracked 2>/dev/null || true)
    if [ -n "$commit" ]; then
      # Skip storing a checkpoint whose tree is identical to the one already
      # sitting at stash@{0} as an auto-checkpoint (issue #2736, the #2652
      # pattern: 50 checkpoints in one session holding three distinct trees).
      # A duplicate binds no additional content — the reminder would only
      # hand the user and the auto-mode classifier one more entry neither can
      # clear. The provenance guard matters: a HAND-made stash at stash@{0}
      # is not checked for equality — the session may have stashed something
      # it intends to restore deliberately, and its tree equality says
      # nothing about what this session's destructive command needs the
      # checkpoint to protect.
      # Both comparisons fail toward STORING: a missing/odd stash@{0}, an
      # unreadable tree, or a `stash list` that comes back empty all fall
      # through to the store, matching the original behaviour exactly.
      prev_msg=$(git stash list --format='%gs' 2>/dev/null | sed -n '1p' || true)
      case "$prev_msg" in
        "auto-checkpoint before "*)
          new_tree=$(git rev-parse --quiet --verify "${commit}^{tree}" 2>/dev/null || true)
          old_tree=$(git rev-parse --quiet --verify 'stash@{0}^{tree}' 2>/dev/null || true)
          if [ -n "$new_tree" ] && [ "$new_tree" = "$old_tree" ]; then
            # Quiet by design: a skipped checkpoint is not user-actionable
            # (nothing is wrong; the protection is already in place), and
            # stderr from a PreToolUse hook reaches the agent's context for
            # every command in a loop — the exact noise this hook fights.
            return 0
          fi
          ;;
      esac
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
