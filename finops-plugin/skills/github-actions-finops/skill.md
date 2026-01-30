---
model: haiku
name: github-actions-finops
description: |
  Analyze GitHub Actions billing, workflow efficiency, and waste patterns.
  Use when investigating CI/CD costs, identifying wasted runs, or optimizing
  workflow triggers. Covers org-level billing, per-repo workflow analysis,
  and waste pattern detection.
allowed-tools: Bash(gh api *), Bash(gh repo *), Bash(gh workflow *), Bash(gh run *), Read, Grep, Glob, TodoWrite
created: 2025-01-30
modified: 2025-01-30
reviewed: 2025-01-30
---

# GitHub Actions FinOps

Analyze GitHub Actions usage, costs, and efficiency across organizations and repositories.

## When to Use This Skill

| Use this skill when... | Use X instead when... |
|------------------------|----------------------|
| Analyzing CI/CD costs and billing | Debugging a specific failed workflow → gh-workflow-monitoring |
| Identifying wasted workflow runs | Setting up new workflows → github-actions-workflows |
| Investigating workflow trigger patterns | Managing cache keys → github-actions-cache-optimization |
| Comparing efficiency across repos | Monitoring a single run → gh-workflow-monitoring |

## Environment Variables

Use `$GITHUB_ORG` for organization name in commands. Detect current org:

```bash
# Get orgs user belongs to
gh api user/orgs --jq '.[].login'

# Get org from current repo
gh repo view --json owner --jq '.owner.login'
```

## Org-Level Metrics

### Billing Summary (requires admin)

```bash
# Actions billing - minutes used
gh api /orgs/$GITHUB_ORG/settings/billing/actions \
  --jq '{included_minutes, total_minutes_used, total_paid_minutes_used}'

# Packages billing
gh api /orgs/$GITHUB_ORG/settings/billing/packages \
  --jq '{included_gigabytes_bandwidth, total_gigabytes_bandwidth_used}'

# Shared storage billing
gh api /orgs/$GITHUB_ORG/settings/billing/shared-storage \
  --jq '{days_left_in_billing_cycle, estimated_paid_storage_for_month}'
```

### List Org Repositories

```bash
# List all repos in org
gh repo list $GITHUB_ORG --json nameWithOwner --limit 100

# With additional metadata
gh repo list $GITHUB_ORG --json nameWithOwner,pushedAt,isArchived --limit 100 \
  --jq '.[] | select(.isArchived == false)'
```

## Per-Repo Workflow Analysis

### List Workflows

```bash
# List workflows for a repo
gh workflow list --repo $OWNER/$REPO --json id,name,path,state

# Active workflows only
gh workflow list --repo $OWNER/$REPO --json id,name,state \
  --jq '.[] | select(.state == "active")'
```

### Workflow Runs Analysis

```bash
# Runs in last 30 days grouped by workflow
gh api "/repos/$OWNER/$REPO/actions/runs?per_page=100&created=>$(date -d '30 days ago' +%Y-%m-%d)" \
  --jq '.workflow_runs | group_by(.name) |
        map({workflow: .[0].name, runs: length,
             conclusions: (group_by(.conclusion) | map({(.[0].conclusion // "unknown"): length}) | add)}) |
        sort_by(-.runs)'

# macOS date variant
gh api "/repos/$OWNER/$REPO/actions/runs?per_page=100&created=>$(date -v-30d +%Y-%m-%d)" \
  --jq '...'
```

### Duration Calculations

```bash
# Recent runs with duration
gh api "/repos/$OWNER/$REPO/actions/runs?per_page=20&status=completed" \
  --jq '.workflow_runs | group_by(.name) |
        map({name: .[0].name, count: length,
             total_seconds: (map(.run_started_at as $start | .updated_at as $end |
                            (($end | fromdateiso8601) - ($start | fromdateiso8601))) | add)}) |
        sort_by(-.count) | .[] | "\(.name): \(.count) runs, ~\(.total_seconds/60|floor)min total"'
```

## Waste Pattern Detection

### Skipped Runs (Wasted Triggers)

