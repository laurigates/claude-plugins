# Testing Plugin

Test execution, TDD workflow, testing strategies, and quality analysis for Claude Code.

## Overview

This plugin provides comprehensive testing support including test runners, TDD workflows, testing strategies, and quality analysis. It supports tiered test execution (unit, integration, e2e) and multiple testing frameworks.

## Commands

| Command | Description |
|---------|-------------|
| `/test:run` | Universal test runner - auto-detects and runs appropriate testing framework |
| `/test:quick` | Fast unit tests only (skip slow/integration/E2E) |
| `/test:focus` | Run single test file with fail-fast mode for rapid iteration |
| `/test:full` | Complete test suite including integration and E2E tests |
| `/test:setup` | Configure testing infrastructure with CI/CD integration |
| `/test:consult` | Consult test-architecture agent for testing strategy |
| `/test:report` | Show test status from last run (without re-executing) |
| `/test:analyze` | Analyze test results for patterns and improvements |

## Skills

| Skill | Description |
|-------|-------------|
| `test-tier-selection` | Determine appropriate test tier (unit, integration, e2e) |
| `test-quality-analysis` | Analyze and improve test quality |
| `hypothesis-testing` | Hypothesis-driven development patterns |
| `property-based-testing` | Property-based testing frameworks |
| `mutation-testing` | Mutation testing for quality validation |
| `vitest-testing` | Vitest testing framework patterns |

## Agents

| Agent | Description |
|-------|-------------|
| `test-runner` | Test execution, failure analysis, concise reporting |
| `test-architecture` | Test strategies, coverage analysis, framework selection |

## Tiered Test Execution

| Tier | When to Run | Command | Duration |
|------|-------------|---------|----------|
| Unit | After every change | `/test:quick` | < 30s |
| Integration | After feature completion | `/test:full` | < 5min |
| E2E | Before commit/PR | `/test:full` | < 30min |

## TDD Workflow

The plugin enforces RED → GREEN → REFACTOR:

1. **RED**: Write a failing test that defines desired behavior
2. **GREEN**: Implement minimal code to make the test pass
3. **REFACTOR**: Improve code quality while keeping tests green

## Usage Examples

### Run Quick Tests

```bash
/test:quick
```

Runs only fast unit tests, skipping slow integration and E2E tests.

### Focus on Single File

```bash
/test:focus login.spec.ts
/test:focus tests/e2e/auth.spec.ts --serial
```

Runs a single test file with fail-fast mode. Stops immediately on first failure for rapid iteration. Use `--serial` for tests requiring sequential execution (WebGL, database state).

### Full Test Suite

```bash
/test:full --coverage
```

Runs complete test suite with coverage reporting.

### Consult on Test Strategy

```bash
/test:consult new-feature
```

Gets recommendations from test-architecture agent for testing a new feature.

### Setup Testing Infrastructure

```bash
/test:setup --coverage --ci github
```

Configures testing framework with coverage thresholds and GitHub Actions CI.

## Companion Plugins

Works well with:
- **python-plugin** - For pytest-advanced skill
- **typescript-plugin** - For additional TypeScript testing patterns
- **code-quality-plugin** - For test code review

## Installation

```bash
/plugin install testing-plugin@laurigates-claude-plugins
```

## License

MIT
