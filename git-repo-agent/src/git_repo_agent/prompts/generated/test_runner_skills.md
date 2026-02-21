## test-run

## Your task

**Delegate this task to the `test-runner` agent.**

Use the Task tool with `subagent_type: test-runner` to run tests with the appropriate framework. Pass all the context gathered above and the parsed parameters to the agent.

The test-runner agent should:

1. **Detect project type and test framework**:
   - Python: pytest, unittest, nose
   - Node.js: vitest, jest, mocha
   - Rust: cargo test
   - Go: go test

2. **Run appropriate test command**:
   - Apply test pattern if provided
   - Enable coverage if requested
   - Enable watch mode if requested

3. **Analyze results**:
   - Parse test output for pass/fail counts
   - Identify failing tests with clear error messages
   - Extract coverage metrics if available

4. **Provide concise summary**:
   ```
   Tests: [PASS|FAIL]
   Passed: X | Failed: Y | Duration: Zs

   Failures (if any):
   - test_name: Brief error (file:line)

   Coverage: XX% (if requested)
   ```

5. **Suggest next actions**:
   - If failures: specific fix recommendations
   - If coverage gaps: areas needing tests
   - If slow: optimization suggestions

Provide the agent with:
- All context from the section above
- The parsed parameters (pattern, --coverage, --watch)
- Any specific test configuration detected

The agent has expertise in:
- Multi-framework test execution
- Test failure analysis and debugging
- Coverage reporting and gap identification
- Tiered test execution (unit, integration, e2e)

---

## test-report

## Cached Result Locations

| Framework | Cache Location |
|-----------|----------------|
| pytest | `.pytest_cache/`, `htmlcov/` |
| Vitest | `node_modules/.vitest/` |
| Jest | `coverage/`, `.jest-cache/` |
| Playwright | `test-results/`, `playwright-report/` |
| Go | `coverage.out` |
| Cargo | `target/debug/` |


## Behavior

1. **Find Latest Results**:
   - Check cache directories
   - Parse last run timestamp
   - Extract pass/fail counts

2. **Coverage Summary** (if --coverage):
   - Read coverage reports
   - Show percentage vs target
   - List uncovered files

3. **Flaky Detection** (if --flaky):
   - Compare recent runs
   - Identify tests with inconsistent results
   - Flag suspected flaky tests

4. **History** (if --history):
   - Show last 5 runs
   - Track pass rate trend
   - Identify regression patterns


## Output Format

```

## Test Status (last run: 5 minutes ago)

| Tier        | Passed | Failed | Skipped |
|-------------|--------|--------|---------|
| Unit        | 45     | 2      | 0       |
| Integration | 12     | 0      | 1       |
| E2E         | 8      | 1      | 0       |

**Coverage**: 78% (target: 80%)


### Recent Failures
- test_user_validation: AssertionError (tests/test_user.py:42)
- e2e/login.spec.ts: Timeout (line 15)


### Flaky Tests (if --flaky)
- test_async_handler: 3 failures in last 10 runs


### Suggested Actions
- Run `/test:quick` to verify current state
- Use `/test:consult coverage` for gap analysis
```


## Post-Actions

- If failures exist: Suggest `/test:quick` to verify current state
- If coverage low: Suggest `/test:consult coverage`
- If flaky detected: Suggest `/test:consult flaky`
- If stale (> 1 hour): Suggest running `/test:quick` or `/test:full`

---

## test-tier-selection

# Test Tier Selection

Automatic guidance for selecting appropriate test tiers based on change context and scope.


## Test Tier Definitions

| Tier | Duration | Scope | When to Run |
|------|----------|-------|-------------|
| **Unit** | < 30s | Single function/module | After every code change |
| **Integration** | < 5min | Component interactions | After feature completion |
| **E2E** | < 30min | Full user flows | Before commit/PR |


## Decision Matrix


### Change Type → Test Tier

| Change Type | Unit | Integration | E2E |
|-------------|------|-------------|-----|
| Single function fix | Required | Skip | Skip |
| New feature (1 file) | Required | Required | Skip |
| Multi-file feature | Required | Required | Required |
| Refactoring | Required | Required | Optional |
| API changes | Required | Required | Required |
| UI changes | Required | Optional | Required |
| Bug fix (isolated) | Required | Optional | Skip |
| Database changes | Required | Required | Required |
| Config changes | Required | Required | Optional |


## Escalation Signals

**Escalate to Integration when:**
- Changes span multiple files
- Business logic affected
- Service boundaries modified
- Database queries changed

**Escalate to E2E when:**
- User-facing features modified
- Authentication/authorization changes
- Critical path functionality
- Before creating PR


## Commands by Tier

```bash

# Tier 1: Unit (fast feedback)
/test:quick


# Tier 2: Integration (feature completion)
/test:full --coverage


# Tier 3: E2E (pre-commit)
/test:full
```


## Agent Consultation Triggers

**Consult `test-architecture` agent when:**
- New feature module created
- Coverage drops > 5%
- > 3 flaky tests detected
- Framework questions arise
- Test strategy needs adjustment

**Consult `test-runner` agent when:**
- Need test execution with analysis
- Multiple failures to diagnose
- Want concise failure summary

**Consult `system-debugging` agent when:**
- Integration test failures with unclear cause
- Environment/timing issues
- Flaky tests related to concurrency


### After Small Change
```
1. Run /test:quick
2. If pass: Continue working
3. If fail: Fix immediately
```


### After Feature Completion
```
1. Run /test:full --coverage
2. Check coverage targets met
3. If gaps: /test:consult coverage
```


### Before Commit/PR
```
1. Run /test:full
2. All tiers must pass
3. Review coverage report
```


### For New Features
```
1. /test:consult new-feature
2. Write tests (TDD)
3. Run /test:quick during development
4. Run /test:full before PR
```


## Activation Triggers

This skill auto-activates when:
- User mentions "test", "run tests", "testing"
- After code modification by Claude
- During TDD workflow
- When `/test:*` commands invoked
- When discussing test strategy
