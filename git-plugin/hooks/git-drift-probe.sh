#!/usr/bin/env bash
# git-drift-probe.sh — SessionStart probe for git PR-branch drift.
#
# When a session starts/resumes on a feature branch with an upstream and an
# open/merged PR, surfaces (via the shared drift-aggregator nudge):
#   1. pr_merged       — the branch's PR is already merged; new work belongs on
#                        a fresh branch off the updated default, not here.
#   2. branch_behind   — local tip is behind origin/<branch> (a teammate, another
#                        agent, or a CI auto-fix pushed since last sync).
#   3. changes_requested — the PR has CHANGES_REQUESTED reviews to address first.
#
# No-ops silently on the default branch, outside a git repo, or when gh is
# unavailable. Read-only: it does not fetch or mutate state (SessionStart must be
# fast and side-effect free) — it reads existing remote-tracking refs + PR state.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Resolve the drift-protocol library shipped by hooks-plugin. Marketplace installs
# place both plugins as siblings, so ../../hooks-plugin/hooks/lib resolves.
PROTO_LIB="${SCRIPT_DIR}/../../hooks-plugin/hooks/lib/drift-protocol.sh"
if [ ! -f "$PROTO_LIB" ]; then
    for candidate in \
        "${CLAUDE_PLUGIN_ROOT:-}/../hooks-plugin/hooks/lib/drift-protocol.sh" \
        "$HOME/.claude/plugins/hooks-plugin/hooks/lib/drift-protocol.sh"; do
        if [ -n "$candidate" ] && [ -f "$candidate" ]; then PROTO_LIB="$candidate"; break; fi
    done
fi
if [ ! -f "$PROTO_LIB" ]; then exit 0; fi
# shellcheck source=../../hooks-plugin/hooks/lib/drift-protocol.sh
# shellcheck disable=SC1091  # PROTO_LIB resolves at runtime via fallback chain
. "$PROTO_LIB"

drift_init "git-plugin"

# Need a git repo and gh; otherwise emit an empty (checked, no-drift) signal.
if ! git -C "$DRIFT_CWD" rev-parse --git-dir >/dev/null 2>&1; then drift_emit; exit 0; fi
drift_no_op_if_command_missing gh

BRANCH=$(git -C "$DRIFT_CWD" symbolic-ref --short HEAD 2>/dev/null || true)
if [ -z "$BRANCH" ]; then drift_emit; exit 0; fi
case "$BRANCH" in main|master|develop) drift_emit; exit 0 ;; esac

# Behind count from the existing remote-tracking ref (no fetch — SessionStart
# stays fast). Stale by at most one fetch; the /git:pr-sync-check skill fetches.
if git -C "$DRIFT_CWD" rev-parse --verify --quiet "refs/remotes/origin/${BRANCH}" >/dev/null 2>&1; then
    behind=$(git -C "$DRIFT_CWD" rev-list --count "HEAD..refs/remotes/origin/${BRANCH}" 2>/dev/null || echo 0)
    case "$behind" in ''|*[!0-9]*) behind=0 ;; esac
    if [ "$behind" -gt 0 ]; then
        drift_add_finding warn branch_behind \
            "${BRANCH} is ${behind} commit(s) behind origin/${BRANCH} — reconcile before new work" \
            "/git:pr-sync-check"
    fi
fi

# PR state (state per gh-json-fields.md, not a `merged` field). reviewDecision is
# APPROVED / CHANGES_REQUESTED / REVIEW_REQUIRED / "" .
REMOTE_URL=$(git -C "$DRIFT_CWD" remote get-url origin 2>/dev/null || true)
PR_JSON=$(gh pr view "$BRANCH" ${REMOTE_URL:+--repo "$REMOTE_URL"} \
    --json number,state,reviewDecision 2>/dev/null || true)
if [ -n "$PR_JSON" ] && [ "$PR_JSON" != "null" ]; then
    pr_num=$(printf '%s' "$PR_JSON" | jq -r '.number // empty' 2>/dev/null || true)
    pr_state=$(printf '%s' "$PR_JSON" | jq -r '.state // empty' 2>/dev/null || true)
    pr_review=$(printf '%s' "$PR_JSON" | jq -r '.reviewDecision // empty' 2>/dev/null || true)
    if [ "$pr_state" = "MERGED" ]; then
        drift_add_finding error pr_merged \
            "${BRANCH}'s PR #${pr_num} is merged — branch off the default before new work" \
            "/git:pr-sync-check"
    elif [ "$pr_review" = "CHANGES_REQUESTED" ]; then
        drift_add_finding warn changes_requested \
            "PR #${pr_num} on ${BRANCH} has changes requested — address review before new work" \
            "/git:pr-feedback"
    fi
fi

drift_emit
exit 0
