#!/usr/bin/env bash
# PreToolUse hook — guards write operations on protected branches (main, master)
#
# Behavior:
#   - Common operations (commit, push, add): denied with guidance to switch to
#     a feature branch, use an explicit-refspec push, or delegate to the user
#     per .claude/rules/handling-blocked-hooks.md.
#   - Destructive operations (reset, rebase): prompts user to approve via "ask"
#   - Read-only operations: always allowed silently
#   - Under permission mode "auto": defers entirely to auto mode's classifier
#     (exits early) to avoid double-gating; still enforces in every other mode
#     and in surfaces where auto mode is unavailable (web/remote/CI, or a
#     plan/model that does not offer it).
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

# Defer to auto mode. Under permission mode "auto", Claude Code routes the
# actual tool call through its own classifier with full environment context
# (CLAUDE.md, trusted-repo config, force-push / protected-branch soft_deny).
# This deterministic guard would only double-gate that and re-introduce the
# blunt false positives auto mode avoids. So enforce ONLY outside auto mode —
# which still covers default/plan/acceptEdits and, crucially, web/remote/CI and
# sessions where auto mode is unavailable. Auto mode is the default permission mode, so in a
# current local session this hook is normally silent and the classifier owns the call.
# permission_mode is a common hook input field; absent (older clients) it's empty and
# enforcement proceeds.
PERMISSION_MODE=$(echo "$INPUT" | jq -r '.permission_mode // empty')
[ "$PERMISSION_MODE" = "auto" ] && exit 0

# Only applies to Bash tool
[ "$TOOL_NAME" != "Bash" ] && exit 0
[ -z "$COMMAND" ] && exit 0

# Split the command into top-level CLAUSES on unquoted `;`, `&`, `|`, and `(` —
# the shell metacharacters that let a git invocation ride past a detector
# anchored only at the start of the string. A `^`-only anchor let a compound or
# prefixed form bypass the whole hook: `cd . && git commit`, `command git
# commit`, `true; git commit`, and `/usr/bin/git commit` were all silently
# ALLOWED before this fix. Quote state (single/double) is tracked per line,
# mirroring bash-antipatterns.sh's mask_quoted_content (not sourced — this is
# a safety-tier hook and must not depend on a file that could be missing from
# a partial deployment; lib/command-views.sh's own header says as much), so a
# separator or a `git`-looking word inside a quoted string (a commit message,
# a comment) never becomes a clause boundary or a second invocation.
split_clauses() {
  printf '%s\n' "$1" | awk -v SQ="'" '
  {
    line = $0
    n = length(line)
    in_s = 0; in_d = 0
    clause = ""
    for (i = 1; i <= n; i++) {
      c = substr(line, i, 1)
      if (in_s == 1) {
        clause = clause c
        if (c == SQ) in_s = 0
      } else if (in_d == 1) {
        if (c == "\\" && i < n) { clause = clause c substr(line, i + 1, 1); i++ }
        else { clause = clause c; if (c == "\"") in_d = 0 }
      } else if (c == "\\" && i < n) {
        clause = clause c substr(line, i + 1, 1); i++
      } else if (c == SQ) {
        in_s = 1; clause = clause c
      } else if (c == "\"") {
        in_d = 1; clause = clause c
      } else if (c == ";" || c == "&" || c == "|" || c == "(") {
        print clause
        clause = ""
      } else {
        clause = clause c
      }
    }
    print clause
  }'
}

# A clause is a git invocation if it starts (after whitespace) with an
# optional run of prefix words (sudo/command/exec/nice/nohup/time/env),
# optional leading `VAR=value` assignments (so an inline
# `CLAUDE_HOOKS_DISABLE_BRANCH_PROTECTION=1 git ...` bypass attempt is still
# treated as a git command), and an optional path prefix before `git`.
GIT_CLAUSE_RE='^[[:space:]]*((sudo|command|exec|nice|nohup|time|env)[[:space:]]+)*([A-Za-z_][A-Za-z0-9_]*=[^[:space:]]*[[:space:]]+)*([^[:space:]]*/)?git[[:space:]]+(-[A-Za-z][[:space:]]+[^[:space:]]+[[:space:]]+)*[a-z-]+'

mapfile -t CLAUSES < <(split_clauses "$COMMAND")

GIT_CLAUSES=()
for c in "${CLAUSES[@]}"; do
  if echo "$c" | grep -Eq "$GIT_CLAUSE_RE"; then
    GIT_CLAUSES+=("$c")
  fi
done

# Only check git commands — no clause in the command looks like a git
# invocation.
[ "${#GIT_CLAUSES[@]}" -eq 0 ] && exit 0

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

# Verdict accumulator across every git clause in the command. deny beats ask
# beats allow — a command that mixes a read-only clause with a write clause
# (`git status && git commit -m x`) must not fall through to allow just
# because the read-only clause was checked first. record_* never exits, so
# every clause gets evaluated; the reason kept is the first tier-raising one
# found, not the last.
VERDICT="allow"
VERDICT_REASON=""

record_deny() {
  if [ "$VERDICT" != "deny" ]; then
    VERDICT="deny"
    VERDICT_REASON="$1"
  fi
}

record_ask() {
  if [ "$VERDICT" = "allow" ]; then
    VERDICT="ask"
    VERDICT_REASON="$1"
  fi
}

