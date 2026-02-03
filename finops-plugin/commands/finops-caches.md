---
model: haiku
description: Analyze cache usage - size, breakdown by prefix/branch, stale cache detection
args: "[repo|org:orgname]"
allowed-tools: Bash(gh api *), Bash(gh repo *), Read, TodoWrite
argument-hint: Repo (owner/name), org:orgname for org-wide, or empty for current repo
created: 2025-01-30
modified: 2025-01-30
reviewed: 2025-01-30
---

# /finops:caches

Analyze GitHub Actions cache usage - size breakdown, cache key patterns, branch distribution, and stale cache detection.

## Context

- Current repo: !`gh repo view --json nameWithOwner --jq '.nameWithOwner' 2>/dev/null`
- Repo owner: !`gh repo view --json owner --jq '.owner.login' 2>/dev/null`

## Parameters

| Parameter | Description | Default |
|-----------|-------------|---------|
| `repo` | Repository in owner/name format | Current repository |
| `org:orgname` | Analyze org-wide cache usage | - |

## Execution

### Org-wide Analysis (if arg starts with "org:")

```bash
ORG="${1#org:}"
echo "=== Org Cache Usage: $ORG ==="

# Org total
gh api /orgs/$ORG/actions/cache/usage \
  --jq '"Total: \(.total_active_caches_count) caches, \(.total_active_caches_size_in_bytes / 1024 / 1024 | floor)MB"'

echo ""
echo "=== Top Repos by Cache Size ==="

# Iterate repos and get cache usage
gh repo list $ORG --json nameWithOwner --limit 100 --jq '.[].nameWithOwner' | while read repo; do
  result=$(gh api "/repos/$repo/actions/cache/usage" 2>/dev/null)
  if [ -n "$result" ]; then
    size=$(echo "$result" | jq -r '.active_caches_size_in_bytes // 0')
    count=$(echo "$result" | jq -r '.active_caches_count // 0')
    if [ "$size" -gt 0 ]; then
      echo "$repo|$count|$size"
    fi
  fi
done | sort -t'|' -k3 -n -r | head -15 | while IFS='|' read repo count size; do
  mb=$((size / 1024 / 1024))
  echo "  $repo: $count caches, ${mb}MB"
done
```

### Per-Repo Analysis (default)

**1. Determine repository:**

```bash
REPO="${1:-$(gh repo view --json nameWithOwner --jq '.nameWithOwner')}"
echo "=== Cache Analysis: $REPO ==="
```

**2. Cache summary:**

```bash
echo ""
echo "Summary:"
gh api "/repos/$REPO/actions/cache/usage" \
  --jq '"  \(.active_caches_count) caches, \(.active_caches_size_in_bytes / 1024 / 1024 | floor)MB used"'

# Check against limit
SIZE=$(gh api "/repos/$REPO/actions/cache/usage" --jq '.active_caches_size_in_bytes')
LIMIT=$((10 * 1024 * 1024 * 1024))  # 10GB
PCT=$((SIZE * 100 / LIMIT))
echo "  $PCT% of 10GB limit"
```

**3. Breakdown by cache key prefix:**

```bash
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
```

**4. Breakdown by branch:**

```bash
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
```

**5. Largest individual caches:**

```bash
echo ""
echo "=== Largest Caches ==="
gh api "/repos/$REPO/actions/caches?per_page=100" \
  --jq '.actions_caches | sort_by(-.size_in_bytes) | .[0:10][] |
        "  \(.key | .[0:60]): \(.size_in_bytes / 1024 / 1024 | floor)MB"'
```

**6. Stale cache detection (not accessed in 7+ days):**

```bash
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
```

**7. PR branch caches (potential cleanup):**

```bash
echo ""
echo "=== PR Branch Caches ==="
gh api "/repos/$REPO/actions/caches?per_page=100" \
  --jq '[.actions_caches[] | select(.ref | startswith("refs/pull/"))] |
        {
          count: length,
          size_mb: (map(.size_in_bytes) | add / 1024 / 1024 | floor // 0)
        } |
        "  \(.count) PR caches, \(.size_mb)MB (check if PRs are merged/closed)"'
```

## Output Format

```
=== Cache Analysis: org/repo ===

Summary:
  45 caches, 2340MB used
  23% of 10GB limit

=== By Key Prefix ===
  node-modules: 12 caches, 1200MB
  playwright: 8 caches, 800MB
  turbo: 15 caches, 300MB

=== By Branch ===
  main: 10 caches, 500MB
  develop: 8 caches, 400MB
  PR 123: 3 caches, 150MB
  PR 118: 3 caches, 140MB

=== Largest Caches ===
  node-modules-linux-abc123: 180MB
  playwright-linux-def456: 150MB

=== Stale Caches (>7 days old) ===
  8 stale caches, 450MB reclaimable
  Oldest: 2025-01-15T10:30:00Z

=== PR Branch Caches ===
  12 PR caches, 580MB (check if PRs are merged/closed)
```

## Post-actions

Based on findings, suggest:
- High % of limit → Clean up stale caches, review key strategies
- Many PR caches → Add cache cleanup workflow for closed PRs
- Large single caches → Consider splitting or compressing
- Stale caches → Provide cleanup command:
  ```bash
  # Delete stale caches
  gh api "/repos/$REPO/actions/caches?per_page=100" \
    --jq '.actions_caches[] | select(.last_accessed_at < "CUTOFF") | .id' | \
    while read id; do gh api -X DELETE "/repos/$REPO/actions/caches/$id"; done
  ```
