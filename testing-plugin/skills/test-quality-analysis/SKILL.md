---
name: Test Quality Analysis
description: Detect test smells, overmocking, flaky tests, and coverage issues. Analyze test effectiveness, maintainability, and reliability. Use when reviewing tests or improving test quality.
allowed-tools: Bash, Read, Edit, Write, Grep, Glob, TodoWrite
---

# Test Quality Analysis

Expert knowledge for analyzing and improving test quality - detecting test smells, overmocking, insufficient coverage, and other testing anti-patterns.

## Core Expertise

**Test Quality Dimensions**
- **Correctness**: Tests verify the right behavior
- **Reliability**: Tests are deterministic and not flaky
- **Maintainability**: Tests are easy to understand and modify
- **Performance**: Tests run quickly
- **Coverage**: Tests cover critical code paths
- **Isolation**: Tests don't depend on external state

## Test Smells

### Overmocking

**Problem**: Mocking too many dependencies, making tests fragile and disconnected from reality.

```typescript
// ❌ BAD: Overmocked
test('calculate total', () => {
  const mockAdd = vi.fn(() => 10)
  const mockMultiply = vi.fn(() => 20)
  const mockSubtract = vi.fn(() => 5)

  // Testing implementation, not behavior
  const result = calculate(mockAdd, mockMultiply, mockSubtract)
  expect(result).toBe(15)
})

// ✅ GOOD: Mock only external dependencies
test('calculate order total', () => {
  const mockPricingAPI = vi.fn(() => ({ tax: 0.1, shipping: 5 }))

  const order = { items: [{ price: 10 }, { price: 20 }] }
  const total = calculateTotal(order, mockPricingAPI)

  expect(total).toBe(38) // 30 + 3 tax + 5 shipping
})
```

**Detection**:
- More than 3-4 mocks in a single test
- Mocking internal utilities or pure functions
- Mocking data structures or value objects
- Complex mock setup that mirrors production code

**Fix**:
- Mock only I/O boundaries (APIs, databases, filesystem)
- Use real implementations for business logic
- Extract testable pure functions
- Consider integration tests instead

### Fragile Tests

**Problem**: Tests break with unrelated code changes.

```typescript
// ❌ BAD: Fragile selector
test('submits form', async ({ page }) => {
  await page.locator('.form-container > div:nth-child(2) > button').click()
})

// ✅ GOOD: Semantic selector
test('submits form', async ({ page }) => {
  await page.getByRole('button', { name: 'Submit' }).click()
})
```

```python
# ❌ BAD: Tests implementation details
def test_user_creation():
    user = User()
    user._internal_id = 123  # Testing private attribute
    assert user._internal_id == 123

# ✅ GOOD: Tests public interface
def test_user_creation():
    user = User(id=123)
    assert user.get_id() == 123
```

**Detection**:
- Tests break when refactoring without changing behavior
- Assertions on private methods or attributes
- Brittle CSS selectors in E2E tests
- Testing implementation details vs. behavior

**Fix**:
- Test public APIs, not internal implementation
- Use semantic selectors (role, label, text)
- Follow the "test behavior, not implementation" principle
- Avoid testing private methods directly

### Flaky Tests

**Problem**: Tests pass or fail non-deterministically.

```typescript
// ❌ BAD: Race condition
test('loads data', async () => {
  fetchData()
  await new Promise(resolve => setTimeout(resolve, 1000))
  expect(data).toBeDefined()
})

// ✅ GOOD: Proper async handling
test('loads data', async () => {
  const data = await fetchData()
  expect(data).toBeDefined()
})
```

```python
# ❌ BAD: Time-dependent test
def test_expires_in_one_hour():
    token = create_token()
    time.sleep(3601)
    assert token.is_expired()

# ✅ GOOD: Inject time dependency
def test_expires_in_one_hour():
    now = datetime(2024, 1, 1, 12, 0)
    future = datetime(2024, 1, 1, 13, 1)
    token = create_token(now)
    assert token.is_expired(future)
```

**Detection**:
- Test passes locally but fails in CI
- Test fails when run in different order
- Tests with arbitrary `sleep()` or `setTimeout()`
- Timing-dependent assertions

**Fix**:
- Use proper async/await patterns
- Mock time and dates
- Avoid arbitrary waits, use explicit waiting
- Ensure test isolation
- Reset shared state between tests

### Test Duplication

**Problem**: Similar test logic repeated across multiple tests.

