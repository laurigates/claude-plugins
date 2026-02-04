---
model: haiku
created: 2025-12-16
modified: 2025-12-16
reviewed: 2025-12-16
allowed-tools: Task, TodoWrite
argument-hint: [test-pattern] [--coverage] [--watch]
description: Universal test runner that automatically detects and runs the appropriate testing framework
---

## Context

- Project indicators: !`ls -la pyproject.toml package.json Cargo.toml go.mod 2>/dev/null`
- Test directories: !`find . -maxdepth 1 -type d \( -name 'tests' -o -name 'test' -o -name '__tests__' -o -name 'spec' \) 2>/dev/null`
- Package.json test script: !`grep -A2 '"test"' package.json 2>/dev/null`
- Pytest config: !`grep -A5 '\[tool.pytest' pyproject.toml 2>/dev/null`

## Parameters

- `$1`: Optional test pattern or specific test file/directory
- `--coverage`: Enable coverage reporting
- `--watch`: Run tests in watch mode

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
