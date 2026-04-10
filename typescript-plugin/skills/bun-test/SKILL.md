---
description: Run tests with Bun test runner
args: [pattern] [--coverage] [--bail] [--watch]
allowed-tools: Bash, BashOutput, Read
argument-hint: [test-pattern] [--coverage] [--bail] [--watch]
created: 2025-12-20
modified: 2025-12-20
reviewed: 2025-12-20
name: bun-test
---

# /bun:test

Run tests using Bun's built-in test runner with optimized output.

## When to Use This Skill

| Scenario | Use this skill | Alternative |
|----------|---------------|-------------|
| Quickly running tests with compact output | Yes | N/A |
| Running a specific test file or pattern | Yes | N/A |
| Running tests with coverage | Yes | N/A |
| Configuring test runner options in detail | No - use `bun-development` | Full test configuration guidance |
| Debugging failing tests interactively | No - use `typescript-debugging` | Inspector-based debugging |

## Parameters

- `pattern` (optional): Test file or name pattern
- `--coverage`: Enable code coverage reporting
- `--bail`: Stop on first failure
- `--watch`: Watch mode for development

## Execution

**Quick feedback (default for agentic use):**
```bash
bun test --dots --bail=1 $PATTERN
```

**With coverage:**
```bash
bun test --dots --coverage $PATTERN
```

**Watch mode:**
```bash
bun test --watch $PATTERN
```

**CI mode (JUnit output):**
```bash
bun test --reporter=junit --reporter-outfile=junit.xml $PATTERN
```

## Output Interpretation

| Symbol | Meaning |
|--------|---------|
| `.` | Test passed |
| `F` | Test failed |
| `S` | Test skipped |

## Post-test

1. Report pass/fail summary
2. If failures: show first failure details
3. If coverage enabled: report coverage percentage
