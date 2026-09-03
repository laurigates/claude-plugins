#!/usr/bin/env bash
# Detect a scheduled workflow that has gone green for weeks while producing nothing.
#
# The failure this catches: a workflow whose ONLY output is a GitHub issue keeps
# reporting success while every attempt to file one is denied. The SDK exits 0 on
# a permission denial, so the run is green, the job log looks ordinary, and the
# silence is indistinguishable from "there was nothing to report" -- which for a
# triage workflow is an explicitly blessed outcome.
#
# Measured, not hypothetical. `research-radar.yml` ran 15 times green between
# 2026-06-15 and 2026-09-02 and filed 5 issues. Nine consecutive weekly runs,
# 2026-07-01 through 2026-08-19, filed nothing:
#
#   2026-08-05  success  11 turns  $1.80  permission_denials_count=6  no issue
#   2026-08-26  success   6 turns  $0.95  permission_denials_count=1  filed #2507
#
# The two differ in one place: the gap run's SDK options carry no `allowedTools`
# at all, so the action's default policy denied every `gh issue create`. The tool
# list had been written under `additional_permissions:`, which takes a GitHub
# permissions MAP, so it was never applied. Cost: ~9 Opus runs, ~1,200 candidate
# papers triaged and discarded, nine weeks of research signal.
#
# Why not gate on `permission_denials_count` directly: the HEALTHY run above has
# one. The prompt forbids WebFetch and the allowlist excludes it, so a denial
# there is the designed boundary working. A denials>0 gate would be red on a good
# week and get switched off.
#
# The same shape, found on the second workflow the moment this check was pointed
# at it: `changelog-review.yml` ran 22 times green and filed its last tracking
# issue on 2026-06-21 (#1733, covering 2.1.138 -> 2.1.185) -- 13 consecutive
# silent runs, and the 2026-08-31 run spent ~$4.77 over 22 turns with
# permission_denials_count=15. Two independent workflows with the same silent
# failure is what makes this a class rather than an anecdote.
#
# The cost is not just the wasted runs. `.claude-code-version-check.json`
# advanced `lastCheckedVersion` to 2.1.257 by hand while the last REVIEWED
# version was 2.1.185, so 2.1.186-2.1.231 was skipped by both the automation and
# the ledger. The stale 5-level subagent nesting ceiling in
# `.claude/rules/agent-development.md` sits in exactly that band.
#
# Why a STREAK and not a single run: one quiet week is legitimate and common. A
# run of them is not. Replayed against the real history, the default threshold
# first fires after the 2026-07-22 run -- the fourth silent week -- recovering 5
# of the 9 lost weeks instead of never firing at all. The two-silent-week stretch
# earlier in that history stays green, which is the property that keeps the check
# switched on.
#
# Output follows .claude/rules/structured-script-output.md.
#
# Usage:
#   scripts/check-audit-liveness.sh [--repo <owner/name>]
#   scripts/check-audit-liveness.sh --issue-body           # markdown for gh issue create
#   scripts/check-audit-liveness.sh --fixture <file.json>  # classify offline (tests)
#   scripts/check-audit-liveness.sh --max-silent <n>       # streak threshold (default 3)
#
# Exit codes:
#   0 - every watched workflow is filing, or is silent within tolerance
#   1 - a workflow exceeded its silent-streak threshold
#   2 - usage / environment error
set -euo pipefail

REPO=""
ISSUE_BODY=false
FIXTURE=""
MAX_SILENT=3

# Workflows whose output is an issue. The bar is whether a silent run is
# INDISTINGUISHABLE from a working one, not whether the workflow can in
# principle do something else: changelog-review also opens a follow-up PR, but
# only after its tracking issue exists, so when it goes quiet there is no
# artifact of any kind.
#   <workflow file>|<issue label>
WATCHED='research-radar.yml|research-radar
changelog-review.yml|changelog-review'

while [ $# -gt 0 ]; do
  case "$1" in
    --repo) REPO="${2:-}"; shift 2 ;;
    --issue-body) ISSUE_BODY=true; shift ;;
    --fixture) FIXTURE="${2:-}"; shift 2 ;;
    --max-silent) MAX_SILENT="${2:-}"; shift 2 ;;
    -h|--help) sed -n '2,40p' "$0"; exit 0 ;;
    # An unknown argument is REJECTED, never swallowed (#2057): a silently
    # ignored flag turns a gate into a no-op that still exits 0.
    *) echo "check-audit-liveness.sh: unknown argument: $1" >&2; exit 2 ;;
  esac
done

case "$MAX_SILENT" in
  ''|*[!0-9]*) echo "check-audit-liveness.sh: --max-silent needs an integer" >&2; exit 2 ;;
esac

if ! command -v jq >/dev/null 2>&1; then
  echo "check-audit-liveness.sh: jq not found on PATH" >&2
  exit 2
fi

