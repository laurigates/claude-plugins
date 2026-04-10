---
description: Quick FinOps summary - org billing and current repo workflow/cache stats. Use when you want a high-level snapshot of CI spending, cache usage, and workflow health before diving deeper.
args: "[org]"
allowed-tools: Bash(gh api *), Bash(gh repo *), Bash(gh workflow *), Bash(bash *), Read, TodoWrite
argument-hint: Optional org name (defaults to current repo's org)
created: 2025-01-30
modified: 2026-03-05
reviewed: 2026-02-08
name: finops-overview
---

# /finops:overview

Display a quick FinOps summary including org-level billing (if admin) and current repository workflow/cache statistics.

## When to Use

| Scenario | Use this skill | Alternative |
|----------|---------------|-------------|
| First look at CI costs and health | `/finops:overview` | - |
| Quick billing + cache + workflow snapshot | `/finops:overview` | - |
| Decide which finops skill to run next | `/finops:overview` | - |
| Detailed cache analysis needed | `/finops:caches` | Use caches for full cache breakdown |
| Detailed workflow run analysis | `/finops:workflows` | Use workflows for per-workflow stats |
| Find and fix CI waste patterns | `/finops:waste` | Use waste for actionable fixes |
| Multi-repo comparison | `/finops:compare` | Use compare for org-wide benchmarks |

## Context

- Current repo URL: !`git remote get-url origin`

## Parameters

| Parameter | Description | Default |
|-----------|-------------|---------|
| `org` | GitHub organization name | Current repo's owner |

## Execution

```bash
bash "${SKILL_DIR}/scripts/billing-summary.sh" $ARGS
```

## Output Format

```
=== Org Billing: orgname ===
Minutes: 1234/2000 included, 0 paid

=== Org Cache Usage ===
45 caches, 2340MB total

=== Repo: orgname/reponame ===
Cache:
  12 caches, 450MB

Workflows (last 30 days):
  CI: 45 runs (40 ok, 3 fail, 2 skip)
  Deploy: 12 runs (12 ok, 0 fail, 0 skip)
  CodeQL: 30 runs (28 ok, 0 fail, 2 skip)

=== Waste Indicators ===
Skipped runs: 4/87
Workflows missing concurrency: 2
```

## Agentic Optimizations

| Context | Command |
|---------|---------|
| Org billing (JSON) | `gh api "/orgs/{org}/settings/billing/actions" --jq '.'` |
| Repo cache summary | `gh api "/repos/{owner}/{repo}/actions/caches" --jq '{total: .total_count}'` |
| Workflow list | `gh workflow list --json name,state` |
| Recent runs (compact) | `gh run list --limit 20 --json status,conclusion,name` |
| Compact overview | `bash "${SKILL_DIR}/scripts/billing-summary.sh" $ARGS` |

## Post-actions

Suggest next steps based on findings:
- High skipped runs -> `/finops:waste`
- High cache usage -> `/finops:caches`
- Want detailed workflow analysis -> `/finops:workflows`
- Compare across repos -> `/finops:compare`
