## kubectl-debugging

# kubectl debug - Interactive Kubernetes Debugging

Expert knowledge for debugging Kubernetes resources using `kubectl debug` - ephemeral containers, pod copies, and node access.


## Core Capabilities

**kubectl debug** automates common debugging tasks:

- **Ephemeral Containers**: Add debug containers to running pods without restart
- **Pod Copying**: Create modified copies for debugging (different images, commands)
- **Node Debugging**: Access node host namespaces and filesystem


## Context Safety (CRITICAL)

**Always specify `--context`** explicitly in every kubectl command:

```bash

# CORRECT: Explicit context
kubectl --context=prod-cluster debug mypod -it --image=busybox


# WRONG: Relying on current context
kubectl debug mypod -it --image=busybox  # Which cluster?
```


### Add Ephemeral Debug Container

```bash

# Interactive debugging with busybox
kubectl --context=my-context debug mypod -it --image=busybox


# Target specific container's process namespace
kubectl --context=my-context debug mypod -it --image=busybox --target=mycontainer


# Use a specific debug profile
kubectl --context=my-context debug mypod -it --image=busybox --profile=netadmin
```


### Copy Pod for Debugging

```bash

# Create debug copy
kubectl --context=my-context debug mypod -it --copy-to=mypod-debug --image=busybox


# Copy and change container image
kubectl --context=my-context debug mypod --copy-to=mypod-debug --set-image=app=busybox


# Copy and modify command
kubectl --context=my-context debug mypod -it --copy-to=mypod-debug --container=myapp -- sh


# Copy on same node
kubectl --context=my-context debug mypod -it --copy-to=mypod-debug --same-node --image=busybox
```


### Debug Node

```bash

# Interactive node debugging (host namespaces, filesystem at /host)
kubectl --context=my-context debug node/mynode -it --image=busybox


# With sysadmin profile for full capabilities
kubectl --context=my-context debug node/mynode -it --image=ubuntu --profile=sysadmin
```


## Debug Profiles

| Profile | Use Case | Capabilities |
|---------|----------|--------------|
| `legacy` | Default, unrestricted | Full access (backwards compatible) |
| `general` | General purpose | Moderate restrictions |
| `baseline` | Minimal restrictions | Pod security baseline |
| `netadmin` | Network troubleshooting | NET_ADMIN capability |
| `restricted` | High security environments | Strictest restrictions |
| `sysadmin` | System administration | SYS_PTRACE, SYS_ADMIN |

```bash

# Network debugging (tcpdump, netstat, ss)
kubectl --context=my-context debug mypod -it --image=nicolaka/netshoot --profile=netadmin


# System debugging (strace, perf)
kubectl --context=my-context debug mypod -it --image=ubuntu --profile=sysadmin
```


## Common Debug Images

| Image | Size | Use Case |
|-------|------|----------|
| `busybox` | ~1MB | Basic shell, common utilities |
| `alpine` | ~5MB | Shell with apk package manager |
| `ubuntu` | ~77MB | Full Linux with apt |
| `nicolaka/netshoot` | ~350MB | Network debugging (tcpdump, dig, curl, netstat) |
| `gcr.io/k8s-debug/debug` | Varies | Official Kubernetes debug image |


## Debugging Patterns


### Network Connectivity Issues

```bash

# Add netshoot container for network debugging
kubectl --context=my-context debug mypod -it \
  --image=nicolaka/netshoot \
  --profile=netadmin


# Inside container:

# - tcpdump -i any port 80

# - dig kubernetes.default

# - curl -v http://service:port

# - ss -tlnp

# - netstat -an
```


### Application Crashes

```bash

# Copy pod with different entrypoint to inspect
kubectl --context=my-context debug mypod -it \
  --copy-to=mypod-debug \
  --container=app \
  -- sh


# Inside: check filesystem, env vars, config files
```


### Process Inspection

```bash

# Target container's process namespace
kubectl --context=my-context debug mypod -it \
  --image=busybox \
  --target=mycontainer


# Inside: ps aux, /proc inspection
```


### Node-Level Issues

```bash

# Debug node with host access
kubectl --context=my-context debug node/worker-1 -it \
  --image=ubuntu \
  --profile=sysadmin


# Inside:

# - Host filesystem at /host

# - chroot /host for full access

# - journalctl, systemctl, dmesg
```


### Non-Destructive Debugging

```bash

# Create copy, keeping original running
kubectl --context=my-context debug mypod -it \
  --copy-to=mypod-debug \
  --same-node \
  --share-processes \
  --image=busybox


# Original pod continues serving traffic

# Debug copy shares storage if on same node
```


## Key Options

| Option | Description |
|--------|-------------|
| `-it` | Interactive TTY (required for shell access) |
| `--image` | Debug container image |
| `--container` | Name for the debug container |
| `--target` | Share process namespace with this container |
| `--copy-to` | Create a copy instead of ephemeral container |
| `--same-node` | Schedule copy on same node (with `--copy-to`) |
| `--set-image` | Change container images in copy |
| `--profile` | Security profile (legacy, netadmin, sysadmin, etc.) |
| `--share-processes` | Enable process namespace sharing (default: true with --copy-to) |
| `--replace` | Delete original pod when creating copy |


## Best Practices

1. **Use appropriate profiles** - Match capabilities to debugging needs
2. **Prefer ephemeral containers** - Less disruptive than pod copies
3. **Use `--copy-to` for invasive debugging** - Preserve original pod
4. **Clean up debug pods** - Delete copies after debugging
5. **Use `--same-node`** - For accessing shared storage/network conditions


