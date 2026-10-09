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

# >>> drift-protocol resolver >>>
# Keep this block byte-identical in every drift probe;
# scripts/tests/test-drift-probe-lib-resolution.sh enforces it.
# hooks-plugin ships the library. Layouts searched, in order:
#   flat    <root>/<plugin>/hooks          -> <root>/hooks-plugin/hooks/lib
#           (a claude-plugins checkout, --plugin-dir)
#   cache   <mkt>/<plugin>/<version>/hooks -> <mkt>/hooks-plugin/<version>/hooks/lib
#           (marketplace installs; old versions stay cached, highest wins)
#   legacy  ~/.claude/plugins/hooks-plugin/hooks/lib
# Before the cache layout was searched, every installed probe found nothing
# here and exited silently.
PROTO_LIB=""
for _dp_base in \
    "${SCRIPT_DIR}/../.." \
    "${CLAUDE_PLUGIN_ROOT:+${CLAUDE_PLUGIN_ROOT}/..}" \
    "${SCRIPT_DIR}/../../.." \
    "${CLAUDE_PLUGIN_ROOT:+${CLAUDE_PLUGIN_ROOT}/../..}" \
    "$HOME/.claude/plugins"; do
    if [ -z "$_dp_base" ] || [ ! -d "$_dp_base/hooks-plugin" ]; then
        continue
    fi
    if [ -f "$_dp_base/hooks-plugin/hooks/lib/drift-protocol.sh" ]; then
        PROTO_LIB="$_dp_base/hooks-plugin/hooks/lib/drift-protocol.sh"
        break
    fi
    _dp_ver=$(
        for _dp_lib in "$_dp_base"/hooks-plugin/*/hooks/lib/drift-protocol.sh; do
            if [ -f "$_dp_lib" ]; then
                _dp_lib="${_dp_lib#"$_dp_base"/hooks-plugin/}"
                printf '%s\n' "${_dp_lib%%/*}"
            fi
        done | sort -V | tail -n 1
    ) || _dp_ver=""
    if [ -n "$_dp_ver" ]; then
        PROTO_LIB="$_dp_base/hooks-plugin/$_dp_ver/hooks/lib/drift-protocol.sh"
        break
    fi
done
unset _dp_base _dp_ver _dp_lib
if [ -z "$PROTO_LIB" ]; then
    exit 0
fi
# shellcheck source=../../hooks-plugin/hooks/lib/drift-protocol.sh
# shellcheck disable=SC1091  # PROTO_LIB resolves at runtime via the search above
. "$PROTO_LIB"
# <<< drift-protocol resolver <<<

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
        # The suggested action must be a skill the MODEL can invoke.
        # /git:pr-feedback carries disable-model-invocation: true, so naming it
        # here would be a silently-unreachable nudge (#2442) — recommend it to
        # the user in the message, and point the action at the reachable skill.
        drift_add_finding warn changes_requested \
            "PR #${pr_num} on ${BRANCH} has changes requested — surface the threads and recommend the user run /git:pr-feedback before new work" \
            "/git:pr-sync-check"
    fi
fi

drift_emit
exit 0
