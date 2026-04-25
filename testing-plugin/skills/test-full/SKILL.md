---
created: 2025-12-16
modified: 2026-04-25
reviewed: 2026-04-25
allowed-tools: Task, TodoWrite
args: "[--coverage] [--parallel] [--report]"
argument-hint: "[--coverage] [--parallel] [--report]"
description: |
  Run the complete test suite in pyramid order - unit, then integration,
  then E2E. Use when the user asks to run all tests before a PR, run the
  full test suite with coverage, execute integration and E2E together,
  generate an HTML test report, or run pre-commit verification across all
  test tiers.
name: test-full
agent: general-purpose
---

## When to Use This Skill

| Use this skill when... | Use test-quick instead when... |
|---|---|
| Running the complete pyramid (unit, integration, E2E) before a PR | You only need fast unit-test feedback |
| Generating coverage and HTML reports across all tiers | Iterating on a single failing file (use test-focus) |
| Forcing parallel pre-commit verification across the suite | Running tests for one specific framework run (use test-run) |
| Producing a CI-like full pass locally | Asking strategic questions about strategy (use test-consult) |

## Context

- Project files: !`find . -maxdepth 1 \( -name 'pyproject.toml' -o -name 'package.json' -o -name 'Cargo.toml' -o -name 'go.mod' \)`
- Test directories: !`find . -type d \( -name "test*" -o -name "__tests__" \)`
- E2E setup: !`find . -maxdepth 1 \( -name 'playwright.config.*' -o -name 'cypress.config.*' \)`
- CI environment: !`echo "CI=$CI GITHUB_ACTIONS=$GITHUB_ACTIONS"`

## Parameters

- `--coverage`: Generate coverage report
- `--parallel`: Force parallel execution
- `--report`: Generate detailed HTML report

## Your task

**Delegate this task to the `test-runner` agent.**

Use the Agent tool with `subagent_type: test-runner` to run the complete test suite. Pass all the context gathered above and specify **All Tiers** execution.

The test-runner agent should:

1. **Run tests in pyramid order** (fail fast):
   - **Tier 1 - Unit tests** first (fastest feedback)
   - **Tier 2 - Integration tests** (component interactions)
   - **Tier 3 - E2E tests** (full user flows)

2. **Apply options**:
   - If `--coverage`: Enable coverage reporting for all tiers
   - If `--parallel`: Run tests in parallel where safe
   - If `--report`: Generate HTML report

3. **Stop on failure** at any tier (don't waste time on later tiers)

4. **Provide pyramid summary**:
   ```
   ## Full Test Suite: [PASSED|FAILED]

   | Tier        | Passed | Failed | Duration |
   |-------------|--------|--------|----------|
   | Unit        | X      | Y      | Zs       |
   | Integration | X      | Y      | Zs       |
   | E2E         | X      | Y      | Zs       |

   Coverage: XX% (target: 80%)

   ### Failures
   [Grouped by tier with file:line references]

   ### Recommended Actions
   - [Specific next steps]
   ```

5. **Post-action guidance**:
   - All pass: Ready to commit/PR
   - Unit failures: Fix immediately, use `/test:quick` for iteration
   - Integration failures: Check service boundaries
   - E2E failures: Check selectors/timing
   - Coverage gaps: Use `/test:consult coverage`

Provide the agent with:
- All context from the section above
- The parsed parameters
- **Explicit instruction**: Run all tiers in order

The agent has expertise in:
- Full test pyramid execution
- Coverage analysis and reporting
- E2E test frameworks (Playwright, Cypress)
- CI/CD integration

## Agent Teams (Optional)

For large test suites, spawn teammates for parallel test execution:

| Teammate | Focus | Value |
|----------|-------|-------|
| Unit test runner | Fast unit tests | Quick feedback loop, fail-fast |
| Integration test runner | Component interactions | Service boundary validation |
| E2E test runner | Full user flows | End-to-end verification |

Each teammate runs its tier independently and reports results via the shared task list. This is optional — the skill runs tiers sequentially without agent teams.
