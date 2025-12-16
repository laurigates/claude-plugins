---
allowed-tools: Task, TodoWrite
argument-hint: "[path] [--watch] [--affected]"
description: Fast unit tests only (skip slow/integration/E2E)
---

## Context

- Project type: !`ls -la pyproject.toml package.json Cargo.toml go.mod 2>/dev/null | head -1`
- Test directories: !`ls -d tests/unit/ test/unit/ __tests__/unit/ 2>/dev/null || echo "no unit dir"`
- Last test run: !`ls -la .pytest_cache/v/cache/lastfailed 2>/dev/null || echo "no cache"`

## Parameters

- `$1`: Optional path or test pattern
- `--watch`: Enable watch mode for continuous feedback
- `--affected`: Only run tests for files changed since last commit

## Your task

**Delegate this task to the `test-runner` agent.**

Use the Task tool with `subagent_type: test-runner` to run fast unit tests only. Pass all the context gathered above and specify **Tier 1 (unit tests)** execution.

The test-runner agent should:

1. **Run unit tests only** (target < 30s):
   - Exclude slow, integration, and E2E tests
   - Use appropriate markers/flags for the framework:
     - pytest: `-m "not slow and not integration and not e2e"`
     - vitest: `--exclude="**/e2e/**" --exclude="**/integration/**"`
     - cargo: `--lib`
     - go: `-short`

2. **Apply options**:
   - If `--watch`: Enable continuous test execution
   - If `--affected`: Only test changed files

3. **Fail fast**: Stop on first failure (`-x` or `--bail`)

4. **Provide concise output**:
   ```
   Unit Tests: [PASS|FAIL]
   Passed: X | Failed: Y | Duration: Zs

   Failures (if any):
   - test_name: Brief error (file:line)

   Rerun failed: [command]
   ```

5. **Post-action guidance**:
   - If all pass: Ready for continued development
   - If failures: Fix before proceeding (fail fast principle)
   - If > 30s: Suggest `/test:consult` for optimization

Provide the agent with:
- All context from the section above
- The parsed parameters
- **Explicit instruction**: Tier 1 only, skip slow tests

The agent has expertise in:
- Tiered test execution
- Fast feedback loops
- Test isolation and parallelization
