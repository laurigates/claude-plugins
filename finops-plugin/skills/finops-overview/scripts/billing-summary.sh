#!/usr/bin/env bash
# Billing Summary
# Quick FinOps overview: org billing, cache usage, repo workflow stats, waste indicators.
# Usage: bash billing-summary.sh [org] [repo]
#
# Args:
#   org   GitHub organization name (default: current repo's org)
#   repo  Repository in owner/name format (default: current repo)

set -euo pipefail

ORG="${1:-$(gh repo view --json owner --jq '.owner.login')}"
REPO="${2:-$(gh repo view --json nameWithOwner --jq '.nameWithOwner')}"

echo "=== Org Billing: $ORG ==="
gh api "/orgs/$ORG/settings/billing/actions" \
  --jq '"Minutes: \(.total_minutes_used)/\(.included_minutes) included, \(.total_paid_minutes_used) paid"' \
  2>/dev/null || echo "  (requires org admin access)"

echo ""
echo "=== Org Cache Usage ==="
gh api "/orgs/$ORG/actions/cache/usage" \
  --jq '"\(.total_active_caches_count) caches, \(.total_active_caches_size_in_bytes / 1024 / 1024 | floor)MB total"' \
  2>/dev/null || echo "  (requires org admin access)"

echo ""
echo "=== Repo: $REPO ==="

echo "Cache:"
gh api "/repos/$REPO/actions/cache/usage" \
  --jq '"  \(.active_caches_count) caches, \(.active_caches_size_in_bytes / 1024 / 1024 | floor)MB"'

echo ""
echo "Workflows (last 30 days):"
gh api "/repos/$REPO/actions/runs?per_page=100" \
  --jq '.workflow_runs | group_by(.name) |
        map({name: .[0].name, runs: length,
             success: ([.[] | select(.conclusion == "success")] | length),
             failure: ([.[] | select(.conclusion == "failure")] | length),
             skipped: ([.[] | select(.conclusion == "skipped")] | length)}) |
        sort_by(-.runs)[] |
        "  \(.name): \(.runs) runs (\(.success) ok, \(.failure) fail, \(.skipped) skip)"'

echo ""
echo "=== Waste Indicators ==="
RUNS_DATA=$(gh api "/repos/$REPO/actions/runs?per_page=100" \
  --jq '{
    total: (.workflow_runs | length),
    skipped: [.workflow_runs[] | select(.conclusion == "skipped")] | length
  }')

SKIPPED=$(echo "$RUNS_DATA" | jq -r '.skipped')
TOTAL=$(echo "$RUNS_DATA" | jq -r '.total')
echo "Skipped runs: $SKIPPED/$TOTAL"

if [ -d ".github/workflows" ]; then
  MISSING_CONCURRENCY=0
  shopt -s nullglob
  for f in .github/workflows/*.yml .github/workflows/*.yaml; do
    if ! grep -q "concurrency:" "$f" 2>/dev/null; then
      MISSING_CONCURRENCY=$((MISSING_CONCURRENCY + 1))
    fi
  done
  shopt -u nullglob
  echo "Workflows missing concurrency: $MISSING_CONCURRENCY"
fi
