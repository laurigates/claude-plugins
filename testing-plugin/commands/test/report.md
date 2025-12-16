---
allowed-tools: Read, Glob, Bash(git:*)
argument-hint: "[--history] [--coverage] [--flaky]"
description: Show test status from last run (without re-executing)
---

## Context

Quick status check without re-running tests. Reads cached results from last test execution.

**Use when:**
- Checking current test health
- Quick status update for standup
- Reviewing before deciding next action

## Parameters

- `--history`: Show trend from recent runs
- `--coverage`: Include coverage summary
- `--flaky`: Identify potentially flaky tests

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
