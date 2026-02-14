---
model: opus
created: 2025-12-16
modified: 2026-02-10
reviewed: 2025-12-16
name: mutation-testing
description: |
  Validate test effectiveness with mutation testing using Stryker (TypeScript/JavaScript)
  and mutmut (Python). Find weak tests that pass despite code mutations.
  Use when user mentions mutation testing, Stryker, mutmut, test effectiveness,
  finding weak tests, or improving test quality through mutation analysis.
allowed-tools: Bash, Read, Edit, Write, Grep, Glob, TodoWrite
---

# Mutation Testing

Expert knowledge for mutation testing - validating that your tests actually catch bugs by introducing deliberate code mutations.

## When to Use This Skill

| Use this skill when... | Use another skill instead when... |
|------------------------|----------------------------------|
| Validating test effectiveness | Writing unit tests (use vitest-testing) |
| Finding weak/insufficient tests | Analyzing test smells (use test-quality-analysis) |
| Setting up Stryker or mutmut | Writing E2E tests (use playwright-testing) |
| Improving mutation score | Generating test data (use property-based-testing) |
| Checking if tests catch real bugs | Setting up code coverage only |

## Core Expertise

**Mutation Testing Concept**
- **Mutants**: Small code changes (mutations) introduced automatically
- **Killed**: Test fails with mutation (good - test caught the bug)
- **Survived**: Test passes with mutation (bad - weak test)
- **Coverage**: Tests execute mutated code but don't catch it
- **Score**: Percentage of mutants killed (aim for 80%+)

**What Mutation Testing Reveals**
- Tests that don't actually verify behavior
- Missing assertions or edge cases
- Overly permissive assertions
- Dead code or unnecessary logic
- Areas needing stronger tests

## TypeScript/JavaScript (Stryker)

### Installation

```bash
# Using Bun
bun add -d @stryker-mutator/core

# For Vitest
bun add -d @stryker-mutator/vitest-runner

# For Jest
bun add -d @stryker-mutator/jest-runner
```

### Running Stryker

```bash
npx stryker run                                    # Run mutation testing
npx stryker run --incremental                      # Only changed files
npx stryker run --mutate "src/utils/**/*.ts"       # Specific files
npx stryker run --reporters html,clear-text        # HTML report
open reports/mutation/html/index.html              # View report
```

### Understanding Results

```
Mutation score: 82.5%
- Killed: 66 (tests caught the mutation)
- Survived: 14 (tests passed despite mutation - weak tests!)
- No Coverage: 0 (mutated code not executed)
- Timeout: 0 (tests took too long)
```

### Example: Weak vs Strong Test

```typescript
// Source code
function calculateDiscount(price: number, percentage: number): number {
  return price - (price * percentage / 100)
}

// WEAK: Test passes even if we mutate the calculation
test('applies discount', () => {
  const result = calculateDiscount(100, 10)
  expect(result).toBeDefined() // Too weak!
})

// STRONG: Test catches mutation
test('applies discount correctly', () => {
  expect(calculateDiscount(100, 10)).toBe(90)
  expect(calculateDiscount(100, 20)).toBe(80)
  expect(calculateDiscount(50, 10)).toBe(45)
})
```

## Python (mutmut)

### Installation

```bash
uv add --dev mutmut                    # Using uv
pip install mutmut                     # Using pip
```

### Running mutmut

```bash
uv run mutmut run                                          # Run mutation testing
uv run mutmut run --paths-to-mutate=src/calculator.py      # Specific files
uv run mutmut results                                      # Show results
uv run mutmut summary                                      # Summary
uv run mutmut show 1                                       # Show specific mutant
uv run mutmut apply 1                                      # Apply mutant manually
uv run mutmut html                                         # HTML report
```

### Understanding Results

```
Status: 45/50 mutants killed (90%)
- Killed: 45 (tests caught the mutation)
- Survived: 5 (tests passed despite mutation)
```

## Mutation Score Targets

| Score | Quality | Action |
|-------|---------|--------|
| 90%+ | Excellent | Maintain quality |
| 80-89% | Good | Small improvements |
| 70-79% | Acceptable | Focus on weak areas |
| 60-69% | Needs work | Add missing tests |
| < 60% | Poor | Major test improvements needed |

## Agentic Optimizations

| Context | Command |
|---------|---------|
| Quick TS mutation | `npx stryker run --incremental --reporters clear-text` |
| Targeted TS mutation | `npx stryker run --mutate "src/core/**/*.ts"` |
| Quick Python mutation | `uv run mutmut run --paths-to-mutate=src/core/` |
| View survived | `uv run mutmut results \| grep Survived` |
| CI mode | `npx stryker run --reporters json` |

For detailed examples, advanced patterns, and best practices, see [REFERENCE.md](REFERENCE.md).

## See Also

- `vitest-testing` - Unit testing framework
- `python-testing` - Python pytest testing
- `test-quality-analysis` - Detecting test smells
- `api-testing` - HTTP API testing

## References

- Stryker: https://stryker-mutator.io/
- mutmut: https://github.com/boxed/mutmut
- Mutation Testing Intro: https://en.wikipedia.org/wiki/Mutation_testing
