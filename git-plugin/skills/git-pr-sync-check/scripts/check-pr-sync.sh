#!/usr/bin/env bash
# check-pr-sync.sh — read-only "is this PR branch still live and in sync?" probe.
#
# Resolves the current branch, fetches origin, computes ahead/behind, and reads
# the branch's PR state, then emits a single VERDICT plus structured KEY=VALUE
# context (see .claude/rules/structured-script-output.md). Read-only — it fetches
# but never mutates working-tree or branch state.
#
# Verdicts (one per run):
#   no_remote          — not a git repo, or no origin remote
#   no_pr              — on the default branch, or no PR found for this branch
#   pr_merged          — the branch's PR is MERGED (new work belongs elsewhere)
#   pr_closed          — the branch's PR is CLOSED unmerged
#   changes_requested  — the PR has CHANGES_REQUESTED reviews to address
#   behind             — local tip is behind origin/<branch>
#   in_sync            — branch tracks an open PR and is up to date
#
# Usage: check-pr-sync.sh [--project-dir <path>]

set -uo pipefail

PROJECT_DIR="$(pwd)"
while [ $# -gt 0 ]; do
    case "$1" in
        --project-dir) PROJECT_DIR="${2:-$(pwd)}"; shift 2 ;;
        *) shift ;;
    esac
done

emit() {
    # emit <status> <verdict> <issue_count>
    local s="$1" v="$2" ic="$3"
    echo "=== PR SYNC ==="
    echo "BRANCH=${BRANCH:-}"
    echo "DEFAULT_BRANCH=${DEFAULT_BRANCH:-}"
    echo "AHEAD=${AHEAD:-0}"
    echo "BEHIND=${BEHIND:-0}"
    echo "PR_NUMBER=${PR_NUMBER:-}"
    echo "PR_STATE=${PR_STATE:-}"
    echo "MERGED_AT=${MERGED_AT:-}"
    echo "REVIEW_DECISION=${REVIEW_DECISION:-}"
    echo "CI_STATUS=${CI_STATUS:-}"
    echo "PR_URL=${PR_URL:-}"
    echo "STATUS=${s}"
    echo "VERDICT=${v}"
    echo "ISSUE_COUNT=${ic}"
    echo "=== END PR SYNC ==="
}

# Guard: git repo + origin remote.
if ! git -C "$PROJECT_DIR" rev-parse --git-dir >/dev/null 2>&1; then
    emit WARN no_remote 0; exit 0
fi
REMOTE_URL=$(git -C "$PROJECT_DIR" remote get-url origin 2>/dev/null || true)
if [ -z "$REMOTE_URL" ]; then
    emit WARN no_remote 0; exit 0
fi

BRANCH=$(git -C "$PROJECT_DIR" symbolic-ref --short HEAD 2>/dev/null || true)
DEFAULT_BRANCH=$(git -C "$PROJECT_DIR" symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null | sed 's#^origin/##' || true)
DEFAULT_BRANCH=${DEFAULT_BRANCH:-main}

if [ -z "$BRANCH" ]; then emit WARN no_remote 0; exit 0; fi

# On the default branch there is no PR-branch to be stale against.
if [ "$BRANCH" = "$DEFAULT_BRANCH" ]; then emit OK no_pr 0; exit 0; fi

# Fetch the branch + default branch so origin/<branch> reflects others' pushes.
# Network-guarded: a failed fetch degrades to whatever refs we already have.
git -C "$PROJECT_DIR" fetch --quiet origin "$BRANCH" "$DEFAULT_BRANCH" >/dev/null 2>&1 || true

# Ahead/behind vs origin/<branch>.
AHEAD=0; BEHIND=0
if git -C "$PROJECT_DIR" rev-parse --verify --quiet "refs/remotes/origin/${BRANCH}" >/dev/null 2>&1; then
    read -r AHEAD BEHIND < <(git -C "$PROJECT_DIR" rev-list --left-right --count \
        "HEAD...refs/remotes/origin/${BRANCH}" 2>/dev/null || echo "0 0")
    case "$AHEAD" in ''|*[!0-9]*) AHEAD=0 ;; esac
    case "$BEHIND" in ''|*[!0-9]*) BEHIND=0 ;; esac
fi

# PR state. state per gh-json-fields.md (never a `merged` field); statusCheckRollup
# carries per-check conclusions for the CI roll-up.
if command -v gh >/dev/null 2>&1; then
    PR_JSON=$(gh pr view "$BRANCH" --repo "$REMOTE_URL" \
        --json number,state,mergedAt,reviewDecision,url,statusCheckRollup 2>/dev/null || true)
    if [ -n "$PR_JSON" ] && [ "$PR_JSON" != "null" ]; then
        PR_NUMBER=$(printf '%s' "$PR_JSON" | jq -r '.number // empty' 2>/dev/null || true)
        PR_STATE=$(printf '%s' "$PR_JSON" | jq -r '.state // empty' 2>/dev/null || true)
        MERGED_AT=$(printf '%s' "$PR_JSON" | jq -r '.mergedAt // empty' 2>/dev/null || true)
        REVIEW_DECISION=$(printf '%s' "$PR_JSON" | jq -r '.reviewDecision // empty' 2>/dev/null || true)
        PR_URL=$(printf '%s' "$PR_JSON" | jq -r '.url // empty' 2>/dev/null || true)
        # CI roll-up: FAILING if any check failed, PENDING if any not yet complete,
        # PASSING if all complete and successful, empty if no checks.
        CI_STATUS=$(printf '%s' "$PR_JSON" | jq -r '
            (.statusCheckRollup // []) as $c
            | if ($c | length) == 0 then ""
              elif ($c | map(.conclusion) | any(. == "FAILURE" or . == "TIMED_OUT" or . == "CANCELLED" or . == "ACTION_REQUIRED" or . == "STARTUP_FAILURE")) then "FAILING"
              elif ($c | map(.status) | any(. != "COMPLETED")) then "PENDING"
              else "PASSING" end' 2>/dev/null || true)
    fi
fi

# Decide the verdict.
if [ -z "${PR_NUMBER:-}" ]; then
    if [ "${BEHIND:-0}" -gt 0 ]; then emit WARN behind 1; else emit OK no_pr 0; fi
    exit 0
fi
case "${PR_STATE:-}" in
    MERGED) emit ERROR pr_merged 1; exit 0 ;;
    CLOSED) emit WARN pr_closed 1; exit 0 ;;
esac
if [ "${REVIEW_DECISION:-}" = "CHANGES_REQUESTED" ]; then emit WARN changes_requested 1; exit 0; fi
if [ "${BEHIND:-0}" -gt 0 ]; then emit WARN behind 1; exit 0; fi
emit OK in_sync 0
exit 0
