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
#   3. Resolve the branch the command actually *writes to*: for a push that is
#      the refspec destination (`<sha>:refs/heads/<other>`), not whatever HEAD
#      happens to be — the push-by-SHA protocol (git-merge-hazards §3) pushes a
#      branch other than the checked-out one (#2672). Falls back to HEAD
#      whenever the refspec is not an unambiguous, literal branch name — a
#      multi-refspec push, or a destination still carrying a shell
#      metacharacter because the command was written as
#      `git push -u origin $(git branch --show-current)`. Adopting such a token
#      verbatim would silence the hook completely.
#   4. Cache per session+branch with a TTL so we fetch at most once per window.
#   5. Fetch origin, compute behind-count, and read the branch's PR state.
#   6. If the branch is behind upstream OR its PR is merged/closed, return
#      permissionDecision: "ask" (a nudge, never a hard deny — legitimate
#      force-syncs and intentional follow-up pushes must remain possible).
#   7. Suppress the *behind* nudge for a lease-pinned force-push whose
#      `--force-with-lease=<branch>:<sha>` SHA matches the freshly-fetched
#      origin tip: nobody pushed, the behind-commits are the session's own
#      pre-rebase history, and the lease itself refuses the push if anyone did
#      push in between (#2672). A *bare* `--force-with-lease` is NOT suppressed —
#      the fetch above advances the very tracking ref a bare lease is evaluated
#      against, so only the explicit form is safe to treat as self-verified.
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

# Is this a push (as opposed to a commit)? Only a push carries a refspec.
IS_PUSH=0
if printf '%s' "$COMMAND" | grep -qE '(^|[[:space:]]|&&[[:space:]]*|;[[:space:]]*)git([[:space:]]+-C[[:space:]]+[^[:space:]]+)?[[:space:]]+push\b'; then
    IS_PUSH=1
fi

