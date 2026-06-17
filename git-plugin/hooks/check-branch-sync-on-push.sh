#!/usr/bin/env bash
# PreToolUse hook for Bash tool — nudges before building further on a stale or
# merged PR branch.
#
# Problem: in a multi-request session Claude keeps committing/pushing onto a PR
# branch after the branch's reality changed — the PR already merged (work belongs
# on a fresh branch off the updated default), or another agent / person / CI
# auto-fix pushed commits so the local tip is behind origin.
#
# Strategy:
#   1. Guard: only fires on git commit / git push commands.
#   2. Resolve the repo dir (honors `git -C <path>` for worktree dispatch, #1389).
#   3. Cache per session+branch with a TTL so we fetch at most once per window.
#   4. Fetch origin, compute behind-count, and read the branch's PR state.
#   5. If the branch is behind upstream OR its PR is merged/closed, return
#      permissionDecision: "ask" (a nudge, never a hard deny — legitimate
#      force-syncs and intentional follow-up pushes must remain possible).
#
# Opt out: CLAUDE_HOOKS_DISABLE_BRANCH_SYNC=1
# TTL override (seconds): CLAUDE_HOOKS_BRANCH_SYNC_TTL (default 300)
#
# This hook asks via a JSON envelope rather than blocking with exit 2, so it
# deliberately does not use the block() convention.

set -uo pipefail

# Opt-out
if [ "${CLAUDE_HOOKS_DISABLE_BRANCH_SYNC:-0}" = "1" ]; then exit 0; fi

# jq is required to parse hook input and emit the envelope.
command -v jq >/dev/null 2>&1 || exit 0

INPUT=$(cat)
COMMAND=$(printf '%s' "$INPUT" | jq -r '.tool_input.command // empty')
CWD=$(printf '%s' "$INPUT" | jq -r '.cwd // empty')
SESSION_ID=$(printf '%s' "$INPUT" | jq -r '.session_id // "nosession"')

# Guard: only for git commit / git push commands.
if [ -z "$COMMAND" ]; then exit 0; fi
if ! printf '%s' "$COMMAND" | grep -qE '(^|[[:space:]]|&&[[:space:]]*|;[[:space:]]*)git([[:space:]]+-C[[:space:]]+[^[:space:]]+)?[[:space:]]+(commit|push)\b'; then
    exit 0
fi

# Resolve the repo directory. Honor an explicit `git -C <path>` in the command
# (worktree dispatch routes writes to a path other than the running cwd, #1389),
# falling back to the hook's cwd.
REPO_DIR="$CWD"
gc_path=$(printf '%s' "$COMMAND" | sed -nE 's/.*git[[:space:]]+-C[[:space:]]+([^[:space:]]+).*/\1/p' | head -1)
if [ -n "$gc_path" ]; then REPO_DIR="$gc_path"; fi

# Guard: skip if not in a git repo.
if [ -z "$REPO_DIR" ] || ! git -C "$REPO_DIR" rev-parse --git-dir >/dev/null 2>&1; then exit 0; fi

# Guard: skip if gh CLI is unavailable (degrade silently).
command -v gh >/dev/null 2>&1 || exit 0

# Resolve the current branch of the resolved repo dir.
BRANCH=$(git -C "$REPO_DIR" symbolic-ref --short HEAD 2>/dev/null || true)
if [ -z "$BRANCH" ]; then exit 0; fi

# Never nudge on the default/protected branches — building there is its own
# concern (branch-protection.sh) and there is no PR-branch to be stale against.
case "$BRANCH" in main|master|develop) exit 0 ;; esac

