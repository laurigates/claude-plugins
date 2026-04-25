---
description: Analyze workflow runs - frequency, duration, success rates, and efficiency. Use when investigating slow CI, high failure rates, or understanding workflow run patterns over time.
args: "[repo] [--created RANGE]"
allowed-tools: Bash(gh api *), Bash(gh workflow *), Bash(gh repo *), Bash(bash *), Read, TodoWrite
argument-hint: Optional repo (owner/name format, defaults to current repo). Use --created for date range. Use org mode for org-wide analysis.
created: 2025-01-30
modified: 2026-04-25
reviewed: 2026-04-25
name: finops-workflows
---

# /finops:workflows

Analyze GitHub Actions workflow runs for a repository - frequency, duration, success rates, and efficiency metrics.

## When to Use This Skill

| Use this skill when... | Use a sibling instead when... |
|---|---|
| You need to analyze workflow run frequency, duration, and trigger distribution | You only need a quick high-level health snapshot — use `/finops:overview` |
| You are investigating high failure rates on specific workflows | You want actionable fixes for workflow config waste — use `/finops:waste` |
| You need org-wide workflow timing analysis (`/finops:workflows org <name>`) | You want to compare workflow metrics across many repos — use `/finops:compare` |
| You want to identify slow or noisy workflows by duration | You are investigating cache size or stale caches — use `/finops:caches` |

## Context

- Current repo URL: !`git remote get-url origin`

## Parameters

| Parameter | Description | Default |
|-----------|-------------|---------|
| `repo` | Repository in owner/name format | Current repository |
| `--created` | Date range filter (e.g., `>=2026-03-01`) | None (last 100 runs) |
| `org <name>` | Org-wide analysis (use instead of repo) | - |

## Execution

### Per-repo analysis (default)

```bash
bash "${SKILL_DIR}/scripts/workflow-runs.sh" $ARGS
```

### Org-wide analysis

When the user requests org-wide analysis, use the org script:

```bash
bash "${SKILL_DIR}/scripts/workflow-runs-org.sh" $ARGS
```

## Output Format

```
Analyzing workflows for: org/repo

=== Active Workflows ===
  CI (id: 12345)
  Deploy (id: 12346)
  CodeQL (id: 12347)

=== Run Summary ===
CI:
  Total: 156 | Success: 140 | Failure: 10 | Cancelled: 4 | Skipped: 2
  Success rate: 89%
Deploy:
  Total: 45 | Success: 44 | Failure: 1 | Cancelled: 0 | Skipped: 0
  Success rate: 97%

=== Duration Analysis ===
CI:
  Runs: 50 | Avg: 4m32s | Max: 12m15s | Total: 226min
Deploy:
  Runs: 20 | Avg: 2m10s | Max: 3m45s | Total: 43min

=== Trigger Types ===
  push: 89 runs
  pull_request: 67 runs
  schedule: 30 runs
  workflow_dispatch: 5 runs

=== Recent Failures (last 10) ===
  #234 CI - 2025-01-28 - https://github.com/org/repo/actions/runs/...
  #231 CI - 2025-01-27 - https://github.com/org/repo/actions/runs/...

=== High Frequency Workflows ===
  CI: 156 runs (~5.2/day) - consider path filters
```

## Agentic Optimizations

| Context | Command |
|---------|---------|
| Workflow list (JSON) | `gh workflow list --json name,id,state` |
| Recent runs (compact) | `gh run list --workflow <name> --limit 20 --json status,conclusion,createdAt` |
| Failed runs only | `gh run list --status failure --limit 10 --json name,createdAt,url` |
| Run timing (JSON) | `gh api "/repos/{owner}/{repo}/actions/runs?per_page=50" --jq '.workflow_runs[] | {name,created_at,updated_at,conclusion}'` |
| Compact per-repo analysis | `bash "${SKILL_DIR}/scripts/workflow-runs.sh" $ARGS` |
| Org-wide analysis | `bash "${SKILL_DIR}/scripts/workflow-runs-org.sh" $ARGS` |

## Post-actions

Based on findings, suggest:
- High failure rate -> Investigate recent failures, check logs with `gh run view --log-failed`
- High frequency -> Review trigger conditions, add path filters
- Long durations -> Review caching, parallelization, step optimization
- Many skipped -> Run `/finops:waste` for detailed analysis