# Parse `git push [opts] <remote> [+]<src>:<dst>` and print "<dst>\t<src>".
# Prints nothing when there is no parseable refspec (plain `git push`, `-u`
# without a refspec, `--all`, …) so the caller falls back to HEAD.
push_refspec_parts() {
    local args token dest src remote_seen=0 skip_next=0 refspec_count=0
    args=$(printf '%s' "$COMMAND" \
        | sed -nE 's/.*git([[:space:]]+-C[[:space:]]+[^[:space:]]+)?[[:space:]]+push[[:space:]]+//p' | head -1)
    [ -n "$args" ] || return 0
    # Stop at the end of this command inside a compound line.
    args=${args%%|*}; args=${args%%;*}; args=${args%%&&*}
    set -f  # no globbing while word-splitting the argument list
    for token in $args; do
        token=${token%\"}; token=${token#\"}
        token=${token%\'}; token=${token#\'}
        [ -n "$token" ] || continue
        if [ "$skip_next" = "1" ]; then skip_next=0; continue; fi
        case "$token" in
            -o|--push-option|--receive-pack|--exec|--repo) skip_next=1; continue ;;
            -*) continue ;;
        esac
        if [ "$remote_seen" = "0" ]; then remote_seen=1; continue; fi
        refspec_count=$((refspec_count + 1))
        [ "$refspec_count" = "1" ] && dest="$token"
    done
    set +f
    [ -n "${dest:-}" ] || return 0
    # A multi-refspec push (`git push origin main feature`) names more than one
    # destination, but this hook evaluates exactly one branch. Guarding only the
    # first refspec would leave the rest silently unguarded, so fall back to
    # HEAD — the pre-#2672 base, which at least always resolves.
    [ "$refspec_count" = "1" ] || return 0
    dest=${dest#+}
    src=""
    case "$dest" in
        *:*) src=${dest%:*}; dest=${dest##*:} ;;
        *)   src="$dest" ;;
    esac
    dest=${dest#refs/heads/}
    # Anything that is not a plain branch name (tags, other ref namespaces,
    # `HEAD`, deletion `:branch` with an empty source) falls back to HEAD.
    case "$dest" in ''|HEAD|refs/*) return 0 ;; esac
    # The hook sees the command as *written*, not as the shell expands it, so a
    # branch named by a substitution or a variable arrives here as raw source
    # text — `git push -u origin $(git branch --show-current)` yields the token
    # `$(git`. Adopting that verbatim silences the hook entirely (no such ref to
    # fetch, no origin ref so BEHIND=0, no PR to look up). Reject anything
    # carrying a shell metacharacter — all of which `git check-ref-format` also
    # forbids in a branch name — and fall back to HEAD, which for this repo's
    # documented push idiom is exactly the branch being pushed (#2672).
    case "$dest" in
        *'$'*|*'`'*|*'('*|*')'*|*'*'*|*'?'*|*'['*|*']'*|*'{'*|*'}'*|*\\*|*'~'*|*'^'*|*'"'*|*"'"*)
            return 0 ;;
    esac
    printf '%s\t%s' "$dest" "$src"
}

# Resolve the branch this command actually writes to.
BRANCH=$(git -C "$REPO_DIR" symbolic-ref --short HEAD 2>/dev/null || true)
PUSH_SRC=""
if [ "$IS_PUSH" = "1" ]; then
    refspec_parts=$(push_refspec_parts)
    if [ -n "$refspec_parts" ]; then
        BRANCH=${refspec_parts%%$'\t'*}
        PUSH_SRC=${refspec_parts#*$'\t'}
    fi
fi
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

# Behind count: commits on origin/<branch> not in the commit being pushed.
# The base is the refspec source when the push names one (push-by-SHA writes a
# branch other than HEAD, so HEAD is the wrong base there), else HEAD.
LOCAL_REF="HEAD"
if [ -n "$PUSH_SRC" ] && git -C "$REPO_DIR" rev-parse --verify --quiet "$PUSH_SRC" >/dev/null 2>&1; then
    LOCAL_REF="$PUSH_SRC"
fi
BEHIND=0
if git -C "$REPO_DIR" rev-parse --verify --quiet "refs/remotes/origin/${BRANCH}" >/dev/null 2>&1; then
    BEHIND=$(git -C "$REPO_DIR" rev-list --count "${LOCAL_REF}..refs/remotes/origin/${BRANCH}" 2>/dev/null || echo 0)
    case "$BEHIND" in ''|*[!0-9]*) BEHIND=0 ;; esac
fi

# Is this a force-push, and is it lease-pinned to the tip we just fetched?
IS_FORCE=0
if printf '%s' "$COMMAND" \
    | grep -qE -- '(^|[[:space:]])(-f|--force|--force-with-lease|--force-if-includes)(=[^[:space:]]*)?([[:space:]]|$)'; then
    IS_FORCE=1
fi

# A lease of the explicit form `--force-with-lease=<ref>:<sha>` is self-verifying:
# git refuses the push unless origin/<ref> is still <sha>. A *bare*
# `--force-with-lease` is not — it leases against the remote-tracking ref that
# this hook's own `git fetch` above just advanced — so it must not suppress.
LEASE_PINNED=0
LEASE=$(printf '%s' "$COMMAND" | sed -nE 's/.*--force-with-lease=([^[:space:]"'"'"']+).*/\1/p' | head -1)
case "$LEASE" in
    *:*)
        LEASE_REF=${LEASE%:*}
        LEASE_SHA=${LEASE##*:}
        LEASE_REF=${LEASE_REF#refs/heads/}
        if [ -n "$LEASE_SHA" ] && [ "$LEASE_REF" = "$BRANCH" ]; then
            ORIGIN_TIP=$(git -C "$REPO_DIR" rev-parse --verify --quiet "refs/remotes/origin/${BRANCH}" 2>/dev/null || true)
            # Leases are routinely abbreviated — prefix-match the full tip.
            if [ -n "$ORIGIN_TIP" ]; then
                case "$ORIGIN_TIP" in "$LEASE_SHA"*) LEASE_PINNED=1 ;; esac
            fi
        fi
        ;;
esac

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
elif [ "$BEHIND" -gt 0 ] && [ "$LEASE_PINNED" = "1" ]; then
    # Lease-pinned force-push: origin/<branch> is still exactly what the lease
    # names, so nobody pushed — the behind-commits are this session's own
    # pre-rebase history. Staying silent here is the #2672 fix.
    REASON=""
elif [ "$BEHIND" -gt 0 ] && [ "$IS_FORCE" = "1" ]; then
    REASON="Branch '${BRANCH}': ${BEHIND} remote commit(s) on origin/${BRANCH} are not in the commit you are pushing (expected after a rebase). Confirm this rewrite is yours before force-pushing. Run /git:pr-sync-check for details."
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
