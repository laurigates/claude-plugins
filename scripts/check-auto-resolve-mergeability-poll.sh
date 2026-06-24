#!/usr/bin/env bash
# Guard: the "PR: Auto-resolve conflicts" workflow must POLL for each open PR's
# mergeability to settle before it decides which PRs are CONFLICTING — it must
# not read `mergeable` a single time, seconds after the triggering push.
#
# Background (the bug this guards against): GitHub recomputes a PR's mergeability
# ASYNCHRONOUSLY after its base branch moves. `auto-resolve-conflicts.yml` fires
# on `push` to main and its `find-conflicts` job ran `gh pr list --json mergeable`
# within ~3s of the push — while every open PR still read `UNKNOWN`, not
# `CONFLICTING`. The `select(.mergeable == "CONFLICTING")` filter therefore
# returned an empty matrix, the `resolve` job was SKIPPED, and the run reported
# green while doing nothing. PR #1786 sat conflicting indefinitely as a result.
#
# The fix polls the open-PR list until no PR is left `UNKNOWN` (bounded by a
# wall-clock deadline so the job can never hang), then filters for CONFLICTING.
# This guard encodes that intent as a SEMANTIC invariant: a future refactor that
# reverts to a single mergeability read drops the `UNKNOWN` poll and trips here.
#
# See .claude/rules/pr-branch-sync.md, .claude/rules/loop-integrity.md (bounded
# loop), and .claude/rules/gh-json-fields.md (mergeable enum).
#
# Usage:
#   bash scripts/check-auto-resolve-mergeability-poll.sh [--project-dir <path>]
#
# Exit codes:
#   0 - the workflow polls for mergeability to settle (bounded)
#   1 - the workflow is missing the poll (the race regression) or absent

set -euo pipefail

project_dir=""
while [ $# -gt 0 ]; do
  case "$1" in
    --project-dir)
      project_dir="${2:-}"
      shift 2
      ;;
    *)
      # Ignore stray filename args (pre-commit may pass them); this guard
      # always targets the one known workflow file.
      shift
      ;;
  esac
done

if [ -z "$project_dir" ]; then
  project_dir="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
fi

wf_rel=".github/workflows/auto-resolve-conflicts.yml"
wf="$project_dir/$wf_rel"

issue_count=0
issues=()

found="false"
polls_unknown="false"
has_wait="false"
is_bounded="false"

if [ -f "$wf" ]; then
  found="true"
  # (b) Inspects the unsettled state — the poll predicate.
  if grep -Eq 'mergeable[^)]*UNKNOWN' "$wf"; then
    polls_unknown="true"
  else
    issues+=("  - SEVERITY=ERROR TYPE=no_unknown_poll FILE=$wf_rel MSG=find-conflicts must inspect mergeable == UNKNOWN and wait, not read mergeable once")
    issue_count=$((issue_count + 1))
  fi
  # (b) Actually waits/retries while unsettled.
  if grep -Eq '(^|[^[:alnum:]_])sleep[[:space:]]' "$wf"; then
    has_wait="true"
  else
    issues+=("  - SEVERITY=ERROR TYPE=no_wait FILE=$wf_rel MSG=poll must wait between rounds (no sleep found) so GitHub can settle mergeability")
    issue_count=$((issue_count + 1))
  fi
  # (a)+loop-integrity: the poll is bounded by a wall-clock deadline.
  if grep -Eq 'DEADLINE|date \+%s' "$wf"; then
    is_bounded="true"
  else
    issues+=("  - SEVERITY=ERROR TYPE=unbounded_poll FILE=$wf_rel MSG=poll must be bounded by a wall-clock deadline (loop-integrity)")
    issue_count=$((issue_count + 1))
  fi
else
  issues+=("  - SEVERITY=ERROR TYPE=missing_workflow FILE=$wf_rel MSG=auto-resolve-conflicts workflow not found")
  issue_count=$((issue_count + 1))
fi

status="OK"
[ "$issue_count" -gt 0 ] && status="ERROR"

echo "=== AUTO-RESOLVE MERGEABILITY POLL ==="
echo "WORKFLOW_FOUND=$found"
echo "POLLS_UNKNOWN=$polls_unknown"
echo "HAS_WAIT=$has_wait"
echo "IS_BOUNDED=$is_bounded"
echo "STATUS=$status"
echo "ISSUE_COUNT=$issue_count"
if [ "$issue_count" -gt 0 ]; then
  echo "ISSUES:"
  printf '%s\n' "${issues[@]}"
fi
echo "=== END AUTO-RESOLVE MERGEABILITY POLL ==="

if [ "$issue_count" -gt 0 ]; then
  echo "" >&2
  echo "auto-resolve-conflicts.yml must poll until mergeability settles before" >&2
  echo "filtering for CONFLICTING PRs — reading 'mergeable' once, seconds after" >&2
  echo "the push, misses PRs GitHub has not finished recomputing (the #1786" >&2
  echo "race). See .claude/rules/pr-branch-sync.md and loop-integrity.md." >&2
  exit 1
fi

echo "auto-resolve-conflicts.yml polls for mergeability to settle (bounded). ✅"
exit 0
