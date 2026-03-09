---
model: haiku
description: Analyze workflow runs - frequency, duration, success rates, and efficiency
args: "[repo] [--created RANGE]"
allowed-tools: Bash(gh api *), Bash(gh workflow *), Bash(gh repo *), Bash(bash *), Read, TodoWrite
argument-hint: Optional repo (owner/name format, defaults to current repo). Use --created for date range. Use org mode for org-wide analysis.
created: 2025-01-30
modified: 2026-03-05
reviewed: 2025-01-30
name: finops-workflows
---

# /finops:workflows

Analyze GitHub Actions workflow runs for a repository - frequency, duration, success rates, and efficiency metrics.

## Context

- Current repo: !`git remote -v | head -1`

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

## Post-actions

Based on findings, suggest:
- High failure rate -> Investigate recent failures, check logs with `gh run view --log-failed`
- High frequency -> Review trigger conditions, add path filters
- Long durations -> Review caching, parallelization, step optimization
- Many skipped -> Run `/finops:waste` for detailed analysis
