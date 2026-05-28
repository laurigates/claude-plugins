#!/usr/bin/env bash
# PreToolUse hook for Bash tool - reminds to check PR title/description on push
#
# When pushing to a branch with an existing PR, checks whether the PR title
# and description still align with the commits being pushed. Blocks with
# guidance showing current PR metadata and recent commits for review.
#
# Strategy:
# 1. Guard: only fires on git push commands
# 2. Check if gh CLI is available
# 3. Detect the target branch from the push command or current branch
# 4. Check if an open PR exists for that branch
# 5. If PR exists, gather PR title/body and recent commits
# 6. Block with a message showing both for Claude to review alignment

set -euo pipefail

block() {
    echo "$1" >&2
    exit 2
}

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty')
CWD=$(echo "$INPUT" | jq -r '.cwd // empty')

# Guard: only for git push commands
if [ -z "$COMMAND" ]; then exit 0; fi
if ! echo "$COMMAND" | grep -qE '(^|\s|&&\s*|;\s*)git\s+push\b'; then exit 0; fi

# Guard: skip if not in a git repo
if [ -z "$CWD" ] || ! git -C "$CWD" rev-parse --git-dir >/dev/null 2>&1; then exit 0; fi

# Guard: skip if gh CLI is not available
if ! command -v gh >/dev/null 2>&1; then exit 0; fi

# Detect the branch being pushed
# Patterns: git push origin branch, git push -u origin branch, git push (current branch)
PUSH_BRANCH=""