## Cleanup

```bash

# List debug pod copies
kubectl --context=my-context get pods | grep -E "debug|copy"


# Delete debug pods
kubectl --context=my-context delete pod mypod-debug
```


## Requirements

- Kubernetes 1.23+ for ephemeral containers (stable)
- Kubernetes 1.25+ for debug profiles
- RBAC permissions for pods/ephemeralcontainers

For detailed option reference, examples, and troubleshooting patterns, see REFERENCE.md.

---

## github-actions-inspection

# GitHub Actions Inspection

Expert knowledge for inspecting, debugging, and troubleshooting GitHub Actions workflow runs using gh CLI and GitHub API.

For detailed examples, advanced patterns, and best practices, see .


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

---

## debugging-methodology

# Debugging Methodology

Systematic approach to finding and fixing bugs.


## Core Principles

1. **Occam's Razor** - Start with the simplest explanation
2. **Binary Search** - Isolate the problem area systematically
3. **Preserve Evidence** - Understand state before making changes
4. **Document Hypotheses** - Track what was tried and didn't work


## Debugging Workflow

```
1. Understand → What is expected vs actual behavior?
2. Reproduce → Can you trigger the bug reliably?
3. Locate → Where in the code does it happen?
4. Diagnose → Why does it happen? (root cause)
5. Fix → Minimal change to resolve
6. Verify → Confirm fix works, no regressions
```


## Common Bug Patterns

| Symptom | Likely Cause | Check First |
|---------|--------------|-------------|
| TypeError/null | Missing null check | Input validation |
| Off-by-one | Loop bounds, array index | Boundary conditions |
| Race condition | Async timing | Await/promise handling |
| Import error | Path/module resolution | File paths, exports |
| Type mismatch | Wrong type passed | Function signatures |
| Flaky test | Timing, shared state | Test isolation |


## System-Level Tools


### Memory Analysis
```bash

# Valgrind (C/C++/Rust)
valgrind --leak-check=full --show-leak-kinds=all ./program
valgrind --tool=massif ./program  # Heap profiling


# Python
python -m memory_profiler script.py
```


### Performance Profiling
```bash

# Linux perf
perf record -g ./program
perf report
perf top  # Real-time CPU usage


# Python
python -m cProfile -s cumtime script.py
```


### System Tracing (Traditional)
```bash

# System calls (ptrace-based, high overhead)
strace -f -e trace=all -p PID


# Library calls
ltrace -f -S ./program


# Open files/sockets
lsof -p PID


# Memory mapping
pmap -x PID
```


### eBPF Tracing (Modern, Production-Safe)

eBPF is the modern replacement for strace/ptrace-based tracing. Key advantages:
- **Low overhead**: Safe for production use
- **No recompilation**: Works on running binaries
- **Non-intrusive**: Doesn't stop program execution
- **Kernel-verified**: Bounded execution, can't crash the system

```bash

# BCC tools (install: apt install bpfcc-tools)

# Trace syscalls with timing (like strace but faster)
sudo syscount -p PID              # Count syscalls
sudo opensnoop -p PID             # Trace file opens
sudo execsnoop                    # Trace new processes
sudo tcpconnect                   # Trace TCP connections
sudo funccount 'vfs_*'            # Count kernel function calls


# bpftrace (install: apt install bpftrace)

# One-liner tracing scripts
sudo bpftrace -e 'tracepoint:syscalls:sys_enter_open { printf("%s %s\n", comm, str(args->filename)); }'
sudo bpftrace -e 'uprobe:/bin/bash:readline { printf("readline\n"); }'


# Trace function arguments in Go/other languages
sudo bpftrace -e 'uprobe:./myapp:main.handleRequest { printf("called\n"); }'
```

**eBPF Tool Hierarchy**:
| Level | Tool | Use Case |
|-------|------|----------|
| High | BCC tools | Pre-built tracing scripts |
| Medium | bpftrace | One-liner custom traces |
| Low | libbpf/gobpf | Custom eBPF programs |

**When to use eBPF over strace**:
- Production systems (strace adds 10-100x overhead)
- Long-running traces
- High-frequency syscalls
- When you can't afford to slow down the process


### Network Debugging
```bash

# Packet capture
tcpdump -i any port 8080


# Connection status
ss -tuln
netstat -tuln
```


## Language-Specific Debugging


### Python
```python

# Quick debug
import pdb; pdb.set_trace()


# Better: ipdb or pudb
import ipdb; ipdb.set_trace()


# Print with context
print(f"{var=}")  # Python 3.8+
```


### JavaScript/TypeScript
```javascript
// Browser/Node
debugger;

// Structured logging
console.log({ var1, var2, context: 'function_name' });
```


### Rust
```rust
// Debug print
dbg!(&variable);

// Backtrace on panic
RUST_BACKTRACE=1 cargo run
```


## Debugging Questions

When stuck, ask:
1. What changed recently that could cause this?
2. Does it happen in all environments or just one?
3. Is the bug in my code or a dependency?
4. What assumptions am I making that might be wrong?
5. Can I write a minimal reproduction?


## Effective Debugging Practices

- **Targeted changes**: Form a hypothesis, change one thing at a time
- **Use proper debuggers**: Step through code with breakpoints when possible
- **Find root causes**: Trace issues to their origin, fix the source
- **Reproduce first**: Create a minimal reproduction before attempting a fix
- **Verify the fix**: Confirm the fix resolves the issue and passes tests
