# GitHub Actions Inspection - Reference

Detailed reference material for debugging scenarios, failure patterns, advanced jq parsing, and troubleshooting.

## Real-World Debugging Scenarios

### Debug CI Failure

```bash
# Step 1: Find the failing run
gh run list --workflow=ci.yml --status=failure --limit 1

# Step 2: View details
gh run view <run-id>

# Step 3: Get failed job logs
gh run view <run-id> --log-failed

# Step 4: Extract specific errors
gh run view <run-id> --log-failed | grep -E "FAIL|Error|Exception" -A 5

# Step 5: Check if rerun fixes it (flaky test)
gh run rerun <run-id>
```

### Compare Working vs Failing Runs

```bash
# Get last successful run
SUCCESS=$(gh run list --workflow=ci.yml --status=success --limit 1 --json databaseId -q '.[0].databaseId')

# Get last failed run
FAILURE=$(gh run list --workflow=ci.yml --status=failure --limit 1 --json databaseId -q '.[0].databaseId')

# Compare commits
gh run view $SUCCESS --json headSha -q '.headSha'
gh run view $FAILURE --json headSha -q '.headSha'

# Compare job results
echo "Success:"
gh api repos/:owner/:repo/actions/runs/$SUCCESS/jobs | jq '.jobs[].conclusion'
echo "Failure:"
gh api repos/:owner/:repo/actions/runs/$FAILURE/jobs | jq '.jobs[].conclusion'
```

### Investigate Intermittent Failures

```bash
# Get last 20 runs of a workflow
gh run list --workflow=test.yml --limit 20 --json conclusion,createdAt,headSha

# Calculate failure rate
gh run list --workflow=test.yml --limit 50 --json conclusion \
  | jq '[.[] | .conclusion] | group_by(.) | map({conclusion: .[0], count: length}) | map({conclusion, count, percent: ((.count / 50) * 100)})'

# Find which commits have failures
gh run list --workflow=test.yml --status=failure --limit 10 --json headSha,createdAt
```

### Trace Workflow Progression

```bash
# Watch from start
gh run watch $(gh run list --workflow=ci.yml --limit 1 --json databaseId -q '.[0].databaseId')

# Check job status during run
while true; do
  gh api repos/:owner/:repo/actions/runs/<run-id>/jobs \
    | jq '.jobs[] | {name, status, conclusion}'
  sleep 10
done

# Get step-by-step progress
gh api repos/:owner/:repo/actions/runs/<run-id>/jobs \
  | jq '.jobs[0].steps[] | {name, status, conclusion, number}'
```

### Analyze Test Failures

```bash
# Extract test results
gh run view <run-id> --log | grep "FAIL\|PASS" | sort | uniq -c

# Find specific test failures
gh run view <run-id> --log | grep -A 10 "FAIL: test_"

# Get JUnit/TAP output
gh run download <run-id> --name test-results

# Parse test output
gh run view <run-id> --log | grep -E "✓|✗|PASS|FAIL" | wc -l
```

### Check Dependency Issues

```bash
# Find dependency installation errors
gh run view <run-id> --log | grep -i "npm install\|pip install\|bundle install" -A 20

# Check for version conflicts
gh run view <run-id> --log | grep -i "conflict\|incompatible\|version"

# Compare dependency tree
gh run view <success-run-id> --log | grep "installed" > success-deps.txt
gh run view <failure-run-id> --log | grep "installed" > failure-deps.txt
diff success-deps.txt failure-deps.txt
```

## Common Failure Patterns

### Authentication Failures
```bash
# Check for auth errors
gh run view <run-id> --log | grep -i "authentication\|permission\|unauthorized\|403\|401"

# Symptoms: "Resource not accessible by integration", "403 Forbidden"
# Fix: Check workflow permissions, GITHUB_TOKEN scope, secrets configuration
```

### Timeout Issues
```bash
# Find timeout errors
gh run view <run-id> --log | grep -i "timeout\|timed out"

# Check job duration
gh run view <run-id> --json jobs | jq '.jobs[] | {name, duration: (.completed_at - .started_at)}'

# Symptoms: "The job running on runner X has exceeded the maximum execution time"
# Fix: Optimize tests, increase timeout-minutes, split into parallel jobs
```

