## test-run

## Your task

**Delegate this task to the `test-runner` agent.**

Use the Agent tool with `subagent_type: test-runner` to run tests with the appropriate framework. Pass all the context gathered above and the parsed parameters to the agent.

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

---

## test-report

## Cached Result Locations

| Framework | Cache Location |
|-----------|----------------|
| pytest | `.pytest_cache/`, `htmlcov/` |
| Vitest | `node_modules/.vitest/` |
| Jest | `coverage/`, `.jest-cache/` |
| Playwright | `test-results/`, `playwright-report/` |
| Go | `coverage.out` |
| Cargo | `target/debug/` |


## Behavior

1. **Find Latest Results**:
   - Check cache directories
   - Parse last run timestamp
   - Extract pass/fail counts

2. **Coverage Summary** (if --coverage):
   - Read coverage reports
   - Show percentage vs target
   - List uncovered files

3. **Flaky Detection** (if --flaky):
   - Compare recent runs
   - Identify tests with inconsistent results
   - Flag suspected flaky tests

4. **History** (if --history):
   - Show last 5 runs
   - Track pass rate trend
   - Identify regression patterns


## Output Format

```

## Test Status (last run: 5 minutes ago)

| Tier        | Passed | Failed | Skipped |
|-------------|--------|--------|---------|
| Unit        | 45     | 2      | 0       |
| Integration | 12     | 0      | 1       |
| E2E         | 8      | 1      | 0       |

**Coverage**: 78% (target: 80%)


### Recent Failures
- test_user_validation: AssertionError (tests/test_user.py:42)
- e2e/login.spec.ts: Timeout (line 15)


### Flaky Tests (if --flaky)
- test_async_handler: 3 failures in last 10 runs


### Suggested Actions
- Run `/test:quick` to verify current state
- Use `/test:consult coverage` for gap analysis
```


## Post-Actions

- If failures exist: Suggest `/test:quick` to verify current state
- If coverage low: Suggest `/test:consult coverage`
- If flaky detected: Suggest `/test:consult flaky`
- If stale (> 1 hour): Suggest running `/test:quick` or `/test:full`

---

## test-tier-selection

# Test Tier Selection

Automatic guidance for selecting appropriate test tiers based on change context and scope.


## Test Tier Definitions

| Tier | Duration | Scope | When to Run |
|------|----------|-------|-------------|
| **Unit** | < 30s | Single function/module | After every code change |
| **Integration** | < 5min | Component interactions | After feature completion |
| **E2E** | < 30min | Full user flows | Before commit/PR |


## Decision Matrix


### Change Type → Test Tier

| Change Type | Unit | Integration | E2E |
|-------------|------|-------------|-----|
| Single function fix | Required | Skip | Skip |
| New feature (1 file) | Required | Required | Skip |
| Multi-file feature | Required | Required | Required |
| Refactoring | Required | Required | Optional |
| API changes | Required | Required | Required |
| UI changes | Required | Optional | Required |
| Bug fix (isolated) | Required | Optional | Skip |
| Database changes | Required | Required | Required |
| Config changes | Required | Required | Optional |


## Escalation Signals

**Escalate to Integration when:**
- Changes span multiple files
- Business logic affected
- Service boundaries modified
- Database queries changed

**Escalate to E2E when:**
- User-facing features modified
- Authentication/authorization changes
- Critical path functionality
- Before creating PR


## Commands by Tier

```bash

# Tier 1: Unit (fast feedback)
/test:quick


# Tier 2: Integration (feature completion)
/test:full --coverage


# Tier 3: E2E (pre-commit)
/test:full
```


## Agent Consultation Triggers

**Consult `test-architecture` agent when:**
- New feature module created
- Coverage drops > 5%
- > 3 flaky tests detected
- Framework questions arise
- Test strategy needs adjustment

**Consult `test-runner` agent when:**
- Need test execution with analysis
- Multiple failures to diagnose
- Want concise failure summary

**Consult `system-debugging` agent when:**
- Integration test failures with unclear cause
- Environment/timing issues
- Flaky tests related to concurrency


### After Small Change
```
1. Run /test:quick
2. If pass: Continue working
3. If fail: Fix immediately
```


