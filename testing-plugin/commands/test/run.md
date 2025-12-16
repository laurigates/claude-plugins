---
allowed-tools: Task, TodoWrite
argument-hint: [test-pattern] [--coverage] [--watch]
description: Universal test runner that automatically detects and runs the appropriate testing framework
---

## Context

- Project indicators: !`ls -la pyproject.toml package.json Cargo.toml go.mod 2>/dev/null || echo "none found"`
- Test directories: !`ls -d tests/ test/ __tests__/ spec/ 2>/dev/null || echo "none found"`
- Package.json test script: !`cat package.json 2>/dev/null | grep -A2 '"test"' | head -3`
- Pytest config: !`cat pyproject.toml 2>/dev/null | grep -A5 '\[tool.pytest' | head -6`

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
