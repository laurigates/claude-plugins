---
model: opus
created: 2025-12-16
modified: 2025-12-16
reviewed: 2025-12-16
name: github-actions-inspection
description: Inspect GitHub Actions workflow runs, check status, analyze logs, debug failures, and identify root causes. Use when investigating CI/CD failures, checking workflow status, or debugging GitHub Actions issues.
allowed-tools: Bash, Read, Grep, Glob, mcp__github
---

# GitHub Actions Inspection

Expert knowledge for inspecting, debugging, and troubleshooting GitHub Actions workflow runs using gh CLI and GitHub API.

For detailed examples, advanced patterns, and best practices, see [REFERENCE.md](REFERENCE.md).

## Core Expertise

**Workflow Run Inspection**
- Check workflow run status and conclusions
- List recent workflow runs with filtering
- View detailed run information
- Monitor in-progress workflows

**Log Analysis**
- Fetch workflow run logs
- Identify failing steps and jobs
- Extract error messages and stack traces
- Parse test failure output

**Debugging Workflows**
- Diagnose common failure patterns
- Correlate errors with code changes
- Identify flaky tests and race conditions
- Analyze timing and performance issues

## Essential Commands

### List Workflow Runs

```bash
# List all workflow runs
gh run list

# List runs for specific workflow
gh run list --workflow=ci.yml

# Filter by status
gh run list --status=failure
gh run list --status=in_progress

# Filter by branch
gh run list --branch=main

# Combine filters
gh run list --workflow=ci.yml --status=failure --limit 5

# JSON output for parsing
gh run list --json databaseId,status,conclusion,name,createdAt,headBranch
```

### View Workflow Run Details

```bash
# View specific run
gh run view <run-id>

# View failed logs only
gh run view <run-id> --log-failed

# View specific job
gh run view <run-id> --job=<job-id>

# JSON output
gh run view <run-id> --json status,conclusion,jobs,startedAt,updatedAt
```

### Download and Analyze Logs

```bash
# Download logs for run
gh run download <run-id>

# View failed step logs only
gh run view <run-id> --log-failed

# Extract specific job logs
gh api repos/:owner/:repo/actions/runs/<run-id>/logs | less
```

### Watch Running Workflows

```bash
# Watch workflow progress
gh run watch <run-id>

# Watch with exit status
gh run watch <run-id> --exit-status
```

### Rerun Workflows

```bash
# Rerun entire workflow
gh run rerun <run-id>

# Rerun only failed jobs
gh run rerun <run-id> --failed

# Rerun with debug logging
gh run rerun <run-id> --debug
```

### Cancel Workflows

```bash
# Cancel specific run
gh run cancel <run-id>
```

## Analysis Patterns

### Find Recent Failures

```bash
# Get last 10 failed runs
gh run list --status=failure --limit 10

# Get failures with details
gh run list --workflow=ci.yml --status=failure --limit 5 \
  --json databaseId,conclusion,name,createdAt,headBranch,headSha
```

### Identify Flaky Tests

```bash
# Get runs for specific commit
gh run list --commit=<sha>

# Find tests that sometimes pass
gh run list --workflow=test.yml --limit 20 --json conclusion \
  | jq 'group_by(.conclusion) | map({conclusion: .[0].conclusion, count: length})'
```

### Extract Error Messages

```bash
# View failed logs
gh run view <run-id> --log-failed

# Extract error lines
gh run view <run-id> --log-failed | grep -i "error\|failed\|exception"

# Parse JSON for errors
gh api repos/:owner/:repo/actions/runs/<run-id>/jobs \
  | jq '.jobs[] | select(.conclusion == "failure") | {name, steps: [.steps[] | select(.conclusion == "failure")]}'
```

### Check Workflow Timing

```bash
# Get run duration
gh run view <run-id> --json startedAt,completedAt,durationMs

# Compare run times
gh run list --workflow=ci.yml --limit 10 \
  --json databaseId,createdAt,updatedAt,durationMs \
  | jq '.[] | {id: .databaseId, duration_min: (.durationMs / 60000)}'
```

### Monitor Workflow Status

```bash
# Check current status
gh run list --status=in_progress

# Summary of run statuses
gh run list --limit 50 --json conclusion \
  | jq 'group_by(.conclusion) | map({conclusion: .[0].conclusion, count: length})'
```

## Common Failure Pattern Summary

| Pattern | Symptoms | Quick Fix |
|---------|----------|-----------|
| Authentication | "403 Forbidden", "Resource not accessible" | Check GITHUB_TOKEN scope, workflow permissions |
| Timeout | "exceeded maximum execution time" | Increase timeout-minutes, split parallel jobs |
| Flaky tests | Same test passes/fails inconsistently | Fix race conditions, mock external deps |
| Dependency install | "Could not find package", "Version conflict" | Lock versions, use cache |
| Environment | "Command not found", "Module not found" | Verify setup steps, check runner version |
| Resource constraints | "out of disk space", "Process killed" | Clean artifacts, increase runner size |

## Agentic Optimizations

| Context | Command |
|---------|---------|
| Quick failure check | `gh run list --status=failure --limit 5 --json databaseId,conclusion,name` |
| Failed logs only | `gh run view <id> --log-failed` |
| JSON run details | `gh run view <id> --json status,conclusion,jobs` |
| Failure rate | `gh run list --limit 50 --json conclusion \| jq 'group_by(.conclusion)'` |
| Rerun failed only | `gh run rerun <id> --failed` |

## Quick Reference

### gh run Commands
- `gh run list` - List workflow runs
- `gh run view <id>` - View run details
- `gh run watch <id>` - Watch run progress
- `gh run download <id>` - Download logs/artifacts
- `gh run rerun <id>` - Rerun workflow
- `gh run cancel <id>` - Cancel running workflow

### Useful Filters
- `--workflow=<name>` - Specific workflow
- `--status=<status>` - Filter by status (in_progress, completed, queued, waiting)
- `--conclusion=<conclusion>` - Filter by conclusion (success, failure, cancelled, skipped)
- `--branch=<branch>` - Specific branch
- `--event=<event>` - Specific trigger event
- `--limit=<n>` - Limit results
- `--json <fields>` - JSON output

### Status Values
- `queued` - Waiting to start
- `in_progress` - Currently running
- `completed` - Finished (check conclusion)
- `waiting` - Waiting for approval

### Conclusion Values
- `success` - All jobs succeeded
- `failure` - At least one job failed
- `cancelled` - Manually cancelled
- `skipped` - Skipped (conditional)
- `timed_out` - Exceeded time limit

## Integration with Other Skills

This skill complements:
- **claude-code-github-workflows** - Creating workflows
- **github-actions-mcp-config** - MCP configuration
- **github-actions-auth-security** - Authentication setup

## Resources

- **gh CLI Manual**: https://cli.github.com/manual/gh_run
- **GitHub Actions API**: https://docs.github.com/en/rest/actions
- **Troubleshooting Guide**: https://docs.github.com/en/actions/monitoring-and-troubleshooting-workflows
