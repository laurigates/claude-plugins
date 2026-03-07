#!/usr/bin/env bash
# Org-Wide Workflow Runs Analysis
# Aggregates workflow run data across all repositories in an organization.
# Usage: bash workflow-runs-org.sh [org] [--created RANGE] [--limit N]
#
# Args:
#   org       GitHub organization name (default: current repo's org)
#   --created Date range filter (e.g., ">=2026-03-01", "2026-02-01..2026-03-01")
#   --limit   Max repos to scan (default: 100)
#
# Output: Per-repo run counts, org-wide totals, top consumers, failure hotspots.

# shellcheck disable=SC2016  # jq expressions use $ for variable references, not shell expansion
set -euo pipefail

ORG=""
CREATED=""
LIMIT=100

while [[ $# -gt 0 ]]; do
  case $1 in
    --created)
      CREATED="$2"
      shift 2
      ;;
    --limit)
      LIMIT="$2"
      shift 2
      ;;
    *)
      ORG="$1"
      shift
      ;;
  esac
done

ORG="${ORG:-$(gh repo view --json owner --jq '.owner.login')}"
echo "=== Org-Wide Workflow Analysis: $ORG ==="

QUERY="per_page=100"
if [[ -n "$CREATED" ]]; then
  QUERY="${QUERY}&created=${CREATED}"
  echo "Date filter: $CREATED"
fi
echo ""

# Collect repos
REPOS=$(gh repo list "$ORG" --json nameWithOwner --limit "$LIMIT" --jq '.[].nameWithOwner')
REPO_COUNT=$(echo "$REPOS" | wc -l | tr -d ' ')
echo "Scanning $REPO_COUNT repositories..."
echo ""

# Temporary file for aggregation
TMPFILE=$(mktemp)
trap 'rm -f "$TMPFILE"' EXIT

ORG_TOTAL=0
ORG_SUCCESS=0
ORG_FAILURE=0
ORG_SKIPPED=0
ORG_CANCELLED=0

echo "=== Per-Repository Summary ==="
printf "%-45s %6s %6s %6s %6s %6s\n" "Repository" "Total" "OK" "Fail" "Skip" "Cancel"
printf "%-45s %6s %6s %6s %6s %6s\n" "---------" "-----" "----" "----" "----" "------"

while IFS= read -r repo; do
  result=$(gh api "/repos/$repo/actions/runs?${QUERY}" 2>/dev/null || echo '{"workflow_runs":[]}')
  stats=$(echo "$result" | jq -r '
    .workflow_runs |
    {
      total: length,
      success: ([.[] | select(.conclusion == "success")] | length),
      failure: ([.[] | select(.conclusion == "failure")] | length),
      skipped: ([.[] | select(.conclusion == "skipped")] | length),
      cancelled: ([.[] | select(.conclusion == "cancelled")] | length)
    } |
    "\(.total)\t\(.success)\t\(.failure)\t\(.skipped)\t\(.cancelled)"
  ')

  IFS=$'\t' read -r total success failure skipped cancelled <<< "$stats"
  total=${total:-0}
  success=${success:-0}
  failure=${failure:-0}
  skipped=${skipped:-0}
  cancelled=${cancelled:-0}

  if [[ "$total" -gt 0 ]]; then
    short_name="${repo#*/}"
    printf "%-45s %6d %6d %6d %6d %6d\n" "$short_name" "$total" "$success" "$failure" "$skipped" "$cancelled"
    echo "$repo $total $success $failure $skipped $cancelled" >> "$TMPFILE"
  fi

  ORG_TOTAL=$((ORG_TOTAL + total))
  ORG_SUCCESS=$((ORG_SUCCESS + success))
  ORG_FAILURE=$((ORG_FAILURE + failure))
  ORG_SKIPPED=$((ORG_SKIPPED + skipped))
  ORG_CANCELLED=$((ORG_CANCELLED + cancelled))
done <<< "$REPOS"

echo ""
echo "=== Org-Wide Totals ==="
echo "  Total runs: $ORG_TOTAL"
echo "  Success: $ORG_SUCCESS"
echo "  Failure: $ORG_FAILURE"
echo "  Skipped: $ORG_SKIPPED"
echo "  Cancelled: $ORG_CANCELLED"
if [[ "$ORG_TOTAL" -gt 0 ]]; then
  SUCCESS_RATE=$((ORG_SUCCESS * 100 / ORG_TOTAL))
  WASTE_RATE=$(((ORG_SKIPPED + ORG_CANCELLED) * 100 / ORG_TOTAL))
  echo "  Success rate: ${SUCCESS_RATE}%"
  echo "  Waste rate (skipped+cancelled): ${WASTE_RATE}%"
fi

echo ""
echo "=== Top 10 by Run Count ==="
# shellcheck disable=SC2034  # Positional fields — not all used in every loop
sort -k2 -n -r "$TMPFILE" | head -10 | while read -r repo total success failure skipped cancelled; do
  short="${repo#*/}"
  printf "  %-40s %d runs\n" "$short" "$total"
done

echo ""
echo "=== Failure Hotspots ==="
# shellcheck disable=SC2034  # Positional fields — not all used in every loop
sort -k4 -n -r "$TMPFILE" | head -10 | while read -r repo total success failure skipped cancelled; do
  if [[ "$failure" -gt 0 ]]; then
    short="${repo#*/}"
    rate=$((failure * 100 / total))
    printf "  %-40s %d failures (%d%%)\n" "$short" "$failure" "$rate"
  fi
done

echo ""
echo "=== Waste Hotspots (skipped + cancelled) ==="
# shellcheck disable=SC2034  # Positional fields — not all used in every loop
while read -r repo total success failure skipped cancelled; do
  waste=$((skipped + cancelled))
  if [[ "$waste" -gt 5 ]]; then
    short="${repo#*/}"
    rate=$((waste * 100 / total))
    printf "  %-40s %d wasted (%d%%)\n" "$short" "$waste" "$rate"
  fi
done < <(sort -k2 -n -r "$TMPFILE")
