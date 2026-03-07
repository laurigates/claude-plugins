#!/usr/bin/env bash
# Cache Analysis
# Analyzes GitHub Actions cache usage: size breakdown, key patterns,
# branch distribution, stale cache detection.
# Usage: bash cache-analysis.sh [repo|org:orgname]
#
# Modes:
#   repo        Per-repo analysis (default: current repo)
#   org:orgname Org-wide top repos by cache size

# shellcheck disable=SC2016  # jq expressions use $ for variable references, not shell expansion
set -euo pipefail

ARG="${1:-$(gh repo view --json nameWithOwner --jq '.nameWithOwner')}"

# === Org-wide mode ===
if [[ "$ARG" == org:* ]]; then
  ORG="${ARG#org:}"
  echo "=== Org Cache Usage: $ORG ==="

  gh api "/orgs/$ORG/actions/cache/usage" \
    --jq '"Total: \(.total_active_caches_count) caches, \(.total_active_caches_size_in_bytes / 1024 / 1024 | floor)MB"'

  echo ""
  echo "=== Top Repos by Cache Size ==="

  gh repo list "$ORG" --json nameWithOwner --limit 100 --jq '.[].nameWithOwner' | while read -r repo; do
    result=$(gh api "/repos/$repo/actions/cache/usage" 2>/dev/null || echo "")
    if [ -n "$result" ]; then
      size=$(echo "$result" | jq -r '.active_caches_size_in_bytes // 0')
      count=$(echo "$result" | jq -r '.active_caches_count // 0')
      if [ "$size" -gt 0 ]; then
        echo "$repo|$count|$size"
      fi
    fi
  done | sort -t'|' -k3 -n -r | head -15 | while IFS='|' read -r repo count size; do
    mb=$((size / 1024 / 1024))
    echo "  $repo: $count caches, ${mb}MB"
  done

  exit 0
fi

# === Per-repo mode ===
REPO="$ARG"
echo "=== Cache Analysis: $REPO ==="

echo ""
echo "Summary:"
gh api "/repos/$REPO/actions/cache/usage" \
  --jq '"  \(.active_caches_count) caches, \(.active_caches_size_in_bytes / 1024 / 1024 | floor)MB used"'

SIZE=$(gh api "/repos/$REPO/actions/cache/usage" --jq '.active_caches_size_in_bytes')
LIMIT=$((10 * 1024 * 1024 * 1024))  # 10GB
PCT=$((SIZE * 100 / LIMIT))
echo "  $PCT% of 10GB limit"

echo ""
echo "=== By Key Prefix ==="
gh api "/repos/$REPO/actions/caches?per_page=100" \
  --jq '.actions_caches | group_by(.key | split("-") | .[0:2] | join("-")) |
        map({
          prefix: .[0].key | split("-") | .[0:2] | join("-"),
          count: length,
          size_mb: (map(.size_in_bytes) | add / 1024 / 1024 | floor)
        }) |
        sort_by(-.size_mb)[] |
        "  \(.prefix): \(.count) caches, \(.size_mb)MB"'

echo ""
echo "=== By Branch ==="
gh api "/repos/$REPO/actions/caches?per_page=100" \
  --jq '.actions_caches | group_by(.ref) |
        map({
          branch: (.[0].ref | sub("refs/heads/"; "") | sub("refs/pull/"; "PR ")),
          count: length,
          size_mb: (map(.size_in_bytes) | add / 1024 / 1024 | floor)
        }) |
        sort_by(-.size_mb)[] |
        "  \(.branch): \(.count) caches, \(.size_mb)MB"'

echo ""
echo "=== Largest Caches ==="
gh api "/repos/$REPO/actions/caches?per_page=100" \
  --jq '.actions_caches | sort_by(-.size_in_bytes) | .[0:10][] |
        "  \(.key | .[0:60]): \(.size_in_bytes / 1024 / 1024 | floor)MB"'

echo ""
echo "=== Stale Caches (>7 days old) ==="
CUTOFF=$(date -d '7 days ago' +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -v-7d +%Y-%m-%dT%H:%M:%SZ)
gh api "/repos/$REPO/actions/caches?per_page=100" \
  --jq --arg cutoff "$CUTOFF" '
    [.actions_caches[] | select(.last_accessed_at < $cutoff)] |
    {
      count: length,
      size_mb: (map(.size_in_bytes) | add / 1024 / 1024 | floor // 0),
      oldest: (sort_by(.last_accessed_at) | .[0].last_accessed_at // "none")
    } |
    "  \(.count) stale caches, \(.size_mb)MB reclaimable\n  Oldest: \(.oldest)"'

echo ""
echo "=== PR Branch Caches ==="
gh api "/repos/$REPO/actions/caches?per_page=100" \
  --jq '[.actions_caches[] | select(.ref | startswith("refs/pull/"))] |
        {
          count: length,
          size_mb: (map(.size_in_bytes) | add / 1024 / 1024 | floor // 0)
        } |
        "  \(.count) PR caches, \(.size_mb)MB (check if PRs are merged/closed)"'
