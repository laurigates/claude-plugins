---
model: haiku
name: gh-workflow-monitoring
description: Monitor GitHub Actions workflow runs using blocking watch commands instead of polling with timeouts.
allowed-tools: Bash(gh run *), Bash(gh workflow *), Bash(gh pr *), Read
created: 2025-01-16
modified: 2025-01-16
reviewed: 2025-01-16
---

# GitHub Workflow Monitoring

Watch and monitor GitHub Actions workflow runs using `gh run watch` - a blocking command that follows runs until completion without needing timeouts or polling.

## Core Commands

### Watch a Run Until Completion

```bash
# Watch most recent run (interactive selection if multiple)
gh run watch

# Watch specific run ID
gh run watch $RUN_ID

# Compact mode - show only relevant/failed steps (recommended for agents)
gh run watch $RUN_ID --compact

# Exit with non-zero if run fails (useful for chaining)
gh run watch $RUN_ID --exit-status

# Combined: compact output, fail on error
gh run watch $RUN_ID --compact --exit-status
```

**Key Flags**:

| Flag | Description |
|------|-------------|
| `--compact` | Show only relevant/failed steps (less output) |
| `--exit-status` | Exit non-zero if run fails |
| `-i, --interval` | Refresh interval in seconds (default: 3) |

### Find Runs to Monitor

```bash
# List in-progress runs
gh run list --status in_progress --json databaseId,name,status,createdAt

# List runs for specific workflow
gh run list -w "CI" --json databaseId,name,status,conclusion -L 5

# List runs for current branch
gh run list --branch $(git branch --show-current) --json databaseId,name,status

# List runs triggered by specific event
gh run list --event push --json databaseId,name,status -L 10

# List failed runs
gh run list --status failure --json databaseId,name,conclusion,createdAt -L 5
```

**Status Values**: `queued`, `in_progress`, `completed`, `waiting`, `pending`, `requested`

**Conclusion Values** (when completed): `success`, `failure`, `cancelled`, `skipped`, `neutral`, `timed_out`

### View Run Details

```bash
# Get run status with jobs
gh run view $RUN_ID --json status,conclusion,jobs,name,createdAt

# View with step details
gh run view $RUN_ID --verbose

# Get failed logs only (most useful for debugging)
gh run view $RUN_ID --log-failed

# Get full logs
gh run view $RUN_ID --log

# View specific job
gh run view --job $JOB_ID

# Open in browser
gh run view $RUN_ID --web
```

## Workflow Patterns

### Trigger and Watch

```bash
# Trigger workflow and immediately watch it
gh workflow run "CI" && sleep 2 && gh run watch --compact --exit-status

# Trigger with inputs
gh workflow run "Deploy" -f environment=staging -f version=1.2.3
```

### Wait for PR Checks

```bash
# Get the latest run for a PR's head commit
RUN_ID=$(gh run list --branch $(gh pr view $PR --json headRefName --jq '.headRefName') -L 1 --json databaseId --jq '.[0].databaseId')
gh run watch $RUN_ID --compact --exit-status
```

### Monitor Multiple Runs

```bash
# List all in-progress runs and watch the first one
gh run list --status in_progress --json databaseId,name --jq '.[0]'

# Get all active run IDs
gh run list --status in_progress --json databaseId --jq '.[].databaseId'
```

## Agentic Patterns

### Find and Watch Latest Run

```bash
# 1. Find the run
RUN_ID=$(gh run list -L 1 --json databaseId --jq '.[0].databaseId')

# 2. Watch it (blocking - waits until complete)
gh run watch $RUN_ID --compact --exit-status
```

### Diagnose Failures

```bash
# 1. Find failed run
gh run list --status failure -L 1 --json databaseId,name,conclusion

# 2. Get failed logs
gh run view $RUN_ID --log-failed
```

### CI Integration Flow

```bash
# After pushing, find and watch the triggered run
git push origin HEAD
sleep 5  # Wait for GitHub to register the run
RUN_ID=$(gh run list --branch $(git branch --show-current) -L 1 --json databaseId --jq '.[0].databaseId')
gh run watch $RUN_ID --compact --exit-status
```

## Agentic Optimizations

| Context | Command |
|---------|---------|
| Watch until done | `gh run watch $ID --compact --exit-status` |
| Find in-progress | `gh run list --status in_progress --json databaseId,name` |
| Latest run ID | `gh run list -L 1 --json databaseId --jq '.[0].databaseId'` |
| Failed logs | `gh run view $ID --log-failed` |
| Trigger + watch | `gh workflow run "$NAME" && sleep 2 && gh run watch --compact` |
| PR run status | `gh pr checks $PR --json name,state,conclusion` |

## Why `gh run watch` Over Polling

| Approach | Problem |
|----------|---------|
| `sleep` + poll | Wastes time, may miss completion, timeout complexity |
| Webhook | Requires infrastructure, not CLI-friendly |
| `gh run watch` | Blocks until complete, shows progress, returns exit code |

**Benefits of `gh run watch`**:
- **Blocking**: Waits until run completes - no timeout management needed
- **Live updates**: Shows progress during execution
- **Exit codes**: Returns 0 on success, non-zero on failure
- **Compact mode**: `--compact` reduces output to relevant steps only
- **Chain-friendly**: Use with `&&` for conditional next steps

## Error Handling

```bash
# Watch with error handling
gh run watch $RUN_ID --compact --exit-status && echo "Success" || echo "Failed"

# Check if run exists before watching
gh run view $RUN_ID --json status 2>/dev/null && gh run watch $RUN_ID --compact
```

## Context Expressions

Use in command frontmatter:

```markdown
- In-progress runs: !`gh run list --status in_progress --json databaseId,name --jq '.[0] // "none"' 2>/dev/null`
- Latest run: !`gh run list -L 1 --json databaseId,name,status,conclusion 2>/dev/null || echo "[]"`
```

## See Also

- **gh-cli-agentic** - General GitHub CLI patterns
- **git-branch-pr-workflow** - PR and branch workflows
