#!/usr/bin/env bash
# Workflow Runs Analysis
# Analyzes GitHub Actions workflow runs for a repository.
# Usage: bash workflow-runs.sh [repo] [--created RANGE]
#
# Args:
#   repo      Repository in owner/name format (default: current repo)
#   --created Date range filter for gh api (e.g., ">=2026-03-01", "2026-02-01..2026-03-01")
#
# Output: Active workflows, run summary, duration analysis, triggers, failures,
#         and high-frequency detection.

# shellcheck disable=SC2016  # jq expressions use $ for variable references, not shell expansion
set -euo pipefail

REPO=""
CREATED=""

while [[ $# -gt 0 ]]; do
  case $1 in
    --created)
      CREATED="$2"
      shift 2
      ;;
    *)
      REPO="$1"
      shift
      ;;
  esac
done

REPO="${REPO:-$(gh repo view --json nameWithOwner --jq '.nameWithOwner')}"
echo "Analyzing workflows for: $REPO"

# Build query params
QUERY="per_page=100"
if [[ -n "$CREATED" ]]; then
  QUERY="${QUERY}&created=${CREATED}"
  echo "Date filter: $CREATED"
fi

echo ""
echo "=== Active Workflows ==="
gh workflow list --repo "$REPO" --json id,name,state \
  --jq '.[] | select(.state == "active") | "  \(.name) (id: \(.id))"'

echo ""
echo "=== Run Summary ==="
gh api "/repos/$REPO/actions/runs?${QUERY}" \
  --jq '.workflow_runs | group_by(.name) |
        map({
          name: .[0].name,
          total: length,
          success: ([.[] | select(.conclusion == "success")] | length),
          failure: ([.[] | select(.conclusion == "failure")] | length),
          cancelled: ([.[] | select(.conclusion == "cancelled")] | length),
          skipped: ([.[] | select(.conclusion == "skipped")] | length)
        }) |
        sort_by(-.total)[] |
        "\(.name):\n  Total: \(.total) | Success: \(.success) | Failure: \(.failure) | Cancelled: \(.cancelled) | Skipped: \(.skipped)\n  Success rate: \(if .total > 0 then ((.success / .total * 100) | floor) else 0 end)%"'

echo ""
echo "=== Duration Analysis ==="
DURATION_QUERY="per_page=50&status=completed"
if [[ -n "$CREATED" ]]; then
  DURATION_QUERY="${DURATION_QUERY}&created=${CREATED}"
fi
gh api "/repos/$REPO/actions/runs?${DURATION_QUERY}" \
  --jq '.workflow_runs | group_by(.name) |
        map({
          name: .[0].name,
          count: length,
          durations: [.[] | (.run_started_at as $start | .updated_at as $end |
                      (($end | fromdateiso8601) - ($start | fromdateiso8601)))],
        }) |
        map({
          name: .name,
          count: .count,
          avg_seconds: (if .count > 0 then (.durations | add / length | floor) else 0 end),
          max_seconds: (if .count > 0 then (.durations | max) else 0 end),
          total_seconds: (.durations | add)
        }) |
        sort_by(-.total_seconds)[] |
        "\(.name):\n  Runs: \(.count) | Avg: \(.avg_seconds / 60 | floor)m\(.avg_seconds % 60)s | Max: \(.max_seconds / 60 | floor)m\(.max_seconds % 60)s | Total: \(.total_seconds / 60 | floor)min"'

echo ""
echo "=== Trigger Types ==="
gh api "/repos/$REPO/actions/runs?${QUERY}" \
  --jq '.workflow_runs | group_by(.event) |
        map({event: .[0].event, count: length}) |
        sort_by(-.count)[] |
        "  \(.event): \(.count) runs"'

echo ""
echo "=== Recent Failures (last 10) ==="
FAIL_QUERY="per_page=100&status=completed"
if [[ -n "$CREATED" ]]; then
  FAIL_QUERY="${FAIL_QUERY}&created=${CREATED}"
fi
gh api "/repos/$REPO/actions/runs?${FAIL_QUERY}" \
  --jq '[.workflow_runs[] | select(.conclusion == "failure")] | .[0:10][] |
        "  #\(.run_number) \(.name) - \(.created_at | split("T")[0]) - \(.html_url)"'

echo ""
echo "=== High Frequency Workflows ==="
gh api "/repos/$REPO/actions/runs?${QUERY}" \
  --jq '.workflow_runs | group_by(.name) |
        map(select(length > 60)) |
        map({name: .[0].name, runs: length, per_day: (length / 30 | . * 10 | floor / 10)}) |
        sort_by(-.runs)[] |
        "  \(.name): \(.runs) runs (~\(.per_day)/day) - consider path filters"'
