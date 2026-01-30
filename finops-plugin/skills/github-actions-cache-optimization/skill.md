---
model: haiku
name: github-actions-cache-optimization
description: |
  Analyze and optimize GitHub Actions cache usage. Use when investigating
  cache bloat, identifying stale caches, optimizing cache keys, or comparing
  cache usage across repositories.
allowed-tools: Bash(gh api *), Bash(gh repo *), Bash(gh cache *), Read, Grep, Glob, TodoWrite
created: 2025-01-30
modified: 2025-01-30
reviewed: 2025-01-30
---

# GitHub Actions Cache Optimization

Analyze cache usage, identify bloat, and optimize cache strategies for GitHub Actions.

## When to Use This Skill

| Use this skill when... | Use X instead when... |
|------------------------|----------------------|
| Analyzing cache size and count | Investigating workflow run failures → gh-workflow-monitoring |
| Identifying stale or bloated caches | Analyzing billing/minutes → github-actions-finops |
| Optimizing cache key strategies | Setting up new cache actions → github-actions-workflows |
| Cleaning up old caches | General workflow efficiency → github-actions-finops |

## Cache Limits

| Limit | Value |
|-------|-------|
| Max cache size | 10 GB per repository |
| Max single entry | 10 GB |
| Retention | 7 days without access |
| Eviction | LRU when limit exceeded |

## Org-Level Cache Usage

```bash
# Total cache usage across org
gh api /orgs/$GITHUB_ORG/actions/cache/usage \
  --jq '{total_active_caches_count, total_active_caches_size_in_bytes}'

# Formatted output
gh api /orgs/$GITHUB_ORG/actions/cache/usage \
  --jq '"\(.total_active_caches_count) caches, \(.total_active_caches_size_in_bytes / 1024 / 1024 | floor)MB total"'
```

## Per-Repo Cache Usage

### Cache Summary

```bash
# Basic cache stats for repo
gh api "/repos/$OWNER/$REPO/actions/cache/usage" \
  --jq '{active_caches_count, active_caches_size_in_bytes}'

# Formatted
gh api "/repos/$OWNER/$REPO/actions/cache/usage" \
  --jq '"\(.active_caches_count) caches, \(.active_caches_size_in_bytes / 1024 / 1024 | floor)MB"'
```

### Cache List and Breakdown

```bash
# List all caches
gh api "/repos/$OWNER/$REPO/actions/caches?per_page=100" \
  --jq '.actions_caches[] | "\(.key): \(.size_in_bytes / 1024 / 1024 | floor)MB, last used: \(.last_accessed_at)"'

# Group by key prefix (first 3 segments)
gh api "/repos/$OWNER/$REPO/actions/caches?per_page=100" \
  --jq '.actions_caches | group_by(.key | split("-") | .[0:3] | join("-")) |
        map({prefix: .[0].key | split("-") | .[0:3] | join("-"),
             count: length,
             size_mb: (map(.size_in_bytes) | add / 1024 / 1024 | floor)}) |
        sort_by(-.size_mb)'

# Caches by branch
gh api "/repos/$OWNER/$REPO/actions/caches?per_page=100" \
  --jq '.actions_caches | group_by(.ref) |
        map({branch: .[0].ref, count: length,
             size_mb: (map(.size_in_bytes) | add / 1024 / 1024 | floor)}) |
        sort_by(-.size_mb)'
```

### Stale Cache Detection

```bash
# Caches not accessed in 7+ days (candidates for cleanup)
gh api "/repos/$OWNER/$REPO/actions/caches?per_page=100" \
  --jq --arg cutoff "$(date -d '7 days ago' +%Y-%m-%dT%H:%M:%SZ)" \
  '.actions_caches[] | select(.last_accessed_at < $cutoff) |
   "\(.key): \(.size_in_bytes / 1024 / 1024 | floor)MB, last: \(.last_accessed_at)"'

# macOS date variant
gh api "/repos/$OWNER/$REPO/actions/caches?per_page=100" \
  --jq --arg cutoff "$(date -v-7d +%Y-%m-%dT%H:%M:%SZ)" \
  '.actions_caches[] | select(.last_accessed_at < $cutoff) | ...'
```

## Cache Cleanup

### Delete Specific Cache

```bash
# Delete cache by ID
gh api -X DELETE "/repos/$OWNER/$REPO/actions/caches/$CACHE_ID"

# Delete cache by key (exact match)
gh api -X DELETE "/repos/$OWNER/$REPO/actions/caches?key=$CACHE_KEY"
```

### Bulk Cleanup

```bash
# Delete all caches for a specific branch
gh api "/repos/$OWNER/$REPO/actions/caches?per_page=100&ref=refs/heads/$BRANCH" \
  --jq '.actions_caches[].id' | while read id; do
    gh api -X DELETE "/repos/$OWNER/$REPO/actions/caches/$id"
  done

# Delete caches matching key prefix
gh api "/repos/$OWNER/$REPO/actions/caches?per_page=100" \
  --jq '.actions_caches[] | select(.key | startswith("PREFIX-")) | .id' | while read id; do
    gh api -X DELETE "/repos/$OWNER/$REPO/actions/caches/$id"
  done
```

