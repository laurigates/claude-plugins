---
model: haiku
created: 2025-12-16
modified: 2026-02-05
reviewed: 2025-12-16
allowed-tools: Task, TodoWrite
argument-hint: "[--coverage] [--parallel] [--report]"
description: Complete test suite including integration and E2E tests
---

## Context

- Project files: !`find . -maxdepth 1 \( -name 'pyproject.toml' -o -name 'package.json' -o -name 'Cargo.toml' -o -name 'go.mod' \) 2>/dev/null`
- Test directories: !`find . -type d \( -name "test*" -o -name "__tests__" \) 2>/dev/null`
- E2E setup: !`find . -maxdepth 1 \( -name 'playwright.config.*' -o -name 'cypress.config.*' \) 2>/dev/null`
- CI environment: !`echo "CI=$CI GITHUB_ACTIONS=$GITHUB_ACTIONS"`

## Parameters

- `--coverage`: Generate coverage report
- `--parallel`: Force parallel execution
- `--report`: Generate detailed HTML report

## Your task

**Delegate this task to the `test-runner` agent.**

Use the Task tool with `subagent_type: test-runner` to run the complete test suite. Pass all the context gathered above and specify **All Tiers** execution.

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
