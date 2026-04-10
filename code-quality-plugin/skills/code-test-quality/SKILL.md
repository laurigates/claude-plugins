---
name: code-test-quality
description: |
  Analyze test suite quality — detect test smells, empty assertions, flaky patterns,
  coverage gaps, and missing edge cases. Use when test suite is unreliable, coverage
  is misleading, or after major refactors. Pairs with /configure:tests and
  /configure:coverage for framework setup.
args: "[PATH] [--focus <smells|coverage|flaky|all>]"
argument-hint: path to test directory or specific test file
allowed-tools: Bash(npx vitest *), Bash(npx jest *), Bash(pytest *), Bash(cargo test *), Read, Grep, Glob, TodoWrite
created: 2026-04-10
modified: 2026-04-10
reviewed: 2026-04-10
---

# /code:test-quality

Analyze test suite for quality issues and reliability.

## When to Use This Skill

| Use this skill when... | Use something else when... |
|---|---|
| Test suite passes but bugs still ship | Setting up test framework → /configure:tests |
| Coverage numbers are high but quality feels low | Setting up coverage thresholds → /configure:coverage |
| Tests are flaky or timing-dependent | Looking for code anti-patterns → /code:antipatterns |
| After major refactor, need test health check | Running tests → /test:run |

## Context

- Test files: !`find . -type f \( -name "*.test.*" -o -name "*.spec.*" -o -name "test_*.py" -o -name "*_test.py" -o -name "*_test.go" -o -name "*_test.rs" \) -not -path "*/node_modules/*"`
- Test config: !`find . -maxdepth 2 \( -name "vitest.config.*" -o -name "jest.config.*" -o -name "pytest.ini" -o -name "pyproject.toml" -o -name "conftest.py" \) -type f`

## Parameters

- `$1`: Path to analyze (defaults to current directory)
- `--focus`: Analysis focus — `smells` (default), `coverage`, `flaky`, or `all`

## Execution

Execute this test quality analysis:

### Step 1: Discover test suite

Scan the target path for test files. Categorize by:
- Unit tests
- Integration tests
- E2E tests
Count total test files and estimate test-to-source ratio.

### Step 2: Detect test smells

Scan test files for these anti-patterns:

**Empty tests (Critical):**
- Test bodies with no assertions
- Tests that only call the function without checking results
- `expect()` or `assert` never called

**Weak assertions (High):**
- `expect(result).toBeTruthy()` on objects (always passes)
- `assert result` without specific value checks
- `assertEqual(len(result), len(result))` (tautologies)
- Snapshot tests without meaningful structure checks

**Test duplication (Medium):**
- Copy-pasted test bodies with minor variations
- Same setup/teardown repeated across many tests
- Missing parameterized/table-driven patterns

**Missing edge cases (Medium):**
- No tests for error paths
- No tests for empty/null/undefined inputs
- No boundary value tests
- No tests for concurrent access (where applicable)

**Flaky patterns (High):**
- `setTimeout` / `sleep` in tests
- Hardcoded ports or file paths
- Date/time-dependent assertions without mocking
- Tests depending on external services without mocks
- Non-deterministic ordering assumptions

**Overly broad mocks (Medium):**
- Mocking implementation details instead of interfaces
- Mock that returns the expected value (circular logic)
- Tests that pass even when implementation is deleted

### Step 3: Analyze coverage quality (if --focus coverage or all)

If coverage data is available:
1. Identify files with 0% coverage
2. Find files with high line coverage but low branch coverage
3. Detect "coverage padding" — tests that execute code but don't assert behavior
4. Identify critical paths without coverage (error handlers, auth, data validation)

### Step 4: Report findings

Print categorized results:

```
Test Quality Report
===================
Test files: N
Test-to-source ratio: N:1

Smells Found:
  Critical: N (empty tests, no assertions)
  High: N (weak assertions, flaky patterns)
  Medium: N (duplication, missing edge cases)
  Low: N (style issues)

Top Issues:
1. [file:line] Empty test - "should handle X" has no assertions
2. [file:line] Flaky - uses setTimeout(500) instead of async await
3. [file:line] Weak assertion - toBeTruthy on object (always passes)

Recommendations:
- Add assertions to N empty tests
- Replace N setTimeout calls with proper async patterns
- Add error path tests for N untested handlers
```

### Step 5: Suggest improvements

For each finding, provide specific fix guidance:
- Empty test → show what assertion to add
- Flaky pattern → show the async/mock alternative
- Missing edge case → suggest specific test cases

## Post-Actions

- If test framework not configured → suggest `/configure:tests`
- If coverage not set up → suggest `/configure:coverage`
- If many smells found → suggest fixing critical ones first
- If good quality → report health score and suggest maintaining it

## Agentic Optimizations

| Context | Command |
|---|---|
| Find empty tests (JS) | `grep -rn "it\|test" --include="*.test.*" -l` then check for assertions |
| Find sleeps in tests | `grep -rn "setTimeout\|sleep\|time.sleep" --include="*.test.*"` |
| Coverage report (Vitest) | `npx vitest run --coverage --reporter=json` |
| Coverage report (pytest) | `pytest --cov --cov-report=json` |
| Quick smell scan | Grep for assertion-free test bodies |
