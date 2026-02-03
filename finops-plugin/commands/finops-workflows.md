---
model: haiku
description: Analyze workflow runs - frequency, duration, success rates, and efficiency
args: "[repo]"
allowed-tools: Bash(gh api *), Bash(gh workflow *), Bash(gh repo *), Read, TodoWrite
argument-hint: Optional repo (owner/name format, defaults to current repo)
created: 2025-01-30
modified: 2025-01-30
reviewed: 2025-01-30
---

# /finops:workflows

Analyze GitHub Actions workflow runs for a repository - frequency, duration, success rates, and efficiency metrics.

## Context

- Current repo: !`gh repo view --json nameWithOwner --jq '.nameWithOwner' 2>/dev/null`

## Parameters

| Parameter | Description | Default |
|-----------|-------------|---------|
| `repo` | Repository in owner/name format | Current repository |

## Execution

**1. Determine repository:**

```bash
REPO="${1:-$(gh repo view --json nameWithOwner --jq '.nameWithOwner')}"
echo "Analyzing workflows for: $REPO"
```

**2. List active workflows:**

```bash
echo ""
echo "=== Active Workflows ==="
gh workflow list --repo "$REPO" --json id,name,state \
  --jq '.[] | select(.state == "active") | "  \(.name) (id: \(.id))"'
```

**3. Workflow run summary (last 30 days):**

```bash
echo ""
echo "=== Run Summary (last 30 days) ==="
gh api "/repos/$REPO/actions/runs?per_page=100" \
  --jq '.workflow_runs | group_by(.name) |
        map({
          name: .[0].name,
          total: length,
          success: ([.[] | select(.conclusion == "success")] | length),
          failure: ([.[] | select(.conclusion == "failure")] | length),
          cancelled: ([.[] | select(.conclusion == "cancelled")] | length),
          skipped: ([.[] | select(.conclusion == "skipped")] | length)
        }) |
        sort_by(-.total)[] |
        "\(.name):\n  Total: \(.total) | Success: \(.success) | Failure: \(.failure) | Cancelled: \(.cancelled) | Skipped: \(.skipped)\n  Success rate: \(if .total > 0 then ((.success / .total * 100) | floor) else 0 end)%"'
```

**4. Duration analysis (completed runs):**

```bash
echo ""
echo "=== Duration Analysis ==="
gh api "/repos/$REPO/actions/runs?per_page=50&status=completed" \
  --jq '.workflow_runs | group_by(.name) |
        map({
          name: .[0].name,
          count: length,
          durations: [.[] | (.run_started_at as $start | .updated_at as $end |
                      (($end | fromdateiso8601) - ($start | fromdateiso8601)))],
        }) |
        map({
          name: .name,
          count: .count,
          avg_seconds: (if .count > 0 then (.durations | add / length | floor) else 0 end),
          max_seconds: (if .count > 0 then (.durations | max) else 0 end),
          total_seconds: (.durations | add)
        }) |
        sort_by(-.total_seconds)[] |
        "\(.name):\n  Runs: \(.count) | Avg: \(.avg_seconds / 60 | floor)m\(.avg_seconds % 60)s | Max: \(.max_seconds / 60 | floor)m\(.max_seconds % 60)s | Total: \(.total_seconds / 60 | floor)min"'
```

**5. Trigger breakdown:**

```bash
echo ""
echo "=== Trigger Types ==="
gh api "/repos/$REPO/actions/runs?per_page=100" \
  --jq '.workflow_runs | group_by(.event) |
        map({event: .[0].event, count: length}) |
        sort_by(-.count)[] |
        "  \(.event): \(.count) runs"'
```

**6. Recent failures:**

```bash
echo ""
echo "=== Recent Failures (last 10) ==="
gh api "/repos/$REPO/actions/runs?per_page=100&status=completed" \
  --jq '[.workflow_runs[] | select(.conclusion == "failure")] | .[0:10][] |
        "  #\(.run_number) \(.name) - \(.created_at | split("T")[0]) - \(.html_url)"'
```

**7. High-frequency workflows (>2 runs/day average):**

```bash
echo ""
echo "=== High Frequency Workflows ==="
gh api "/repos/$REPO/actions/runs?per_page=100" \
  --jq '.workflow_runs | group_by(.name) |
        map(select(length > 60)) |
        map({name: .[0].name, runs: length, per_day: (length / 30 | . * 10 | floor / 10)}) |
        sort_by(-.runs)[] |
        "  \(.name): \(.runs) runs (~\(.per_day)/day) - consider path filters"'
```

## Output Format

```
Analyzing workflows for: org/repo

=== Active Workflows ===
  CI (id: 12345)
  Deploy (id: 12346)
  CodeQL (id: 12347)

=== Run Summary (last 30 days) ===
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
- High failure rate → Investigate recent failures, check logs with `gh run view --log-failed`
- High frequency → Review trigger conditions, add path filters
- Long durations → Review caching, parallelization, step optimization
- Many skipped → Run `/finops:waste` for detailed analysis
