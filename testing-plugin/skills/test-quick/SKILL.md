---
created: 2025-12-16
modified: 2026-04-25
reviewed: 2026-04-25
allowed-tools: Task, TodoWrite
args: "[path] [--watch] [--affected]"
argument-hint: "[path] [--watch] [--affected]"
description: |
  Run fast unit tests only, skipping slow/integration/E2E tiers. Use when
  the user asks to run quick tests, check unit tests after a change, run
  only affected tests since the last commit, enable watch mode for TDD,
  or get sub-30-second feedback while iterating.
name: test-quick
---

## When to Use This Skill

| Use this skill when... | Use test-full instead when... |
|---|---|
| Running unit tests only for sub-30s feedback | Running the full pyramid (unit + integration + E2E) before a PR |
| Restricting to tests affected by recent changes (`--affected`) | Generating coverage or HTML reports across all tiers |
| Running watch-mode TDD on unit tests | Iterating on a single failing file (use test-focus) |
| Confirming nothing broke after a small refactor | Triaging test results from a prior run (use test-analyze) |

## Context

- Project type: !`find . -maxdepth 1 \( -name 'pyproject.toml' -o -name 'package.json' -o -name 'Cargo.toml' -o -name 'go.mod' \)`
- Test directories: !`find . -maxdepth 2 -type d \( -path '*/tests/unit' -o -path '*/test/unit' -o -path '*/__tests__/unit' \)`
- Last test run: !`find .pytest_cache/v/cache -maxdepth 1 -name 'lastfailed'`

## Parameters

- `$1`: Optional path or test pattern
- `--watch`: Enable watch mode for continuous feedback
- `--affected`: Only run tests for files changed since last commit

## Your task

**Delegate this task to the `test-runner` agent.**

Use the Agent tool with `subagent_type: test-runner` to run fast unit tests only. Pass all the context gathered above and specify **Tier 1 (unit tests)** execution.

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
