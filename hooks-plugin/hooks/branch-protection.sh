#!/usr/bin/env bash
# PreToolUse hook — guards write operations on protected branches (main, master)
#
# Behavior:
#   - Common operations (commit, push, add): denied with guidance to switch to
#     a feature branch, use an explicit-refspec push, or delegate to the user
#     per .claude/rules/handling-blocked-hooks.md.
#   - Destructive operations (reset, rebase): prompts user to approve via "ask"
#   - Read-only operations: always allowed silently
#
# Toggle: a human operator can export CLAUDE_HOOKS_DISABLE_BRANCH_PROTECTION=1
# in their shell environment (e.g. in a personal repo / dotfiles / main-branch-
# dev setup). The toggle is only honored when set in the process environment —
# inline prefixes like `CLAUDE_HOOKS_DISABLE_BRANCH_PROTECTION=1 git commit ...`
# on the command line are intentionally NOT honored so that agents cannot
# self-serve the bypass.
#
# Matches: Bash
# Detects: git commit, git push, git rebase on main/master
# Allows: read-only git operations, git merge (local, reversible), the initial
#         bootstrap push (a single root commit) that initializes a repo, a push
#         that explicitly names a non-protected target branch (e.g. git push -u
#         origin feat/x while parked on main — pushes feat/x, not main; #1600),
#         and any write in a GitHub wiki checkout (*.wiki, which renders only
#         master and supports no PRs; #1586)

set -euo pipefail

# Human-operator escape hatch: only honored when set in the process environment
# (not when prefixed inline on the command). See header comment for rationale.
[ "${CLAUDE_HOOKS_DISABLE_BRANCH_PROTECTION:-}" = "1" ] && exit 0

INPUT=$(cat)

TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // empty')
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty')
# The directory the Bash command actually runs in. In a git worktree this is
# the worktree path (with its own per-worktree HEAD), not the main checkout —
# so the branch lookup must run here, not in the hook's own process cwd, or a
# correctly-branched worktree gets misread as `main`. See #1695.
HOOK_CWD=$(echo "$INPUT" | jq -r '.cwd // empty')

# Only applies to Bash tool
[ "$TOOL_NAME" != "Bash" ] && exit 0
[ -z "$COMMAND" ] && exit 0

# Only check git commands. Allow any number of leading `VAR=value` assignments
# before the `git` invocation so that an attempt to inline-bypass via
# `CLAUDE_HOOKS_DISABLE_BRANCH_PROTECTION=1 git ...` is still treated as a git
# command (and therefore subject to the protections below) rather than slipping
# past this filter as "not a git command".
echo "$COMMAND" | grep -Eq '^\s*([A-Za-z_][A-Za-z0-9_]*=\S*[[:space:]]+)*git[[:space:]]+' || exit 0

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

# Detect `git -C <path>` and use that path for the branch check. The
# orchestrator's cwd may differ from the worktree the command targets
# (e.g. orchestrator on `main`, agent driving a `git -C <feature-worktree>`
# from outside). Without this, the hook would misread the branch as `main`
# and deny legitimate writes against a feature-branch worktree. See #1389.
WORKING_DIR=$(echo "$COMMAND" | grep -oE 'git[[:space:]]+-C[[:space:]]+[^[:space:]]+' | head -1 | awk '{print $NF}' || true)

# Resolve the directory all branch/repo lookups run in, in precedence order:
#   1. `git -C <path>` — the command explicitly targets that dir (#1389)
#   2. the hook-input cwd — the worktree the Bash command runs in (#1695)
#   3. (empty) — fall back to the hook's own process cwd
# Without (2), a plain `git add`/`git rm` (no -C) issued from a feature-branch
# worktree resolved its branch in the hook process's cwd (the main checkout)
# and was wrongly denied as if on `main`.
EFFECTIVE_DIR="${WORKING_DIR:-${HOOK_CWD:-}}"

# Get current branch (silently fail if not in a git repo)
if [ -n "$EFFECTIVE_DIR" ]; then
  CURRENT_BRANCH=$(git -C "$EFFECTIVE_DIR" branch --show-current 2>/dev/null || echo "")
else
  CURRENT_BRANCH=$(git branch --show-current 2>/dev/null || echo "")
fi
[ -z "$CURRENT_BRANCH" ] && exit 0

# Exempt GitHub wiki checkouts. A wiki renders only its `master` branch and
# supports no pull requests, so "switch to a feature branch" is a dead end and
# every wiki edit would degrade to full user delegation. Detect via the remote
# URL (*.wiki.git — robust, survives directory renames) or the working-tree
# top-level directory name (*.wiki — cheap fallback when there's no remote).
# (#1586)
if [ -n "$EFFECTIVE_DIR" ]; then
  WIKI_REMOTE=$(git -C "$EFFECTIVE_DIR" remote get-url origin 2>/dev/null || echo "")
  WIKI_TOPLEVEL=$(git -C "$EFFECTIVE_DIR" rev-parse --show-toplevel 2>/dev/null || echo "")
