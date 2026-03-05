#!/usr/bin/env bash
# Compare Repos FinOps
# Compares GitHub Actions FinOps metrics across repositories in an organization.
# Usage: bash compare-repos.sh <org> [repo1 repo2 ...] [--limit N]
#
# Args:
#   org       GitHub organization name (required)
#   repos     Space-separated repo names (default: all org repos)
#   --limit   Max repos for auto-discovery (default: 30)

set -euo pipefail

if [[ $# -eq 0 ]]; then
  echo "Usage: bash compare-repos.sh <org> [repo1 repo2 ...] [--limit N]"
  exit 1
fi

ORG="$1"
shift

LIMIT=30
REPOS=()
while [[ $# -gt 0 ]]; do
  case $1 in
    --limit)
      LIMIT="$2"
      shift 2
      ;;
    *)
      REPOS+=("$1")
      shift
      ;;
  esac
done

echo "=== FinOps Comparison: $ORG ==="
echo ""

# Discover repos if not specified
if [[ ${#REPOS[@]} -eq 0 ]]; then
  echo "Discovering repos (limit: $LIMIT)..."
  mapfile -t REPOS < <(gh repo list "$ORG" --json name --limit "$LIMIT" --jq '.[].name')
  echo "Found ${#REPOS[@]} repos"
  echo ""
fi

# === Cache Usage ===
echo "=== Cache Usage ==="
printf "%-40s %10s %12s\n" "Repository" "Caches" "Size (MB)"
printf "%-40s %10s %12s\n" "----------" "------" "---------"

for repo in "${REPOS[@]}"; do
  result=$(gh api "/repos/$ORG/$repo/actions/cache/usage" 2>/dev/null || echo "")
  if [[ -n "$result" ]]; then
    count=$(echo "$result" | jq -r '.active_caches_count // 0')
    size=$(echo "$result" | jq -r '.active_caches_size_in_bytes // 0')
    size_mb=$((size / 1024 / 1024))
    if [[ "$count" -gt 0 || "$size_mb" -gt 0 ]]; then
      printf "%-40s %10d %12d\n" "$repo" "$count" "$size_mb"
    fi
  fi
done

echo ""

# === Workflow Activity ===
echo "=== Workflow Activity (last 30 days) ==="
printf "%-40s %8s %8s %8s %10s\n" "Repository" "Runs" "Success" "Failed" "Skip Rate"
printf "%-40s %8s %8s %8s %10s\n" "----------" "----" "-------" "------" "---------"

for repo in "${REPOS[@]}"; do
  result=$(gh api "/repos/$ORG/$repo/actions/runs?per_page=100" 2>/dev/null || echo "")
  if [[ -n "$result" ]]; then
    stats=$(echo "$result" | jq -r '
      .workflow_runs |
      if length > 0 then
        {
          total: length,
          success: ([.[] | select(.conclusion == "success")] | length),
          failed: ([.[] | select(.conclusion == "failure")] | length),
          skipped: ([.[] | select(.conclusion == "skipped")] | length)
        } |
        "\(.total)\t\(.success)\t\(.failed)\t\(if .total > 0 then (.skipped * 100 / .total | floor) else 0 end)%"
      else empty end
    ')
    if [[ -n "$stats" ]]; then
      printf "%-40s %s\n" "$repo" "$stats"
    fi
  fi
done

echo ""

# === Failure Rates ===
echo "=== Failure Rates (top 15) ==="
printf "%-40s %8s %8s %10s\n" "Repository" "Total" "Failed" "Rate"
printf "%-40s %8s %8s %10s\n" "----------" "-----" "------" "----"

{
  for repo in "${REPOS[@]}"; do
    result=$(gh api "/repos/$ORG/$repo/actions/runs?per_page=100&status=completed" 2>/dev/null || echo "")
    if [[ -n "$result" ]]; then
      stats=$(echo "$result" | jq -r '
        .workflow_runs |
        if length > 0 then
          {
            total: length,
            failed: ([.[] | select(.conclusion == "failure")] | length)
          } |
          select(.failed > 0) |
          "\(.total)\t\(.failed)\t\(.failed * 100 / .total | floor)%"
        else empty end
      ')
      if [[ -n "$stats" ]]; then
        printf "%-40s %s\n" "$repo" "$stats"
      fi
    fi
  done
} | head -15

echo ""

# === Active Workflows ===
echo "=== Active Workflows ==="
printf "%-40s %10s\n" "Repository" "Workflows"
printf "%-40s %10s\n" "----------" "---------"

for repo in "${REPOS[@]}"; do
  count=$(gh workflow list --repo "$ORG/$repo" --json id --jq 'length' 2>/dev/null || echo "0")
  if [[ "$count" -gt 0 ]]; then
    printf "%-40s %10s\n" "$repo" "$count"
  fi
done

echo ""

# === Summary ===
echo "=== Summary ==="

TOTAL_CACHE=0
for repo in "${REPOS[@]}"; do
  size=$(gh api "/repos/$ORG/$repo/actions/cache/usage" --jq '.active_caches_size_in_bytes // 0' 2>/dev/null || echo "0")
  TOTAL_CACHE=$((TOTAL_CACHE + size))
done
echo "Total cache usage: $((TOTAL_CACHE / 1024 / 1024))MB across ${#REPOS[@]} repos"

echo ""
echo "Repos exceeding 1GB cache:"
for repo in "${REPOS[@]}"; do
  size=$(gh api "/repos/$ORG/$repo/actions/cache/usage" --jq '.active_caches_size_in_bytes // 0' 2>/dev/null || echo "0")
  if [[ "$size" -gt 1073741824 ]]; then
    echo "  $repo: $((size / 1024 / 1024))MB"
  fi
done

echo ""
echo "Repos with >20% failure rate:"
for repo in "${REPOS[@]}"; do
  result=$(gh api "/repos/$ORG/$repo/actions/runs?per_page=50&status=completed" 2>/dev/null || echo "")
  if [[ -n "$result" ]]; then
    rate=$(echo "$result" | jq -r '
      .workflow_runs |
      if length > 0 then
        ([.[] | select(.conclusion == "failure")] | length) * 100 / length | floor
      else 0 end
    ')
    if [[ "$rate" -gt 20 ]]; then
      echo "  $repo: ${rate}% failure rate"
    fi
  fi
done
