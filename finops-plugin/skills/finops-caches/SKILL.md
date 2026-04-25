---
description: Analyze cache usage - size, breakdown by prefix/branch, stale cache detection. Use when investigating GitHub Actions cache bloat, finding stale caches, or auditing cache key strategies.
args: "[repo|org:orgname]"
allowed-tools: Bash(gh api *), Bash(gh repo *), Bash(bash *), Read, TodoWrite
argument-hint: Repo (owner/name), org:orgname for org-wide, or empty for current repo
created: 2025-01-30
modified: 2026-04-25
reviewed: 2026-04-25
name: finops-caches
---

# /finops:caches

Analyze GitHub Actions cache usage - size breakdown, cache key patterns, branch distribution, and stale cache detection.

## When to Use This Skill

| Use this skill when... | Use a sibling instead when... |
|---|---|
| Cache usage is near the 10GB repo limit or unknown | You need a high-level repo health snapshot first — use `/finops:overview` |
| You need to identify stale or orphaned PR-branch caches | You want to compare cache footprints across many repos — use `/finops:compare` |
| You are reviewing cache key strategy and prefix breakdown | You want to optimize workflow triggers rather than caches — use `/finops:waste` |
| You want to track down a single bloated cache entry | You are investigating slow or noisy workflow runs — use `/finops:workflows` |

## Context

- Current repo URL: !`git remote get-url origin`

## Parameters

| Parameter | Description | Default |
|-----------|-------------|---------|
| `repo` | Repository in owner/name format | Current repository |
| `org:orgname` | Analyze org-wide cache usage | - |

## Execution

```bash
bash "${SKILL_DIR}/scripts/cache-analysis.sh" $ARGS
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

## Agentic Optimizations

| Context | Command |
|---------|---------|
| Cache list (JSON) | `gh api "/repos/{owner}/{repo}/actions/caches?per_page=100" --jq '.actions_caches'` |
| Total cache count | `gh api "/repos/{owner}/{repo}/actions/caches" --jq '.total_count'` |
| Delete stale cache | `gh api -X DELETE "/repos/{owner}/{repo}/actions/caches/{id}"` |
| Cache key search | `gh api "/repos/{owner}/{repo}/actions/caches?key=prefix" --jq '.actions_caches[].key'` |
| Compact summary | `bash "${SKILL_DIR}/scripts/cache-analysis.sh" $ARGS` |

## Post-actions

Based on findings, suggest:
- High % of limit -> Clean up stale caches, review key strategies
- Many PR caches -> Add cache cleanup workflow for closed PRs
- Large single caches -> Consider splitting or compressing
- Stale caches -> Provide cleanup command:
  ```bash
  # Delete stale caches
  gh api "/repos/$REPO/actions/caches?per_page=100" \
    --jq '.actions_caches[] | select(.last_accessed_at < "CUTOFF") | .id' | \
    while read id; do gh api -X DELETE "/repos/$REPO/actions/caches/$id"; done
  ```