## Cache Bloat Indicators

| Indicator | Threshold | Issue |
|-----------|-----------|-------|
| Total size | >5 GB | Approaching 10GB limit |
| Cache count | >50 | Too many keys/branches |
| Stale caches | >20% older than 7d | Inefficient key strategy |
| Single cache | >2 GB | Consider splitting |
| Branch caches | Many closed PR branches | Missing cleanup workflow |

## Cache Key Strategies

### Good Key Patterns

```yaml
# OS + lockfile hash (recommended)
key: ${{ runner.os }}-node-${{ hashFiles('**/package-lock.json') }}

# With restore keys for partial matches
restore-keys: |
  ${{ runner.os }}-node-

# Include tool version
key: ${{ runner.os }}-node-${{ matrix.node-version }}-${{ hashFiles('**/package-lock.json') }}
```

### Problematic Patterns

| Pattern | Issue | Fix |
|---------|-------|-----|
| `${{ github.sha }}` in key | Never reused | Use lockfile hash |
| `${{ github.run_id }}` | Never reused | Remove from key |
| No `restore-keys` | Cache misses | Add fallback keys |
| Branch in key | PR cache bloat | Use base branch fallback |

## Cache Cleanup Workflow

Add to repository for automatic cleanup:

```yaml
name: Cache Cleanup
on:
  pull_request:
    types: [closed]
  schedule:
    - cron: '0 0 * * 0'  # Weekly

jobs:
  cleanup:
    runs-on: ubuntu-latest
    steps:
      - name: Cleanup PR caches
        if: github.event_name == 'pull_request'
        run: |
          gh api "/repos/${{ github.repository }}/actions/caches?ref=refs/heads/${{ github.head_ref }}" \
            --jq '.actions_caches[].id' | while read id; do
              gh api -X DELETE "/repos/${{ github.repository }}/actions/caches/$id" || true
            done
        env:
          GH_TOKEN: ${{ secrets.GITHUB_TOKEN }}

      - name: Cleanup stale caches
        if: github.event_name == 'schedule'
        run: |
          # Delete caches not accessed in 14 days
          cutoff=$(date -d '14 days ago' +%Y-%m-%dT%H:%M:%SZ)
          gh api "/repos/${{ github.repository }}/actions/caches?per_page=100" \
            --jq --arg cutoff "$cutoff" \
            '.actions_caches[] | select(.last_accessed_at < $cutoff) | .id' | while read id; do
              gh api -X DELETE "/repos/${{ github.repository }}/actions/caches/$id" || true
            done
        env:
          GH_TOKEN: ${{ secrets.GITHUB_TOKEN }}
```

## Multi-Repo Cache Comparison

```bash
# Compare cache usage across repos
for repo in repo1 repo2 repo3; do
  echo "=== $repo ==="
  gh api "/repos/$GITHUB_ORG/$repo/actions/cache/usage" \
    --jq '"\(.active_caches_count) caches, \(.active_caches_size_in_bytes / 1024 / 1024 | floor)MB"'
done

# Full org scan
gh repo list $GITHUB_ORG --json nameWithOwner --limit 100 --jq '.[].nameWithOwner' | while read repo; do
  size=$(gh api "/repos/$repo/actions/cache/usage" --jq '.active_caches_size_in_bytes // 0' 2>/dev/null)
  if [ "$size" -gt 0 ]; then
    echo "$repo: $((size / 1024 / 1024))MB"
  fi
done | sort -t: -k2 -n -r | head -20
```

## Agentic Optimizations

| Context | Command |
|---------|---------|
| Org total | `gh api /orgs/$ORG/actions/cache/usage --jq '.total_active_caches_size_in_bytes / 1024 / 1024 \| floor'` |
| Repo summary | `gh api "/repos/$O/$R/actions/cache/usage" --jq '"\(.active_caches_count) caches, \(.active_caches_size_in_bytes / 1048576 \| floor)MB"'` |
| List caches | `gh api "/repos/$O/$R/actions/caches?per_page=30" --jq '.actions_caches[] \| "\(.key): \(.size_in_bytes / 1048576 \| floor)MB"'` |
| By prefix | `gh api "..." --jq '.actions_caches \| group_by(.key \| split("-") \| .[0]) \| map({prefix: .[0].key \| split("-") \| .[0], count: length})'` |
| Delete cache | `gh api -X DELETE "/repos/$O/$R/actions/caches/$ID"` |

## Quick Reference

| API Endpoint | Method | Purpose |
|--------------|--------|---------|
| `/orgs/{org}/actions/cache/usage` | GET | Org-wide cache stats |
| `/repos/{owner}/{repo}/actions/cache/usage` | GET | Repo cache stats |
| `/repos/{owner}/{repo}/actions/caches` | GET | List all caches |
| `/repos/{owner}/{repo}/actions/caches/{id}` | DELETE | Delete specific cache |
| `/repos/{owner}/{repo}/actions/caches?key={key}` | DELETE | Delete by key |

## See Also

- **github-actions-finops** - Billing and workflow efficiency analysis
- **gh-workflow-monitoring** - Watching workflow runs