### After Feature Completion
```
1. Run /test:full --coverage
2. Check coverage targets met
3. If gaps: /test:consult coverage
```


### Before Commit/PR
```
1. Run /test:full
2. All tiers must pass
3. Review coverage report
```


### For New Features
```
1. /test:consult new-feature
2. Write tests (TDD)
3. Run /test:quick during development
4. Run /test:full before PR
```


## Activation Triggers

This skill auto-activates when:
- User mentions "test", "run tests", "testing"
- After code modification by Claude
- During TDD workflow
- When `/test:*` commands invoked
- When discussing test strategy

---

## test-analyze

# Test Analysis and Fix Planning

Analyzes test results from any testing framework, uses Zen planner to create a systematic fix strategy, and delegates fixes to appropriate subagents.


## Usage

```bash
/test:analyze <results-path> [--type <test-type>] [--focus <area>]
```


## Examples

```bash

# Analyze Playwright accessibility test results
/test:analyze ./test-results/ --type accessibility


# Analyze unit test failures with focus on auth
/test:analyze ./coverage/junit.xml --type unit --focus authentication


# Auto-detect test type and analyze all issues
/test:analyze ./test-output/


# Analyze security scan results
/test:analyze ./security-report.json --type security
```


## Command Flow

1. **Analyze Test Results**
   - Parse test result files (XML, JSON, HTML, text)
   - Extract failures, errors, warnings
   - Categorize issues by type and severity
   - Identify patterns and root causes

2. **Plan Fixes with PAL Planner**
   - Use `mcp__pal__planner` for systematic planning
   - Break down complex fixes into actionable steps
   - Identify dependencies between fixes
   - Estimate effort and priority

3. **Delegate to Subagents**
   - **Accessibility issues** → `code-review` agent (WCAG compliance)
   - **Security vulnerabilities** → `security-audit` agent
   - **Performance problems** → `system-debugging` agent
   - **Code quality issues** → `code-refactoring` agent
   - **Test infrastructure** → `test-architecture` agent
   - **Integration failures** → `system-debugging` agent
   - **Documentation gaps** → `documentation` agent

4. **Execute Plan**
   - Sequential execution based on dependencies
   - Verification after each fix
   - Re-run tests to confirm resolution


## Subagent Selection Logic

The command uses this decision tree to delegate:

- **Accessibility violations** (WCAG, ARIA, contrast)
  → `code-review` agent with accessibility focus

- **Security issues** (XSS, SQLi, auth bypass)
  → `security-audit` agent with OWASP analysis

- **Performance bottlenecks** (slow queries, memory leaks)
  → `system-debugging` agent with profiling

- **Code smells** (duplicates, complexity, coupling)
  → `code-refactoring` agent with SOLID principles

- **Flaky tests** (race conditions, timing issues)
  → `test-architecture` agent with stability analysis

- **Build/CI failures** (pipeline errors, dependency issues)
  → `cicd-pipelines` agent with workflow optimization


## Output

The command produces:

1. **Summary Report**
   - Total issues found
   - Breakdown by category/severity
   - Top priorities

2. **Fix Plan** (from PAL planner)
   - Step-by-step remediation strategy
   - Dependency graph
   - Effort estimates

3. **Subagent Assignments**
   - Which agent handles which issues
   - Rationale for delegation
   - Execution order

4. **Actionable Next Steps**
   - Commands to run
   - Files to modify
   - Verification steps


## Notes

- Works with any test framework that produces structured output
- Auto-detects common test result formats (JUnit XML, JSON, TAP)
- Preserves test evidence for debugging
- Can be chained with `/git:smartcommit` for automated fixes
- Respects TDD workflow (RED → GREEN → REFACTOR)


## Related Commands

- `/test:run` - Run tests with framework detection
- `/code:review` - Manual code review for test files
- `/docs:update` - Update test documentation
- `/git:smartcommit` - Commit fixes with conventional messages

---

**Prompt:**

Analyze test results from {{ARG1}} and create a systematic fix plan.