```typescript
// ❌ BAD: Duplicated setup
test('user can edit profile', async ({ page }) => {
  await page.goto('/login')
  await page.fill('[name=email]', 'user@example.com')
  await page.fill('[name=password]', 'password')
  await page.click('button[type=submit]')
  await page.goto('/profile')
  // Test logic...
})

test('user can view settings', async ({ page }) => {
  await page.goto('/login')
  await page.fill('[name=email]', 'user@example.com')
  await page.fill('[name=password]', 'password')
  await page.click('button[type=submit]')
  await page.goto('/settings')
  // Test logic...
})

// ✅ GOOD: Extract to fixture/helper
async function loginAsUser(page) {
  await page.goto('/login')
  await page.fill('[name=email]', 'user@example.com')
  await page.fill('[name=password]', 'password')
  await page.click('button[type=submit]')
}

test('user can edit profile', async ({ page }) => {
  await loginAsUser(page)
  await page.goto('/profile')
  // Test logic...
})
```

**Detection**:
- Copy-pasted test setup code
- Similar assertion patterns across tests
- Repeated fixture or mock configurations

**Fix**:
- Extract common setup to `beforeEach()` hooks
- Create reusable fixtures or test helpers
- Use parameterized tests for similar scenarios
- Apply DRY principle to test code

### Slow Tests

**Problem**: Tests take too long to run, slowing down feedback loop.

```typescript
// ❌ BAD: Unnecessary setup in every test
describe('User API', () => {
  beforeEach(async () => {
    await database.migrate() // Slow!
    await seedDatabase()     // Slow!
  })

  test('creates user', async () => {
    const user = await createUser({ name: 'John' })
    expect(user.name).toBe('John')
  })

  test('updates user', async () => {
    const user = await createUser({ name: 'John' })
    await updateUser(user.id, { name: 'Jane' })
    expect(user.name).toBe('Jane')
  })
})

// ✅ GOOD: Shared expensive setup
describe('User API', () => {
  beforeAll(async () => {
    await database.migrate()
    await seedDatabase()
  })

  beforeEach(async () => {
    await cleanUserTable() // Fast!
  })

  // Tests...
})
```

**Detection**:
- Test suite takes > 10 seconds for unit tests
- Unnecessary database migrations in tests
- No parallelization of independent tests
- Excessive E2E tests for unit-testable logic

**Fix**:
- Use `beforeAll()` for expensive one-time setup
- Mock external dependencies
- Run tests in parallel
- Push tests down the pyramid (more unit, fewer E2E)
- Use in-memory databases or test doubles

### Poor Assertions

**Problem**: Weak or missing assertions that don't verify behavior.

```typescript
// ❌ BAD: No assertion
test('creates user', async () => {
  await createUser({ name: 'John' })
  // No verification!
})

// ❌ BAD: Weak assertion
test('returns users', async () => {
  const users = await getUsers()
  expect(users).toBeDefined() // Too vague!
})

// ❌ BAD: Assertion on mock
test('calls API', async () => {
  const mockAPI = vi.fn()
  await service.fetchData(mockAPI)
  expect(mockAPI).toHaveBeenCalled() // Testing mock, not behavior
})

// ✅ GOOD: Strong, specific assertions
test('creates user with correct attributes', async () => {
  const user = await createUser({ name: 'John', email: 'john@example.com' })

  expect(user).toMatchObject({
    id: expect.any(Number),
    name: 'John',
    email: 'john@example.com',
    createdAt: expect.any(Date),
  })
})
```

**Detection**:
- Tests with no assertions
- Assertions only on mocks, not outputs
- Vague assertions (`toBeDefined()`, `toBeTruthy()`)
- Not testing edge cases or error conditions

**Fix**:
- Assert on actual outputs and side effects
- Use specific matchers
- Test both happy path and error cases
- Verify state changes, not just mock calls

### Insufficient Coverage

**Problem**: Critical code paths not tested.

```typescript
// Source code
function calculateDiscount(price: number, coupon?: string): number {
  if (coupon === 'SAVE20') return price * 0.8
  if (coupon === 'SAVE50') return price * 0.5
  return price
}

// ❌ BAD: Only tests happy path
test('applies SAVE20 discount', () => {
  expect(calculateDiscount(100, 'SAVE20')).toBe(80)
})

// ✅ GOOD: Tests all paths
describe('calculateDiscount', () => {
  it('applies SAVE20 discount', () => {
    expect(calculateDiscount(100, 'SAVE20')).toBe(80)
  })

  it('applies SAVE50 discount', () => {
    expect(calculateDiscount(100, 'SAVE50')).toBe(50)
  })

  it('returns original price for invalid coupon', () => {
    expect(calculateDiscount(100, 'INVALID')).toBe(100)
  })

  it('returns original price when no coupon provided', () => {
    expect(calculateDiscount(100)).toBe(100)
  })
})
```