# ── Cache: fetch + check at most once per TTL per session+branch ──────────────
TTL="${CLAUDE_HOOKS_BRANCH_SYNC_TTL:-300}"
SID_CLEAN=$(printf '%s' "$SESSION_ID" | tr -cd 'a-zA-Z0-9_-'); SID_CLEAN=${SID_CLEAN:-nosession}
BR_CLEAN=$(printf '%s' "$BRANCH" | tr -cd 'a-zA-Z0-9_.-'); BR_CLEAN=${BR_CLEAN:-branch}
CACHE_DIR="${TMPDIR:-/tmp}/claude-branch-sync/${SID_CLEAN}"
CACHE_FILE="${CACHE_DIR}/${BR_CLEAN}"
now=$(date +%s 2>/dev/null || echo 0)
if [ -f "$CACHE_FILE" ]; then
    last=$(cat "$CACHE_FILE" 2>/dev/null || echo 0)
    case "$last" in ''|*[!0-9]*) last=0 ;; esac
    if [ "$now" -ge 0 ] && [ "$last" -gt 0 ] && [ $((now - last)) -lt "$TTL" ]; then
        exit 0
    fi
fi
mkdir -p "$CACHE_DIR" 2>/dev/null || true
printf '%s' "$now" > "$CACHE_FILE" 2>/dev/null || true

# ── Detect drift ──────────────────────────────────────────────────────────────
REMOTE_URL=$(git -C "$REPO_DIR" remote get-url origin 2>/dev/null || true)

# Fetch the branch quietly so origin/<branch> reflects what others pushed.
# Network-guarded: a failed fetch must not block the user's command.
git -C "$REPO_DIR" fetch --quiet origin "$BRANCH" >/dev/null 2>&1 || true

# Behind count: commits on origin/<branch> not in local HEAD.
BEHIND=0
if git -C "$REPO_DIR" rev-parse --verify --quiet "refs/remotes/origin/${BRANCH}" >/dev/null 2>&1; then
    BEHIND=$(git -C "$REPO_DIR" rev-list --count "HEAD..refs/remotes/origin/${BRANCH}" 2>/dev/null || echo 0)
    case "$BEHIND" in ''|*[!0-9]*) BEHIND=0 ;; esac
fi

# PR state for this branch. state is "MERGED"/"OPEN"/"CLOSED" (gh-json-fields.md:
# never ask for a `merged` field). mergedAt is an ISO timestamp or null.
PR_JSON=$(gh pr view "$BRANCH" ${REMOTE_URL:+--repo "$REMOTE_URL"} \
    --json number,state,mergedAt,url 2>/dev/null || true)
PR_STATE=""
PR_NUMBER=""
PR_URL=""
if [ -n "$PR_JSON" ] && [ "$PR_JSON" != "null" ]; then
    PR_STATE=$(printf '%s' "$PR_JSON" | jq -r '.state // empty' 2>/dev/null || true)
    PR_NUMBER=$(printf '%s' "$PR_JSON" | jq -r '.number // empty' 2>/dev/null || true)
    PR_URL=$(printf '%s' "$PR_JSON" | jq -r '.url // empty' 2>/dev/null || true)
fi

# ── Decide ────────────────────────────────────────────────────────────────────
REASON=""
if [ "$PR_STATE" = "MERGED" ]; then
    REASON="Branch '${BRANCH}' has an ALREADY-MERGED PR #${PR_NUMBER} (${PR_URL}). New work here will not reach a PR. Start a fresh branch off the updated default branch instead of adding commits to a merged branch. Run /git:pr-sync-check to confirm."
elif [ "$PR_STATE" = "CLOSED" ]; then
    REASON="Branch '${BRANCH}' has a CLOSED (unmerged) PR #${PR_NUMBER} (${PR_URL}). Confirm this branch is still where the work belongs before adding commits. Run /git:pr-sync-check."
elif [ "$BEHIND" -gt 0 ]; then
    REASON="Branch '${BRANCH}' is ${BEHIND} commit(s) behind origin/${BRANCH} — someone (a teammate, another agent, or a CI auto-fix) pushed since your last sync. Reconcile first (git pull --rebase) so you build on the current tip and avoid a rejected push or conflict. Run /git:pr-sync-check for details."
fi

if [ -n "$REASON" ]; then
    jq -n --arg reason "$REASON" '{
        hookSpecificOutput: {
            hookEventName: "PreToolUse",
            permissionDecision: "ask",
            permissionDecisionReason: $reason
        }
    }'
fi

exit 0