# Try to extract explicit branch name from command (last non-flag argument after remote)
# Handles: git push origin branch, git push -u origin branch, git push origin HEAD:branch
PUSH_BRANCH=$(echo "$COMMAND" | perl -ne '
    # Remove git push prefix and flags
    s/.*git\s+push\s+//;
    # Remove common flags
    s/\s+--[a-z-]+(?:=\S+)?//g;
    s/\s+-[a-zA-Z]+//g;
    # What remains should be [remote] [refspec]
    my @parts = split /\s+/;
    if (scalar @parts >= 2) {
        my $ref = $parts[1];
        # Handle HEAD:refs/heads/branch or HEAD:branch
        if ($ref =~ /:(.+)/) {
            my $target = $1;
            $target =~ s|^refs/heads/||;
            print $target;
        } else {
            print $ref;
        }
    }
' 2>/dev/null || true)

# Fall back to current branch
if [ -z "$PUSH_BRANCH" ]; then
    PUSH_BRANCH=$(git -C "$CWD" symbolic-ref --short HEAD 2>/dev/null || true)
fi

# Guard: no branch detected
if [ -z "$PUSH_BRANCH" ]; then exit 0; fi

# Check for an existing open PR on this branch
PR_JSON=$(gh pr view "$PUSH_BRANCH" --repo "$(git -C "$CWD" remote get-url origin 2>/dev/null || true)" --json title,body,number,url,updatedAt 2>/dev/null || true)

# Guard: no open PR for this branch
if [ -z "$PR_JSON" ] || [ "$PR_JSON" = "null" ]; then exit 0; fi

PR_NUMBER=$(echo "$PR_JSON" | jq -r '.number // empty')
PR_TITLE=$(echo "$PR_JSON" | jq -r '.title // empty')
PR_BODY=$(echo "$PR_JSON" | jq -r '.body // empty')
PR_URL=$(echo "$PR_JSON" | jq -r '.url // empty')
PR_UPDATED_AT=$(echo "$PR_JSON" | jq -r '.updatedAt // empty')

# Guard: couldn't parse PR data
if [ -z "$PR_NUMBER" ] || [ -z "$PR_TITLE" ]; then exit 0; fi

# Resolve the ref to inspect for commits and bypass-timestamp comparison.
# When the push command names a branch other than the running shell's
# current branch (e.g. `git push origin fix/A` from a `fix/B` checkout —
# the default situation under `git-pr-feedback --all` where the
# orchestrator drives multiple worktrees from a main-branch checkout),
# inspecting HEAD shows the wrong commits in the block message and reads
# the wrong author time for the bypass check. Use the pushed branch's
# local ref when it exists; fall back to HEAD for first-time pushes and
# `HEAD:new-branch` refspecs where the local ref hasn't been created yet.
# Regression: see issue #1419.
PUSH_REF="HEAD"
if [ -n "$PUSH_BRANCH" ] && \
   git -C "$CWD" rev-parse --verify --quiet "refs/heads/$PUSH_BRANCH" >/dev/null 2>&1; then
    PUSH_REF="refs/heads/$PUSH_BRANCH"
fi

# Retry-aware bypass (issue #1041, refined in #1400, cross-branch fix in #1419):
# if the PR was edited after the latest local commit on the pushed branch was
# authored, metadata has demonstrably been reconciled for that branch — let
# the push proceed silently.
#
# Use AUTHOR date (%aI), not committer date (%cI), because `git rebase`
# refreshes committer time to "now" while preserving author time. Without
# this, every rebase invalidates a previously-fired bypass and the agent
# has to make a content-different `gh pr edit` to escape — but
# `gh pr edit --body-file <file>` no-ops when the body is unchanged, so
# the agent ends up trapped (issue #1400).
HEAD_AUTHOR_TIME=$(git -C "$CWD" log -1 --format=%aI "$PUSH_REF" 2>/dev/null || true)
if [ -n "$PR_UPDATED_AT" ] && [ -n "$HEAD_AUTHOR_TIME" ]; then
    iso_to_epoch() {
        # Convert ISO 8601 to epoch seconds. Handles both Z (UTC) and
        # offset (e.g. +03:00) suffixes on BSD date (macOS) and GNU date.
        local iso="$1"
        if [[ "$iso" == *Z ]]; then
            # UTC: parse with TZ=UTC so BSD date doesn't assume local time
            TZ=UTC date -j -f "%Y-%m-%dT%H:%M:%S" "${iso%Z}" "+%s" 2>/dev/null && return 0
        else
            # Has explicit offset like +03:00; BSD date %z wants +0300
            local tz_normalized
            tz_normalized=$(printf '%s' "$iso" | sed -E 's/([+-][0-9]{2}):([0-9]{2})$/\1\2/')
            date -j -f "%Y-%m-%dT%H:%M:%S%z" "$tz_normalized" "+%s" 2>/dev/null && return 0
        fi
        # GNU date (Linux) accepts ISO 8601 directly
        date -d "$iso" "+%s" 2>/dev/null && return 0
        return 1
    }
    PR_UPDATED_TS=$(iso_to_epoch "$PR_UPDATED_AT" || echo "")
    HEAD_AUTHOR_TS=$(iso_to_epoch "$HEAD_AUTHOR_TIME" || echo "")
    if [ -n "$PR_UPDATED_TS" ] && [ -n "$HEAD_AUTHOR_TS" ] && \
       [ "$PR_UPDATED_TS" -gt "$HEAD_AUTHOR_TS" ]; then
        exit 0
    fi
fi

# Get recent commits on the pushed branch (since divergence from default
# branch). Uses PUSH_REF instead of HEAD so the block message shows the
# commits actually being pushed when the current shell is on a different
# branch (issue #1419).
RECENT_COMMITS=""
BASE=$(git -C "$CWD" merge-base "$PUSH_REF" origin/HEAD 2>/dev/null || true)
if [ -n "$BASE" ]; then
    RECENT_COMMITS=$(git -C "$CWD" log --format='  - %s' "${BASE}..${PUSH_REF}" 2>/dev/null | head -20 || true)
fi

# Truncate body for display (first 5 non-empty lines)
PR_BODY_PREVIEW=""
if [ -n "$PR_BODY" ]; then
    PR_BODY_PREVIEW=$(echo "$PR_BODY" | grep -v '^$' | head -5)
    BODY_LINES=$(echo "$PR_BODY" | grep -cv '^$' 2>/dev/null || echo "0")
    if [ "$BODY_LINES" -gt 5 ]; then
        PR_BODY_PREVIEW="${PR_BODY_PREVIEW}
  ... (truncated)"
    fi
fi

block "PR METADATA CHECK: You are pushing to a branch with an existing PR.

PR #${PR_NUMBER}: ${PR_TITLE}
${PR_URL}

Current PR description:
${PR_BODY_PREVIEW:-  (empty)}

Commits on this branch:
${RECENT_COMMITS:-  (no commits found)}

Before pushing, verify:
1. PR title still accurately describes the changes (conventional commit format)
2. PR description/summary reflects what the commits actually do
3. Issue references (Closes/Fixes/Resolves #N) are still correct

If the PR metadata is already accurate, re-run the push command.
If updates are needed, update the PR title/description first, then push."