**Detection**:
- Coverage below 80% for critical modules
- Untested error handling paths
- Missing edge case tests
- No tests for boundary conditions

**Fix**:
- Aim for 80%+ coverage on business logic
- Test error paths and exceptions
- Test boundary values (0, null, max values)
- Use mutation testing to find weak tests

## Analysis Tools

### Coverage Analysis (TypeScript/JavaScript)

```bash
# Vitest coverage
vitest --coverage

# View HTML report
open coverage/index.html

# Check thresholds
vitest --coverage --coverage.thresholds.lines=80
```

```typescript
// vitest.config.ts
export default defineConfig({
  test: {
    coverage: {
      provider: 'v8',
      reporter: ['text', 'html', 'lcov'],
      thresholds: {
        lines: 80,
        functions: 80,
        branches: 80,
        statements: 80,
      },
      exclude: [
        'node_modules/',
        '**/*.config.ts',
        '**/*.d.ts',
        '**/types/**',
      ],
    },
  },
})
```

### Coverage Analysis (Python)

```bash
# pytest-cov
uv run pytest --cov --cov-report=html

# View report
open htmlcov/index.html

# Show missing lines
uv run pytest --cov --cov-report=term-missing

# Fail if below threshold
uv run pytest --cov --cov-fail-under=80
```

```toml
# pyproject.toml
[tool.coverage.run]
source = ["src"]
branch = true
omit = ["*/tests/*", "*/test_*.py"]

[tool.coverage.report]
precision = 2
show_missing = true
skip_covered = false

[tool.coverage.html]
directory = "htmlcov"
```

### Test Performance Analysis

```bash
# Vitest: Show slow tests
vitest --reporter=verbose

# pytest: Show slowest tests
uv run pytest --durations=10

# pytest: Profile test execution
uv run pytest --profile

# Playwright: Trace for performance
npx playwright test --trace on
```

## Best Practices Checklist

### Unit Test Quality

- [ ] **Fast**: Tests run in milliseconds
- [ ] **Isolated**: No dependencies between tests
- [ ] **Repeatable**: Same results every time
- [ ] **Self-validating**: Clear pass/fail without manual inspection
- [ ] **Timely**: Written alongside code (TDD)

### Mock Usage Guidelines

- [ ] Mock only external dependencies (APIs, databases, filesystem)
- [ ] Don't mock business logic or pure functions
- [ ] Don't mock data structures or value objects
- [ ] Use real implementations when possible
- [ ] Limit to 3-4 mocks per test maximum

### Test Coverage Goals

- [ ] 80%+ line coverage for business logic
- [ ] 100% coverage for critical paths (payment, auth, security)
- [ ] All error paths tested
- [ ] Boundary conditions tested
- [ ] Happy path and edge cases covered

### Test Naming

```typescript
// ✅ GOOD: Descriptive test names
test('calculateTotal adds tax and shipping to subtotal', () => {})
test('login fails with invalid credentials', () => {})
test('createUser throws ValidationError for invalid email', () => {})

// ❌ BAD: Vague test names
test('test1', () => {})
test('works correctly', () => {})
test('handles error', () => {})
```

### Test Structure (AAA Pattern)

```typescript
test('user registration flow', async () => {
  // Arrange: Setup test data and dependencies
  const userData = {
    email: 'user@example.com',
    password: 'secure123',  // pragma: allowlist secret
  }
  const mockEmailService = vi.fn()

  // Act: Execute the behavior being tested
  const user = await registerUser(userData, mockEmailService)

  // Assert: Verify the expected outcome
  expect(user).toMatchObject({
    email: 'user@example.com',
    emailVerified: false,
  })
  expect(mockEmailService).toHaveBeenCalledWith(
    'user@example.com',
    expect.any(String)
  )
})
```

## Code Review Checklist

When reviewing tests, check for:

### Correctness
- [ ] Tests verify actual behavior, not implementation
- [ ] Assertions are specific and meaningful
- [ ] Error cases are tested
- [ ] Edge cases are covered

