---
model: opus
created: 2025-12-16
modified: 2025-12-16
reviewed: 2025-12-16
name: test-quality-analysis
description: Detect test smells, overmocking, flaky tests, and coverage issues. Analyze test effectiveness, maintainability, and reliability. Use when reviewing tests or improving test quality.
allowed-tools: Bash, Read, Edit, Write, Grep, Glob, TodoWrite
---

# Test Quality Analysis

Expert knowledge for analyzing and improving test quality - detecting test smells, overmocking, insufficient coverage, and other testing anti-patterns.

## When to Use This Skill

| Use this skill when... | Use another skill instead when... |
|------------------------|----------------------------------|
| Reviewing test quality and smells | Writing new unit tests (use vitest-testing) |
| Detecting overmocking or flaky tests | Setting up E2E tests (use playwright-testing) |
| Analyzing test coverage gaps | Validating tests via mutation (use mutation-testing) |
| Improving test maintainability | Generating test data (use property-based-testing) |
| Auditing test suites for anti-patterns | Writing Python tests (use python-testing) |

## Core Expertise

**Test Quality Dimensions**
- **Correctness**: Tests verify the right behavior
- **Reliability**: Tests are deterministic and not flaky
- **Maintainability**: Tests are easy to understand and modify
- **Performance**: Tests run quickly
- **Coverage**: Tests cover critical code paths
- **Isolation**: Tests don't depend on external state

## Test Smells - Quick Reference

| Smell | Symptom | Fix |
|-------|---------|-----|
| **Overmocking** | 3+ mocks per test; mocking pure functions | Mock only I/O boundaries; use real implementations |
| **Fragile tests** | Break on refactor without behavior change | Test public APIs; use semantic selectors |
| **Flaky tests** | Non-deterministic pass/fail | Proper async/await; mock time; ensure isolation |
| **Test duplication** | Copy-pasted setup across tests | Extract to `beforeEach()`, fixtures, helpers |
| **Slow tests** | Suite > 10s for unit tests | `beforeAll()` for expensive setup; parallelize |
| **Poor assertions** | `toBeDefined()`, no assertions, mock-only assertions | Specific matchers; assert outputs and state |
| **Insufficient coverage** | Critical paths untested | 80%+ on business logic; test error paths and boundaries |

## Analysis Tools

### TypeScript/JavaScript

```bash
vitest --coverage                              # Coverage report
vitest --coverage --coverage.thresholds.lines=80  # Threshold check
vitest --reporter=verbose                      # Find slow tests
```

### Python

```bash
uv run pytest --cov --cov-report=term-missing  # Coverage with missing lines
uv run pytest --cov --cov-fail-under=80        # Threshold check
uv run pytest --durations=10                   # Find slow tests
```

## Key Anti-Patterns

### Testing Implementation vs Behavior

```typescript
// BAD: Testing how
test('uses correct algorithm', () => {
  const spy = vi.spyOn(Math, 'sqrt')
  calculateDistance({ x: 0, y: 0 }, { x: 3, y: 4 })
  expect(spy).toHaveBeenCalled()
})

// GOOD: Testing what
test('calculates distance correctly', () => {
  const distance = calculateDistance({ x: 0, y: 0 }, { x: 3, y: 4 })
  expect(distance).toBe(5)
})
```

### Weak Assertions

```typescript
// BAD
expect(users).toBeDefined()     // Too vague
expect(mockAPI).toHaveBeenCalled() // Testing mock, not behavior

// GOOD
expect(user).toMatchObject({
  id: expect.any(Number),
  name: 'John',
  email: 'john@example.com',
})
```

### Missing Coverage

```typescript
// BAD: Only tests happy path
test('applies discount', () => {
  expect(calculateDiscount(100, 'SAVE20')).toBe(80)
})

// GOOD: Tests all paths
describe('calculateDiscount', () => {
  it('applies SAVE20', () => expect(calculateDiscount(100, 'SAVE20')).toBe(80))
  it('applies SAVE50', () => expect(calculateDiscount(100, 'SAVE50')).toBe(50))
  it('invalid coupon', () => expect(calculateDiscount(100, 'INVALID')).toBe(100))
  it('no coupon', () => expect(calculateDiscount(100)).toBe(100))
})
```

## Test Structure (AAA Pattern)

```typescript
test('user registration flow', async () => {
  // Arrange
  const userData = { email: 'user@example.com', password: 'secure123' }
  const mockEmailService = vi.fn()

  // Act
  const user = await registerUser(userData, mockEmailService)

  // Assert
  expect(user).toMatchObject({ email: 'user@example.com', emailVerified: false })
  expect(mockEmailService).toHaveBeenCalledWith('user@example.com', expect.any(String))
})
```

## Agentic Optimizations

| Context | Command |
|---------|---------|
| Coverage check (TS) | `vitest --coverage --reporter=dot` |
| Coverage check (Python) | `uv run pytest --cov --cov-fail-under=80 -q` |
| Find slow tests (TS) | `vitest --reporter=verbose` |
| Find slow tests (Python) | `uv run pytest --durations=10 -q` |
| Missing lines (Python) | `uv run pytest --cov --cov-report=term-missing` |

For detailed examples, advanced patterns, and best practices, see [REFERENCE.md](REFERENCE.md).

## See Also

- `vitest-testing` - TypeScript/JavaScript testing
- `python-testing` - Python pytest testing
- `playwright-testing` - E2E testing
- `mutation-testing` - Validate test effectiveness

## References

- Test Smells: https://testsmells.org/
- Test Double Patterns: https://martinfowler.com/bliki/TestDouble.html
- Testing Best Practices: https://kentcdodds.com/blog/common-mistakes-with-react-testing-library
