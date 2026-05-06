---
created: 2025-12-16
modified: 2026-04-25
reviewed: 2026-04-25
allowed-tools: Task, TodoWrite
args: "[test-pattern] [--coverage] [--watch]"
argument-hint: "[test-pattern] [--coverage] [--watch]"
description: |
  Universal test runner that auto-detects and runs the appropriate testing
  framework (pytest, vitest, jest, cargo test, go test). Use when the user
  asks to run the tests, test a specific file or pattern, run tests with
  coverage, start a watch-mode dev loop, or run tests without specifying
  the framework.
name: test-run
---

## When to Use This Skill

| Use this skill when... | Use test-quick instead when... |
|---|---|
| Running tests with auto-detected framework (pytest, vitest, jest, cargo, go) | You only want fast unit tests for sub-30s feedback |
| Running a specific file or pattern with full framework defaults | Iterating on a single failing spec (use test-focus) |
| Generating coverage in the standard run | Running the full pyramid before a PR (use test-full) |
| Starting a watch-mode dev loop across the project | Triaging existing test results (use test-analyze) |

## Context

- Project indicators: !`find . -maxdepth 1 \( -name 'pyproject.toml' -o -name 'package.json' -o -name 'Cargo.toml' -o -name 'go.mod' \)`
- Test directories: !`find . -maxdepth 1 -type d \( -name 'tests' -o -name 'test' -o -name '__tests__' -o -name 'spec' \)`
- Package.json test script: !`grep -A2 '"test"' package.json`
- Pytest config: !`grep -A5 '\[tool.pytest' pyproject.toml`

## Parameters

- `$1`: Optional test pattern or specific test file/directory
- `--coverage`: Enable coverage reporting
- `--watch`: Run tests in watch mode

## Your task

**Delegate this task to the `test-runner` agent.**

Use the Agent tool with `subagent_type: test-runner` to run tests with the appropriate framework. Pass all the context gathered above and the parsed parameters to the agent.

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
