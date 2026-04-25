---
description: Compare FinOps metrics across multiple repositories in an organization. Use when benchmarking repos against each other, identifying worst-performing repos, or doing org-wide CI cost analysis.
args: "<org> [repo1 repo2 ...] [--limit N]"
allowed-tools: Bash(gh api *), Bash(gh repo *), Bash(bash *), Read, TodoWrite
argument-hint: Org name required, optional repo list, --limit for auto-discovery
created: 2025-01-30
modified: 2026-04-25
reviewed: 2026-04-25
name: finops-compare
---

# /finops:compare

Compare GitHub Actions FinOps metrics across multiple repositories - cache usage, workflow frequency, failure rates, and efficiency.

## When to Use This Skill

| Use this skill when... | Use a sibling instead when... |
|---|---|
| You need to benchmark CI metrics across many repos in an org | You only need a snapshot of the current repo — use `/finops:overview` |
| You want to identify the worst-performing repos in an org | You need a deep dive on one repo's caches — use `/finops:caches` |
| You are running an org-wide cache or failure audit | You need per-workflow analysis on one repo — use `/finops:workflows` |
| You want to rank repos by efficiency or cache size | You want actionable workflow waste fixes — use `/finops:waste` |

## Parameters

| Parameter | Description | Default |
|-----------|-------------|---------|
| `org` | GitHub organization name (required) | - |
| `repos...` | Space-separated list of repo names | All org repos |
| `--limit N` | Limit auto-discovery to N repos | 30 |

## Usage Examples

```bash
# Compare specific repos
/finops:compare myorg repo1 repo2 repo3

# Compare all repos in org (up to 30)
/finops:compare myorg

# Compare more repos
/finops:compare myorg --limit 50
```

## Execution

```bash
bash "${SKILL_DIR}/scripts/compare-repos.sh" $ARGS
```

## Output Format

```
=== FinOps Comparison: myorg ===

Discovering repos (limit: 30)...
Found 25 repos

=== Cache Usage ===
Repository                               Caches    Size (MB)
----------                               ------    ---------
frontend-app                                 45         2340
backend-api                                  32         1850
shared-libs                                  18          420
...

=== Workflow Activity (last 30 days) ===
Repository                                 Runs  Success   Failed  Skip Rate
----------                                 ----  -------   ------  ---------
frontend-app                                156      140       10         3%
backend-api                                  89       85        2         2%
...

=== Failure Rates (top 15) ===
Repository                                Total   Failed       Rate
----------                                -----   ------       ----
legacy-service                               45       12        26%
experimental-repo                            20        5        25%
...

=== Active Workflows ===
Repository                               Workflows
----------                               ---------
frontend-app                                     8
backend-api                                      5
...

=== Summary ===
Total cache usage: 8450MB across 25 repos

Repos exceeding 1GB cache:
  frontend-app: 2340MB
  backend-api: 1850MB

Repos with >20% failure rate:
  legacy-service: 26%
  experimental-repo: 25%
```

## Agentic Optimizations

| Context | Command |
|---------|---------|
| List org repos (JSON) | `gh api "/orgs/{org}/repos?per_page=100&sort=pushed" --jq '.[].full_name'` |
| Cache count per repo | `gh api "/repos/{owner}/{repo}/actions/caches" --jq '.total_count'` |
| Workflow runs (JSON) | `gh api "/repos/{owner}/{repo}/actions/runs?per_page=100" --jq '.workflow_runs'` |
| Compact multi-repo compare | `bash "${SKILL_DIR}/scripts/compare-repos.sh" $ARGS` |

## Post-actions

Based on comparison results:
- **High cache repos**: Run `/finops:caches <repo>` for detailed analysis
- **High failure repos**: Run `/finops:workflows <repo>` to investigate
- **High activity repos**: Run `/finops:waste <repo>` to find optimizations
- **Create report**: Consider creating a GitHub issue with findings
