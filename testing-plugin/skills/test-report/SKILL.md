---
created: 2025-12-16
modified: 2026-10-12
reviewed: 2026-04-25
allowed-tools: Read, Glob, Bash(git *)
args: "[--history] [--coverage] [--flaky]"
argument-hint: "[--history] [--coverage] [--flaky]"
description: "Cached results from the last test run, no re-run — pass/fail counts, existing coverage report, history, flaky tests. Use when asked for current test status or standup health."
name: test-report
---

## When to Use This Skill

| Use this skill when... | Use test-run instead when... |
|---|---|
| Reading cached results without re-running tests | Actually executing the test suite |
| Showing standup-ready test status from the last run | Triaging structured test output (use test-analyze) |
| Spotting flaky tests via `--flaky` from recent runs | Picking which tier to run next (use test-tier-selection) |
| Pulling a coverage summary from existing reports | Asking strategic questions (use test-consult) |

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
   - If no cache location exists, report `no data` (see [Output Format](#output-format)) and stop

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

Fill every `<...>` slot from a file you actually read in Behavior step 1. A
slot with no backing file is reported as `no data`; never estimate or carry over
a number.

**When no cached results exist** (none of the locations in
[Cached Result Locations](#cached-result-locations) is present), print only:

```
## Test Status: no data

No cached test results found (checked: <locations checked>).
Run `/test:quick` to produce results.
```

Otherwise:

```
## Test Status (last run: <timestamp from the result file>)

| Tier        | Passed   | Failed   | Skipped   |
|-------------|----------|----------|-----------|
| <tier>      | <passed> | <failed> | <skipped> |

**Coverage**: <percent from the coverage report, or "no data"> (target: <target, if configured>)

### Recent Failures
- <test id>: <error type> (<file>:<line>)

### Flaky Tests (if --flaky)
- <test id>: <failures> failures in last <runs> runs

### Suggested Actions
- Run `/test:quick` to verify current state
- Use `/test:consult coverage` for gap analysis
```

## Post-Actions

- If failures exist: Suggest `/test:quick` to verify current state
- If coverage low: Suggest `/test:consult coverage`
- If flaky detected: Suggest `/test:consult flaky`
- If stale (> 1 hour): Suggest running `/test:quick` or `/test:full`
