# finops-plugin

GitHub Actions FinOps analysis - billing, cache usage, workflow efficiency, and waste identification.

## Overview

This plugin provides tools for analyzing and optimizing GitHub Actions costs and efficiency:

- **Billing analysis**: Org-level minutes usage and costs
- **Cache management**: Size tracking, stale cache detection, cleanup
- **Workflow efficiency**: Run frequency, duration, success rates
- **Waste detection**: Skipped runs, bot triggers, missing optimizations

## Skills

| Skill | Description |
|-------|-------------|
| `github-actions-finops` | Core FinOps analysis - billing, workflows, waste patterns |
| `github-actions-cache-optimization` | Cache-specific analysis and optimization |
| `/finops:overview [org]` | Quick summary - org billing + current repo stats |
| `/finops:workflows [repo]` | Analyze workflow runs - frequency, duration, success rates |
| `/finops:caches [repo\|org:name]` | Cache usage breakdown by prefix, branch, staleness |
| `/finops:waste [repo]` | Identify waste patterns and suggest fixes |
| `/finops:compare <org> [repos...]` | Compare metrics across multiple repositories |

## Quick Start

```bash
# Get a quick overview of current repo and org
/finops:overview

# Analyze workflow efficiency
/finops:workflows

# Check cache usage
/finops:caches

# Find waste and get fix suggestions
/finops:waste

# Compare across repos in your org
/finops:compare myorg
```

## Key Metrics Tracked

| Category | Metrics |
|----------|---------|
| **Billing** | Included minutes, used minutes, paid minutes |
| **Cache** | Total size, cache count, stale caches, size by prefix/branch |
| **Workflows** | Run count, success/failure/skip rates, average duration |
| **Waste** | Skipped runs, bot triggers, missing concurrency, missing path filters |

## Waste Patterns Detected

| Pattern | Impact | Fix |
|---------|--------|-----|
| Missing concurrency | Duplicate runs | Add `concurrency:` group |
| No path filters | Unnecessary runs | Add `paths:` filter |
| Bot triggers | Cascading workflows | Add `if: github.event.sender.type != 'Bot'` |
| No cancel-in-progress | Stale PR runs | Add `cancel-in-progress: true` |

## Requirements

- GitHub CLI (`gh`) authenticated
- Admin access for billing endpoints (optional - degrades gracefully)
- Repository access for workflow/cache analysis

## Environment Variables

- `$GITHUB_ORG` - Default organization name (optional)

## Example Output

```
=== FinOps Overview: myorg ===

Org Billing:
  Minutes: 1234/2000 included, 0 paid

Org Cache:
  45 caches, 2340MB total

Repo: myorg/myrepo
  Cache: 12 caches, 450MB

  Workflows (last 30 days):
    CI: 45 runs (40 ok, 3 fail, 2 skip)
    Deploy: 12 runs (12 ok, 0 fail, 0 skip)

Waste Indicators:
  Skipped runs: 4/87
  Workflows missing concurrency: 2
```

## Related Plugins

- **git-plugin**: GitHub CLI patterns, workflow monitoring
- **github-actions-plugin**: Workflow configuration, debugging

## License

MIT