```bash
# Skipped runs by workflow
gh api "/repos/$OWNER/$REPO/actions/runs?per_page=100&created=>$(date -d '30 days ago' +%Y-%m-%d)" \
  --jq '[.workflow_runs[] | select(.conclusion == "skipped")] |
        group_by(.name) | map({workflow: .[0].name, skipped: length}) |
        sort_by(-.skipped)'
```

### Trigger Pattern Analysis

```bash
# Analyze triggers for specific workflow
gh api "/repos/$OWNER/$REPO/actions/runs?per_page=20" \
  --jq '.workflow_runs[] | select(.name == "WORKFLOW_NAME") |
        "\(.id) | \(.event) | \(.conclusion) | trigger: \(.triggering_actor.login)"'

# Bot-triggered runs
gh api "/repos/$OWNER/$REPO/actions/runs?per_page=100" \
  --jq '[.workflow_runs[] | select(.triggering_actor.type == "Bot")] | length'
```

### High-Frequency Workflows

```bash
# Workflows with >50 runs/month (candidates for path filters)
gh api "/repos/$OWNER/$REPO/actions/runs?per_page=100&created=>$(date -d '30 days ago' +%Y-%m-%d)" \
  --jq '.workflow_runs | group_by(.name) | map(select(length > 50)) |
        map({workflow: .[0].name, runs: length})'
```

## Key Waste Indicators

| Metric | API/Command | Red Flag |
|--------|-------------|----------|
| Skipped runs | `conclusion == "skipped"` | >10% of total runs |
| Bot triggers | `triggering_actor.type == "Bot"` | Bot-to-bot chains |
| Long durations | Duration calculation | >10min average |
| High frequency | Group by workflow | >50 runs/month without path filters |
| Duplicate runs | Same commit, multiple runs | Missing concurrency groups |

## Common Fixes

### 1. Filter Bot Triggers

Add to workflow job:
```yaml
jobs:
  build:
    if: github.event.sender.type != 'Bot'
```

### 2. Add Concurrency Groups

```yaml
concurrency:
  group: ${{ github.workflow }}-${{ github.ref }}
  cancel-in-progress: true  # For PR workflows
```

### 3. Add Path Filters

```yaml
on:
  push:
    paths:
      - 'src/**'
      - 'package.json'
    paths-ignore:
      - '**.md'
      - 'docs/**'
```

### 4. Cancel Duplicate Runs

```yaml
concurrency:
  group: ${{ github.workflow }}-${{ github.ref }}
  cancel-in-progress: true
```

## Workflow File Analysis

```bash
# Check for missing concurrency in workflow files
for f in .github/workflows/*.yml .github/workflows/*.yaml; do
  if [ -f "$f" ] && ! grep -q "concurrency:" "$f"; then
    echo "Missing concurrency: $f"
  fi
done

# Check for missing path filters
for f in .github/workflows/*.yml .github/workflows/*.yaml; do
  if [ -f "$f" ] && ! grep -q "paths:" "$f"; then
    echo "No path filter: $f"
  fi
done
```

## Agentic Optimizations

| Context | Command |
|---------|---------|
| Org billing | `gh api /orgs/$ORG/settings/billing/actions --jq '{included_minutes, total_minutes_used}'` |
| List repos | `gh repo list $ORG --json nameWithOwner --limit 100` |
| Workflow runs | `gh api "/repos/$O/$R/actions/runs?per_page=100" --jq '.workflow_runs \| length'` |
| Skipped count | `gh api "..." --jq '[.workflow_runs[] \| select(.conclusion == "skipped")] \| length'` |
| Bot triggers | `gh api "..." --jq '[.workflow_runs[] \| select(.triggering_actor.type == "Bot")] \| length'` |

## Quick Reference

| API Endpoint | Purpose | Admin Required |
|--------------|---------|----------------|
| `/orgs/{org}/settings/billing/actions` | Minutes usage | Yes |
| `/orgs/{org}/actions/cache/usage` | Org cache stats | No |
| `/repos/{owner}/{repo}/actions/runs` | Workflow runs | No |
| `/repos/{owner}/{repo}/actions/workflows` | Workflow definitions | No |

## See Also

- **github-actions-cache-optimization** - Cache-specific analysis and cleanup
- **gh-workflow-monitoring** - Watching individual workflow runs