else
  WIKI_REMOTE=$(git remote get-url origin 2>/dev/null || echo "")
  WIKI_TOPLEVEL=$(git rev-parse --show-toplevel 2>/dev/null || echo "")
fi
case "$WIKI_REMOTE" in *.wiki.git|*.wiki) exit 0 ;; esac
case "$WIKI_TOPLEVEL" in *.wiki) exit 0 ;; esac

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
        deny "You're on '${CURRENT_BRANCH}'. Switch to a feature branch before 'git stash ${STASH_OP}' (git switch -c feature/your-change), or delegate this command to the user per .claude/rules/handling-blocked-hooks.md. If this repo uses main-branch-dev, ask the user to export CLAUDE_HOOKS_DISABLE_BRANCH_PROTECTION=1 in their shell."
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
    deny "You're on '${CURRENT_BRANCH}'. Create a feature branch first: git switch -c feature/your-change, then re-run 'git ${GIT_SUBCMD}'. If committing directly to ${CURRENT_BRANCH} is genuinely required (e.g. personal repo, dotfiles, main-branch-dev), delegate to the user per .claude/rules/handling-blocked-hooks.md — ask them to run it, or to export CLAUDE_HOOKS_DISABLE_BRANCH_PROTECTION=1 in their shell. Do not attempt to self-serve this bypass."
    ;;
  push)
    # Allow push to specific remote branch via explicit refspec
    if echo "$COMMAND" | grep -q ':'; then
      exit 0
    fi
    # Allow a push that explicitly names a non-protected branch as its target,
    # even without a colon refspec. `git push -u origin feat/x` pushes the local
    # `feat/x` ref (refs/heads/feat/x:refs/heads/feat/x) — the current branch
    # being main is irrelevant to what gets pushed. Pre-fix this fell through to
    # deny because only colon refspecs were allowed, even though the push never
    # touches the protected branch (#1600). PUSH_TARGET is the 2nd positional
    # (non-flag) token after `push` — i.e. the refspec following the remote.
    # HEAD/@ are excluded because on a protected checkout they resolve back to
    # the protected branch, so they must still be denied.
    PUSH_TARGET=$(echo "$COMMAND" | awk '
      { for (i = 1; i <= NF; i++) {
          if ($i == "push") { seen = 1; continue }
          if (seen && $i !~ /^-/) { n++; if (n == 2) { print $i; exit } }
      } }')
    if [ -n "$PUSH_TARGET" ] && \
       [ "$PUSH_TARGET" != "$CURRENT_BRANCH" ] && \
       [ "$PUSH_TARGET" != "main" ] && [ "$PUSH_TARGET" != "master" ] && \
       [ "$PUSH_TARGET" != "HEAD" ] && [ "$PUSH_TARGET" != "@" ]; then
      exit 0
    fi
    # Allow the very first push that bootstraps a repo. When the branch tip is
    # the repo's only commit (a single root commit), there is no prior history
    # to open a PR against — pushing it to main is how an empty remote gets
    # initialized. The normal protection resumes as soon as a second commit
    # exists. Branch detection respects `git -C <path>` and the hook-input cwd
    # for the same reason as CURRENT_BRANCH above (#1389, #1695).
    if [ -n "$EFFECTIVE_DIR" ]; then
      COMMIT_COUNT=$(git -C "$EFFECTIVE_DIR" rev-list --count HEAD 2>/dev/null || echo "")
    else
      COMMIT_COUNT=$(git rev-list --count HEAD 2>/dev/null || echo "")
    fi
    if [ "$COMMIT_COUNT" = "1" ]; then
      exit 0
    fi
    deny "You're about to push directly to '${CURRENT_BRANCH}'. In collaborative repos, changes go through a PR on a feature branch. To push local ${CURRENT_BRANCH} to a remote feature branch, use an explicit refspec (allowed): git push origin ${CURRENT_BRANCH}:feature/your-change. If pushing to ${CURRENT_BRANCH} is genuinely intentional, delegate to the user per .claude/rules/handling-blocked-hooks.md."
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
    deny "You're staging changes on '${CURRENT_BRANCH}'. Switch to a feature branch first: git switch -c feature/your-change, then re-run 'git ${GIT_SUBCMD}'. If committing to ${CURRENT_BRANCH} is genuinely required, delegate to the user per .claude/rules/handling-blocked-hooks.md — do not self-serve the CLAUDE_HOOKS_DISABLE_BRANCH_PROTECTION bypass."
    ;;
esac

exit 0