### Reliability
- [ ] No flaky tests (timing, ordering issues)
- [ ] Proper async/await usage
- [ ] No arbitrary waits (`sleep`, `setTimeout`)
- [ ] Tests are isolated and independent

### Maintainability
- [ ] Test names clearly describe behavior
- [ ] Tests follow AAA pattern (Arrange, Act, Assert)
- [ ] Minimal code duplication
- [ ] Clear and focused assertions

### Performance
- [ ] Unit tests run in < 10 seconds total
- [ ] Expensive setup in `beforeAll()`, not `beforeEach()`
- [ ] Tests run in parallel when possible
- [ ] Mocks used for slow dependencies

### Coverage
- [ ] Critical paths have tests
- [ ] Coverage meets threshold (80%+)
- [ ] Both happy path and error cases covered
- [ ] Boundary conditions tested

## Refactoring Test Smells

### Overmocking Refactor

```typescript
// Before: Overmocked
test('processes order', () => {
  const mockValidator = vi.fn(() => true)
  const mockCalculator = vi.fn(() => 100)
  const mockFormatter = vi.fn(() => '$100.00')

  const result = processOrder(mockValidator, mockCalculator, mockFormatter)
  expect(result).toBe('$100.00')
})

// After: Mock only I/O
test('processes order and sends confirmation', async () => {
  const mockEmailService = vi.fn()

  const order = { items: [{ price: 50 }, { price: 50 }] }
  await processOrder(order, mockEmailService)

  expect(mockEmailService).toHaveBeenCalledWith(
    expect.objectContaining({
      total: 100,
      formattedTotal: '$100.00',
    })
  )
})
```

### Flaky Test Refactor

```typescript
// Before: Flaky
test('animation completes', async () => {
  triggerAnimation()
  await new Promise(resolve => setTimeout(resolve, 500))
  expect(isAnimationComplete()).toBe(true)
})

// After: Deterministic
test('animation completes', async () => {
  vi.useFakeTimers()

  triggerAnimation()
  vi.advanceTimersByTime(500)

  expect(isAnimationComplete()).toBe(true)

  vi.restoreAllMocks()
})
```

## Common Anti-Patterns

### Testing Implementation Details

```typescript
// ❌ BAD
test('uses correct algorithm', () => {
  const spy = vi.spyOn(Math, 'sqrt')
  calculateDistance({ x: 0, y: 0 }, { x: 3, y: 4 })
  expect(spy).toHaveBeenCalled() // Testing how, not what
})

// ✅ GOOD
test('calculates distance correctly', () => {
  const distance = calculateDistance({ x: 0, y: 0 }, { x: 3, y: 4 })
  expect(distance).toBe(5) // Testing output
})
```

### Mocking Too Much

```typescript
// ❌ BAD: Mocking everything
const mockAdd = vi.fn((a, b) => a + b)
const mockMultiply = vi.fn((a, b) => a * b)
const mockFormat = vi.fn((n) => `$${n}`)

// ✅ GOOD: Use real implementations
import { add, multiply, format } from './utils'
// Only mock external services
const mockPaymentGateway = vi.fn()
```

### Ignoring Test Failures

```typescript
// ❌ BAD: Skipping failing tests
test.skip('this test is broken', () => {
  // Don't leave broken tests!
})

// ✅ GOOD: Fix or remove
test('feature works correctly', () => {
  // Fixed implementation
})
```

## Tools and Commands

### TypeScript/JavaScript

```bash
# Run tests with coverage
vitest --coverage

# Find slow tests
vitest --reporter=verbose

# Watch mode for TDD
vitest --watch

# UI mode for debugging
vitest --ui

# Generate coverage report
vitest --coverage --coverage.reporter=html
```

### Python

```bash
# Run tests with coverage
uv run pytest --cov

# Show missing lines
uv run pytest --cov --cov-report=term-missing

# Find slow tests
uv run pytest --durations=10

# Run only failed tests
uv run pytest --lf

# Generate HTML coverage report
uv run pytest --cov --cov-report=html
```

## See Also

- `vitest-testing` - TypeScript/JavaScript testing
- `python-testing` - Python pytest testing
- `playwright-testing` - E2E testing
- `mutation-testing` - Validate test effectiveness

## References

- Test Smells: https://testsmells.org/
- Test Double Patterns: https://martinfowler.com/bliki/TestDouble.html
- Testing Best Practices: https://kentcdodds.com/blog/common-mistakes-with-react-testing-library