for GIT_CLAUSE in "${GIT_CLAUSES[@]}"; do
  # Extract the git subcommand from THIS clause (handles global flags like
  # -C <path>, prefix words, and path prefixes — head -1 takes only the
  # leading, real invocation even if the clause also quotes a git-looking
  # phrase later, e.g. `git commit -m "fix git log parsing"`).
  GIT_SUBCMD=$(echo "$GIT_CLAUSE" | grep -oE "$GIT_CLAUSE_RE" | head -1 | awk '{print $NF}' || true)

  case "$GIT_SUBCMD" in
    # Read-only operations — always allowed
    status|diff|log|show|branch|remote|fetch|pull|stash|tag|blame|shortlog|describe|ls-files|ls-tree|rev-parse|rev-list|name-rev|reflog)
      # Allow stash list but guard stash pop/apply/drop
      if [ "$GIT_SUBCMD" = "stash" ]; then
        if echo "$GIT_CLAUSE" | grep -Eq 'stash\s+(pop|apply|drop|clear)'; then
          STASH_OP=$(echo "$GIT_CLAUSE" | grep -oE '(pop|apply|drop|clear)' | head -1 || true)
          record_deny "You're on '${CURRENT_BRANCH}'. Switch to a feature branch before 'git stash ${STASH_OP}' (git switch -c feature/your-change), or delegate this command to the user per .claude/rules/handling-blocked-hooks.md. If this repo uses main-branch-dev, ask the user to export CLAUDE_HOOKS_DISABLE_BRANCH_PROTECTION=1 in their shell."
        fi
      fi
      ;;
    # Merge — allowed on protected branches (local, reversible operation)
    merge)
      ;;
    # Destructive operations — require explicit user approval
    rebase|reset)
      record_ask "You're about to run 'git ${GIT_SUBCMD}' on '${CURRENT_BRANCH}'. This is a destructive operation on a protected branch. Approve to proceed, or deny to work on a feature branch instead."
      ;;
    # Common write operations — deny with guidance for Claude
    commit|cherry-pick|revert)
      record_deny "You're on '${CURRENT_BRANCH}'. Create a feature branch first: git switch -c feature/your-change, then re-run 'git ${GIT_SUBCMD}'. If committing directly to ${CURRENT_BRANCH} is genuinely required (e.g. personal repo, dotfiles, main-branch-dev), delegate to the user per .claude/rules/handling-blocked-hooks.md — ask them to run it, or to export CLAUDE_HOOKS_DISABLE_BRANCH_PROTECTION=1 in their shell. Do not attempt to self-serve this bypass."
      ;;
    push)
      PUSH_ALLOWED=0
      # Allow push to specific remote branch via explicit refspec
      if echo "$GIT_CLAUSE" | grep -q ':'; then
        PUSH_ALLOWED=1
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
      if [ "$PUSH_ALLOWED" -eq 0 ]; then
        PUSH_TARGET=$(echo "$GIT_CLAUSE" | awk '
          { for (i = 1; i <= NF; i++) {
              if ($i == "push") { seen = 1; continue }
              if (seen && $i !~ /^-/) { n++; if (n == 2) { print $i; exit } }
          } }')
        if [ -n "$PUSH_TARGET" ] && \
           [ "$PUSH_TARGET" != "$CURRENT_BRANCH" ] && \
           [ "$PUSH_TARGET" != "main" ] && [ "$PUSH_TARGET" != "master" ] && \
           [ "$PUSH_TARGET" != "HEAD" ] && [ "$PUSH_TARGET" != "@" ]; then
          PUSH_ALLOWED=1
        fi
      fi
      # Allow the very first push that bootstraps a repo. When the branch tip is
      # the repo's only commit (a single root commit), there is no prior history
      # to open a PR against — pushing it to main is how an empty remote gets
      # initialized. The normal protection resumes as soon as a second commit
      # exists. Branch detection respects `git -C <path>` and the hook-input cwd
      # for the same reason as CURRENT_BRANCH above (#1389, #1695).
      if [ "$PUSH_ALLOWED" -eq 0 ]; then
        if [ -n "$EFFECTIVE_DIR" ]; then
          COMMIT_COUNT=$(git -C "$EFFECTIVE_DIR" rev-list --count HEAD 2>/dev/null || echo "")
        else
          COMMIT_COUNT=$(git rev-list --count HEAD 2>/dev/null || echo "")
        fi
        [ "$COMMIT_COUNT" = "1" ] && PUSH_ALLOWED=1
      fi
      if [ "$PUSH_ALLOWED" -eq 0 ]; then
        record_deny "You're about to push directly to '${CURRENT_BRANCH}'. In collaborative repos, changes go through a PR on a feature branch. To push local ${CURRENT_BRANCH} to a remote feature branch, use an explicit refspec (allowed): git push origin ${CURRENT_BRANCH}:feature/your-change. If pushing to ${CURRENT_BRANCH} is genuinely intentional, delegate to the user per .claude/rules/handling-blocked-hooks.md."
      fi
      ;;
    # Staging operations
    add|rm|mv|restore|checkout|switch)
      # Allow checkout/switch to another branch, and restore (a safety op)
      if [ "$GIT_SUBCMD" != "checkout" ] && [ "$GIT_SUBCMD" != "switch" ] && [ "$GIT_SUBCMD" != "restore" ]; then
        # Staging implies committing — deny with guidance
        record_deny "You're staging changes on '${CURRENT_BRANCH}'. Switch to a feature branch first: git switch -c feature/your-change, then re-run 'git ${GIT_SUBCMD}'. If committing to ${CURRENT_BRANCH} is genuinely required, delegate to the user per .claude/rules/handling-blocked-hooks.md — do not self-serve the CLAUDE_HOOKS_DISABLE_BRANCH_PROTECTION bypass."
      fi
      ;;
  esac
done

case "$VERDICT" in
  deny) deny "$VERDICT_REASON" ;;
  ask) ask "$VERDICT_REASON" ;;
esac

exit 0