{{#if ARG2}}
Test type: {{ARG2}}
{{else}}
Auto-detect test type from file formats and content.
{{/if}}

{{#if ARG3}}
Focus area: {{ARG3}}
{{/if}}

**Step 1: Analyze Test Results**

Read the test result files from {{ARG1}} and extract:
- Failed tests with error messages
- Warnings and deprecations
- Performance metrics (if available)
- Coverage gaps (if available)
- Categorize by: severity (critical/high/medium/low), type (functional/security/performance/accessibility)

**Step 2: Use PAL Planner**

Call `mcp__pal__planner` with model "gemini-2.5-pro" to create a systematic fix plan:
- Step 1: Summarize findings and identify root causes
- Step 2: Prioritize issues (impact × effort matrix)
- Step 3: Break down fixes into actionable tasks
- Step 4: Identify dependencies between fixes
- Step 5: Assign each fix category to appropriate subagent
- Continue planning steps as needed for complex scenarios

**Step 3: Subagent Delegation Strategy**

Based on the issue categories, delegate to:

- **Accessibility violations** (WCAG, ARIA, color contrast, keyboard nav)
  → Use `Task` tool with `subagent_type: code-review`
  → Focus: WCAG 2.1 compliance, semantic HTML, ARIA best practices

- **Security vulnerabilities** (XSS, SQLi, CSRF, auth issues)
  → Use `Task` tool with `subagent_type: security-audit`
  → Focus: OWASP Top 10, input validation, authentication

- **Performance issues** (slow tests, memory leaks, timeouts)
  → Use `Task` tool with `subagent_type: system-debugging`
  → Focus: Profiling, bottleneck identification, optimization

- **Code quality** (duplicates, complexity, maintainability)
  → Use `Task` tool with `subagent_type: code-refactoring`
  → Focus: SOLID principles, DRY, code smells

- **Flaky/unreliable tests** (race conditions, timing, dependencies)
  → Use `Task` tool with `subagent_type: test-architecture`
  → Focus: Test stability, isolation, determinism

- **CI/CD failures** (build errors, pipeline issues)
  → Use `Task` tool with `subagent_type: cicd-pipelines`
  → Focus: GitHub Actions, dependency management, caching

- **Documentation gaps** (missing docs, outdated examples)
  → Use `Task` tool with `subagent_type: documentation`
  → Focus: API docs, test documentation, migration guides

**Step 4: Create Execution Plan**

For each subagent assignment:
1. **Context**: What files/areas need attention
2. **Objective**: Specific fix goal
3. **Success Criteria**: How to verify the fix
4. **Dependencies**: What must be done first
5. **Verification**: Commands to re-run tests

**Step 5: Present Summary**

Provide:
- 📊 **Issue Breakdown**: Count by category and severity
- 🎯 **Priorities**: Top 3-5 issues to fix first
- 🤖 **Subagent Plan**: Which agents will handle what
- ✅ **Next Steps**: Concrete actions to take
- 🔍 **Verification**: How to confirm fixes worked

{{#if ARG3}}
**Additional focus on {{ARG3}}**: Prioritize issues related to this area and provide extra context for relevant subagents.
{{/if}}

**Documentation-First Reminder**: Before implementing fixes, research relevant documentation using context7 to verify:
- Test framework best practices
- Accessibility standards (WCAG 2.1)
- Security patterns (OWASP)
- Performance optimization techniques

**TDD Workflow**: Follow RED → GREEN → REFACTOR:
1. Verify tests fail (RED) ✓ (already done)
2. Implement minimal fix (GREEN)
3. Refactor for quality
4. Re-run tests to confirm

Do you want me to proceed with the analysis and planning, or would you like to review the plan first?

---

## test-quality-analysis

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


## References

- Test Smells: https://testsmells.org/
- Test Double Patterns: https://martinfowler.com/bliki/TestDouble.html
- Testing Best Practices: https://kentcdodds.com/blog/common-mistakes-with-react-testing-library


# Test Quality Analysis - Reference

Detailed reference material for test quality analysis, test smell examples, and best practices.


## Test Smells - Detailed Examples


### Overmocking

**Problem**: Mocking too many dependencies, making tests fragile and disconnected from reality.

```typescript
// BAD: Overmocked
test('calculate total', () => {
  const mockAdd = vi.fn(() => 10)
  const mockMultiply = vi.fn(() => 20)
  const mockSubtract = vi.fn(() => 5)

  // Testing implementation, not behavior
  const result = calculate(mockAdd, mockMultiply, mockSubtract)
  expect(result).toBe(15)
})

// GOOD: Mock only external dependencies
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
// BAD: Fragile selector
test('submits form', async ({ page }) => {
  await page.locator('.form-container > div:nth-child(2) > button').click()
})

// GOOD: Semantic selector
test('submits form', async ({ page }) => {
  await page.getByRole('button', { name: 'Submit' }).click()
})
```

```python

# BAD: Tests implementation details
def test_user_creation():
    user = User()
    user._internal_id = 123  # Testing private attribute
    assert user._internal_id == 123


# GOOD: Tests public interface
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
- Test through public APIs and behavioral boundaries


### Flaky Tests

**Problem**: Tests pass or fail non-deterministically.

```typescript
// BAD: Race condition
test('loads data', async () => {
  fetchData()
  await new Promise(resolve => setTimeout(resolve, 1000))
  expect(data).toBeDefined()
})

// GOOD: Proper async handling
test('loads data', async () => {
  const data = await fetchData()
  expect(data).toBeDefined()
})
```

```python

# BAD: Time-dependent test
def test_expires_in_one_hour():
    token = create_token()
    time.sleep(3601)
    assert token.is_expired()


# GOOD: Inject time dependency
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
- Use explicit waiting mechanisms (waitFor, assertions with retries)
- Ensure test isolation
- Reset shared state between tests


### Test Duplication

**Problem**: Similar test logic repeated across multiple tests.

```typescript
// BAD: Duplicated setup
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

// GOOD: Extract to fixture/helper
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
// BAD: Unnecessary setup in every test
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

// GOOD: Shared expensive setup
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
// BAD: No assertion
test('creates user', async () => {
  await createUser({ name: 'John' })
  // No verification!
})

// BAD: Weak assertion
test('returns users', async () => {
  const users = await getUsers()
  expect(users).toBeDefined() // Too vague!
})

// BAD: Assertion on mock
test('calls API', async () => {
  const mockAPI = vi.fn()
  await service.fetchData(mockAPI)
  expect(mockAPI).toHaveBeenCalled() // Testing mock, not behavior
})

// GOOD: Strong, specific assertions
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

// BAD: Only tests happy path
test('applies SAVE20 discount', () => {
  expect(calculateDiscount(100, 'SAVE20')).toBe(80)
})

// GOOD: Tests all paths
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


## Coverage Analysis - Detailed Configuration


### TypeScript/JavaScript

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


### Python

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


## Best Practices Checklist


### Unit Test Quality (FIRST)

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
// GOOD: Descriptive test names
test('calculateTotal adds tax and shipping to subtotal', () => {})
test('login fails with invalid credentials', () => {})
test('createUser throws ValidationError for invalid email', () => {})

// BAD: Vague test names
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
    password: 'secure123',  // gitleaks:allow
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
// BAD
test('uses correct algorithm', () => {
  const spy = vi.spyOn(Math, 'sqrt')
  calculateDistance({ x: 0, y: 0 }, { x: 3, y: 4 })
  expect(spy).toHaveBeenCalled() // Testing how, not what
})

// GOOD
test('calculates distance correctly', () => {
  const distance = calculateDistance({ x: 0, y: 0 }, { x: 3, y: 4 })
  expect(distance).toBe(5) // Testing output
})
```


### Mocking Too Much

```typescript
// BAD: Mocking everything
const mockAdd = vi.fn((a, b) => a + b)
const mockMultiply = vi.fn((a, b) => a * b)
const mockFormat = vi.fn((n) => `$${n}`)

// GOOD: Use real implementations
import { add, multiply, format } from './utils'
// Only mock external services
const mockPaymentGateway = vi.fn()
```


### Ignoring Test Failures

```typescript
// BAD: Skipping failing tests
test.skip('this test is broken', () => {
  // Don't leave broken tests!
})

// GOOD: Fix or remove
test('feature works correctly', () => {
  // Fixed implementation
})
```


## Full Tools and Commands Reference


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