# --- Collect ------------------------------------------------------------------
# Emits one JSON object per watched workflow:
#   {workflow, label, runs: [{id, createdAt}], issues: [{number, createdAt}]}
# Only SUCCESSFUL runs are collected: a red run is already visible as red, and
# this check exists for the ones that are green.
collect() {
  if [ -n "$FIXTURE" ]; then
    cat "$FIXTURE"
    return
  fi
  if ! command -v gh >/dev/null 2>&1; then
    echo "check-audit-liveness.sh: gh not found on PATH (use --fixture offline)" >&2
    exit 2
  fi
  local repo_args=()
  [ -n "$REPO" ] && repo_args=(--repo "$REPO")

  printf '%s\n' "$WATCHED" | while IFS='|' read -r wf label; do
    [ -n "$wf" ] || continue
    local runs issues
    runs="$(gh run list "${repo_args[@]}" --workflow "$wf" \
              --status success --limit 30 \
              --json databaseId,createdAt 2>/dev/null || echo '[]')"
    issues="$(gh issue list "${repo_args[@]}" --label "$label" --state all \
                --limit 100 --json number,createdAt 2>/dev/null || echo '[]')"
    jq -n --arg wf "$wf" --arg label "$label" \
          --argjson runs "${runs:-[]}" --argjson issues "${issues:-[]}" \
          '{workflow:$wf, label:$label, runs:$runs, issues:$issues}'
  done
}

# --- Classify -----------------------------------------------------------------
# A run FILED if an issue carrying the workflow's label was created in the two
# hours after the run started. Two hours is generous for a ~3-minute job and far
# tighter than the weekly cadence, so a run can never claim its neighbour's issue.
#
# The streak is counted from the NEWEST run backwards and stops at the first run
# that filed: what matters is whether the workflow is producing output NOW, not
# how many silent runs it has had in total.
classify() {
  jq -s --argjson max "$MAX_SILENT" '
    def filed(run; issues):
      (run.createdAt | fromdateiso8601) as $t
      | any(issues[];
            (.createdAt | fromdateiso8601) as $i
            | $i >= $t and $i <= ($t + 7200));

    map(
      . as $w
      | ($w.runs | sort_by(.createdAt) | reverse) as $runs
      | [ $runs[] | select(filed(.; $w.issues) | not) ] as $silent_all
      | ( [ $runs[] | filed(.; $w.issues) ] | index(true) // ($runs | length) ) as $streak
      | {
          workflow: $w.workflow,
          label: $w.label,
          runs_examined: ($runs | length),
          issues_seen: ($w.issues | length),
          silent_total: ($silent_all | length),
          silent_streak: $streak,
          newest_run: ($runs[0].createdAt // "none"),
          over: ($streak > $max)
        }
    )
  '
}

RESULT="$(collect | classify)"
OVER_COUNT="$(printf '%s' "$RESULT" | jq '[.[] | select(.over)] | length')"
WATCHED_COUNT="$(printf '%s' "$RESULT" | jq 'length')"

if [ "$ISSUE_BODY" = true ]; then
  # Emits nothing when everything is filing, so a clean sweep opens no issue.
  [ "$OVER_COUNT" -eq 0 ] && exit 0
  echo "## What"
  echo ""
  echo "A scheduled workflow has been reporting success while filing nothing."
  echo ""
  echo "## Why"
  echo ""
  echo "A green run that files no issue is indistinguishable from a green run"
  echo "that had nothing to file. \`research-radar.yml\` lost nine consecutive"
  echo "weeks to this in 2026 -- every \`gh issue create\` denied, every run green."
  echo ""
  echo "## How"
  echo ""
  printf '%s' "$RESULT" | jq -r '.[] | select(.over) |
    "- `\(.workflow)` (label `\(.label)`): \(.silent_streak) consecutive successful runs with no issue, newest \(.newest_run)."'
  echo ""
  echo "Check the run's SDK options for a missing \`--allowedTools\` grant, and"
  echo "its \`permission_denials_count\` in the execution log."
  exit 0
fi

echo "=== AUDIT LIVENESS ==="
echo "WORKFLOWS_WATCHED=$WATCHED_COUNT"
echo "SCANNED_EMPTY=$([ "$WATCHED_COUNT" -eq 0 ] && echo true || echo false)"
echo "MAX_SILENT_STREAK=$MAX_SILENT"
printf '%s' "$RESULT" | jq -r '.[] |
  "WORKFLOW=\(.workflow)\tRUNS=\(.runs_examined)\tISSUES=\(.issues_seen)\tSILENT_STREAK=\(.silent_streak)\tOVER=\(.over)"'
echo "ISSUE_COUNT=$OVER_COUNT"

if [ "$OVER_COUNT" -gt 0 ]; then
  echo ""
  echo "=== SILENT WORKFLOWS ==="
  printf '%s' "$RESULT" | jq -r '.[] | select(.over) |
    "SILENT=\(.workflow)\tLABEL=\(.label)\tSTREAK=\(.silent_streak)\tNEWEST_RUN=\(.newest_run)"'
  echo ""
  echo "=== REMEDY ==="
  echo "Read the newest run's \"SDK options\" block in the job log. A missing"
  echo "--allowedTools grant makes the action fall back to a default policy that"
  echo "denies 'gh issue create', so the run spends its budget and files nothing."
  echo "Confirm with permission_denials_count in the same log."
fi

echo ""
echo "STATUS=$([ "$OVER_COUNT" -gt 0 ] && echo FAIL || echo OK)"
[ "$OVER_COUNT" -gt 0 ] && exit 1
exit 0
