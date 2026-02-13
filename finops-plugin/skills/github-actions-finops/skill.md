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
modified: 2026-02-11
reviewed: 2025-01-30
---

# GitHub Actions FinOps

Analyze GitHub Actions usage, costs, and efficiency across organizations and repositories.

## When to Use This Skill

| Use this skill when... | Use X instead when... |
|------------------------|----------------------|
| Analyzing CI/CD costs and billing | Debugging a specific failed workflow -- use gh-workflow-monitoring |
| Identifying wasted workflow runs | Setting up new workflows -- use github-actions-workflows |
| Investigating workflow trigger patterns | Managing cache keys -- use github-actions-cache-optimization |
| Comparing efficiency across repos | Monitoring a single run -- use gh-workflow-monitoring |

## Context

- Current repo: !`gh repo view --json nameWithOwner --jq '.nameWithOwner' 2>/dev/null`
- Repo owner: !`gh repo view --json owner --jq '.owner.login' 2>/dev/null`
- Owner type: !`gh repo view --json owner --jq '.owner.__typename' 2>/dev/null`
- Workflow files: !`find .github/workflows -maxdepth 1 \( -name '*.yml' -o -name '*.yaml' \) 2>/dev/null`
- Active workflows: !`gh workflow list --json id,name,state --jq '[.[] | select(.state == "active")] | length' 2>/dev/null`

## Execution

Execute this GitHub Actions FinOps analysis:

### Step 1: Determine scope

Read the Context values above. Set `$OWNER` and `$REPO` from the current repo. If owner type is "Organization", set `$GITHUB_ORG` to the repo owner for org-level billing queries.

If no repo context is available, ask the user for the target organization or repository.

### Step 2: Fetch org-level billing (if org and admin access)

Query the Actions billing API:

```bash
gh api /orgs/$GITHUB_ORG/settings/billing/actions \
  --jq '{included_minutes, total_minutes_used, total_paid_minutes_used}'
```

If this returns a permissions error, note that admin access is required and skip to Step 3.

Optionally also check packages and storage billing:

```bash
gh api /orgs/$GITHUB_ORG/settings/billing/packages \
  --jq '{included_gigabytes_bandwidth, total_gigabytes_bandwidth_used}'

gh api /orgs/$GITHUB_ORG/settings/billing/shared-storage \
  --jq '{days_left_in_billing_cycle, estimated_paid_storage_for_month}'
```

### Step 3: Analyze workflow runs

Fetch recent runs and group by workflow:

```bash
gh api "/repos/$OWNER/$REPO/actions/runs?per_page=100" \
  --jq '.workflow_runs | group_by(.name) |
        map({workflow: .[0].name, runs: length,
             conclusions: (group_by(.conclusion) | map({(.[0].conclusion // "unknown"): length}) | add)}) |
        sort_by(-.runs)'
```

Calculate run durations:

```bash
gh api "/repos/$OWNER/$REPO/actions/runs?per_page=20&status=completed" \
  --jq '.workflow_runs | group_by(.name) |
        map({name: .[0].name, count: length,
             total_seconds: (map(.run_started_at as $start | .updated_at as $end |
                            (($end | fromdateiso8601) - ($start | fromdateiso8601))) | add)}) |
        sort_by(-.count) | .[] | "\(.name): \(.count) runs, ~\(.total_seconds/60|floor)min total"'
```

### Step 4: Detect waste patterns

Check each waste indicator:

**Skipped runs:**

```bash
gh api "/repos/$OWNER/$REPO/actions/runs?per_page=100" \
  --jq '[.workflow_runs[] | select(.conclusion == "skipped")] |
        group_by(.name) | map({workflow: .[0].name, skipped: length}) |
        sort_by(-.skipped)'
```

**Bot-triggered runs:**

```bash
gh api "/repos/$OWNER/$REPO/actions/runs?per_page=100" \
  --jq '[.workflow_runs[] | select(.triggering_actor.type == "Bot")] | length'
```

**High-frequency workflows (candidates for path filters):**

```bash
gh api "/repos/$OWNER/$REPO/actions/runs?per_page=100" \
  --jq '.workflow_runs | group_by(.name) | map(select(length > 50)) |
        map({workflow: .[0].name, runs: length})'
```

### Step 5: Analyze workflow files

Read each workflow file from `.github/workflows/` and check for:

1. Missing `concurrency:` groups
2. Missing `paths:` filters on push/PR triggers
3. Missing bot-trigger guards (`if: github.event.sender.type != 'Bot'`)

### Step 6: Report findings

Print a summary with these sections:

1. **Billing summary** (if available): minutes used, paid minutes, days left in cycle
2. **Workflow run counts**: table of workflows with run counts and conclusion breakdown
3. **Waste indicators**: skipped runs, bot triggers, high-frequency workflows, missing concurrency groups
4. **Recommendations**: specific fixes for each waste pattern detected

Use these thresholds for flagging:

| Metric | Red Flag Threshold |
|--------|-------------------|
| Skipped runs | >10% of total runs |
| Bot triggers | Bot-to-bot chains detected |
| Long durations | >10min average |
| High frequency | >50 runs/month without path filters |
| Duplicate runs | Same commit triggers multiple runs |

### Step 7: Suggest fixes

For each waste pattern found, recommend the specific fix:

| Pattern | Fix |
|---------|-----|
| Bot-triggered waste | Add `if: github.event.sender.type != 'Bot'` to jobs |
| Missing concurrency | Add `concurrency: { group: ${{ github.workflow }}-${{ github.ref }}, cancel-in-progress: true }` |
| No path filters | Add `paths:` with relevant source directories |
| Duplicate runs | Add concurrency groups with `cancel-in-progress: true` |

## API Reference

| Endpoint | Purpose | Admin Required |
|----------|---------|----------------|
| `/orgs/{org}/settings/billing/actions` | Minutes usage | Yes |
| `/orgs/{org}/settings/billing/packages` | Package bandwidth | Yes |
| `/orgs/{org}/settings/billing/shared-storage` | Storage billing | Yes |
| `/orgs/{org}/actions/cache/usage` | Org cache stats | No |
| `/repos/{owner}/{repo}/actions/runs` | Workflow runs | No |
| `/repos/{owner}/{repo}/actions/workflows` | Workflow definitions | No |

## Agentic Optimizations

| Context | Command |
|---------|---------|
| Org billing | `gh api /orgs/$ORG/settings/billing/actions --jq '{included_minutes, total_minutes_used}'` |
| List repos | `gh repo list $ORG --json nameWithOwner --limit 100` |
| Workflow runs | `gh api "/repos/$O/$R/actions/runs?per_page=100" --jq '.workflow_runs \| length'` |
| Skipped count | `gh api "..." --jq '[.workflow_runs[] \| select(.conclusion == "skipped")] \| length'` |
| Bot triggers | `gh api "..." --jq '[.workflow_runs[] \| select(.triggering_actor.type == "Bot")] \| length'` |

## See Also

- **github-actions-cache-optimization** - Cache-specific analysis and cleanup
- **gh-workflow-monitoring** - Watching individual workflow runs