### Flaky Tests
```bash
# Identify flaky tests by running multiple times
for i in {1..5}; do
  gh workflow run test.yml
  sleep 60
done

# Check failure consistency
gh run list --workflow=test.yml --limit 10 --json conclusion

# Symptoms: Same test passes/fails inconsistently
# Fix: Add delays, fix race conditions, mock external dependencies
```

### Dependency Installation Failures
```bash
# Find install errors
gh run view <run-id> --log | grep -B 5 -A 10 "error installing\|failed to install"

# Symptoms: "Could not find package", "Version conflict", "Network error"
# Fix: Lock versions, use cache, check package registry status
```

### Environment Issues
```bash
# Check environment differences
gh run view <run-id> --log | grep "runner\|environment\|os\|platform"

# Symptoms: "Command not found", "Module not found", "Path does not exist"
# Fix: Verify setup steps, check runner version, install missing tools
```

### Resource Constraints
```bash
# Check for memory/disk issues
gh run view <run-id> --log | grep -i "out of memory\|disk space\|killed"

# Symptoms: "The runner has run out of disk space", "Process killed"
# Fix: Clean up artifacts, reduce test data, increase runner size
```

## Integration with jq (Advanced Parsing)

```bash
# Get all failed jobs with step details
gh api repos/:owner/:repo/actions/runs/<run-id>/jobs \
  | jq '.jobs[] | select(.conclusion == "failure") | {
      job: .name,
      failed_steps: [.steps[] | select(.conclusion == "failure") | .name]
    }'

# Create failure summary report
gh run list --workflow=ci.yml --limit 20 --json conclusion,createdAt,headBranch \
  | jq 'group_by(.headBranch) | map({
      branch: .[0].headBranch,
      total: length,
      failures: [.[] | select(.conclusion == "failure")] | length,
      success_rate: (([.[] | select(.conclusion == "success")] | length) / length * 100)
    })'

# Extract error messages from API
gh api repos/:owner/:repo/actions/runs/<run-id>/jobs \
  | jq '.jobs[].steps[] | select(.conclusion == "failure") | {
      name,
      number,
      conclusion,
      completed_at
    }'
```

## Best Practices

**Efficient Debugging**
- Start with `gh run list` to identify problematic runs
- Use `--log-failed` to focus on failures
- Compare with recent successful runs
- Check for patterns across multiple failures

**Performance**
- Use `--limit` to reduce API calls
- Cache run IDs for repeated queries
- Use JSON output with jq for complex parsing
- Download logs once, analyze locally

**Systematic Investigation**
1. Identify the failure (list recent runs)
2. View run details (overall status)
3. Examine failed jobs (specific job failures)
4. Analyze logs (error messages, stack traces)
5. Compare with working runs (what changed)
6. Verify fix (rerun workflow)

**Automation**
- Script common inspection patterns
- Create aliases for frequent queries
- Use shell functions for repeated tasks
- Integrate with notification systems

## Troubleshooting

### gh CLI Not Working
```bash
# Check authentication
gh auth status

# Re-authenticate
gh auth login

# Check permissions
gh auth refresh -h github.com -s repo,workflow
```

### Rate Limiting
```bash
# Check rate limit
gh api rate_limit

# Use personal access token
export GITHUB_TOKEN=<your-token>

# Reduce API calls with caching
gh run list --limit 100 --json databaseId,conclusion > cache.json
```

### Large Log Files
```bash
# Download logs instead of viewing
gh run download <run-id>

# Filter logs immediately
gh run view <run-id> --log | grep "Error" > errors.txt

# View specific sections
gh run view <run-id> --log | less +/Error
```

### Missing Runs
```bash
# Check workflow file exists
gh workflow list

# Verify workflow is enabled
gh workflow view ci.yml

# Check for pending runs
gh run list --status=queued
gh run list --status=waiting
```
