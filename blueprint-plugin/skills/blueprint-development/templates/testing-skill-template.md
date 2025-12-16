---
name: testing-strategies
description: "TDD workflow, testing patterns, and coverage requirements for [PROJECT_NAME]. Enforces test-first development and defines testing standards."
---

# Testing Strategies

## TDD Workflow

Follow strict **RED → GREEN → REFACTOR** cycle:

### RED - Write Failing Test
1. Write a test describing desired behavior
2. Run test suite: `[test_command]`
3. Confirm test **FAILS** (expected failure)

### GREEN - Minimal Implementation
1. Write minimal code to pass the test
2. Run test suite: `[test_command]`
3. Confirm test **PASSES**

### REFACTOR - Improve Code
1. Identify refactoring opportunities
2. Refactor while keeping tests green
3. Run test suite: `[test_command]`
4. Confirm tests **STILL PASS**

**Never skip RED**: If test passes immediately, the test is wrong or unnecessary.

**Never skip REFACTOR**: Technical debt accumulates if you skip refactoring.

## Test Structure

```
[tests_directory]/
├── unit/               # Unit tests for individual functions/classes
│   ├── [module1]/
│   └── [module2]/
├── integration/        # Integration tests for component interactions
│   ├── [area1]/
│   └── [area2]/
└── e2e/               # End-to-end tests for user flows
    ├── [flow1]/
    └── [flow2]/
```

**Naming Conventions**:
- Unit tests: `[filename].test.js` or `[filename].spec.js`
- Integration tests: `[feature].integration.test.js`
- E2E tests: `[flow].e2e.test.js`

## Test Types

### Unit Tests

**Purpose**: Test individual functions, classes, or components in isolation

**Location**: `[unit_test_directory]/`

**What to unit test**:
- [Item 1: e.g., "Business logic in service layer"]
- [Item 2: e.g., "Pure functions and utilities"]
- [Item 3: e.g., "Data transformations"]
- [Item 4: e.g., "Validation logic"]

**What NOT to unit test**:
- [Item 1: e.g., "Framework code or libraries"]
- [Item 2: e.g., "Trivial getters/setters"]
- [Item 3: e.g., "Configuration files"]

**Pattern**:
```[language]
describe('[Component/Function Name]', () => {
  describe('[Method/Behavior]', () => {
    it('should [expected behavior]', () => {
      // Arrange
      [setup_code]

      // Act
      [execution_code]

      // Assert
      [assertion_code]
    });

    it('should [handle error case]', () => {
      // Test error handling
    });
  });
});
```

**Example**:
```[language]
[CONCRETE_UNIT_TEST_EXAMPLE]
```

### Integration Tests

**Purpose**: Test interactions between components, with real dependencies

**Location**: `[integration_test_directory]/`

**What to integration test**:
- [Item 1: e.g., "API endpoints with real database"]
- [Item 2: e.g., "Service interactions"]
- [Item 3: e.g., "Data access layer with database"]
- [Item 4: e.g., "Authentication/authorization flows"]

**Setup**:
- [Setup requirement 1: e.g., "Use test database / test containers"]
- [Setup requirement 2: e.g., "Seed test data before each test"]
- [Setup requirement 3: e.g., "Clean up after each test"]

**Pattern**:
```[language]
describe('[Feature] Integration', () => {
  beforeAll(async () => {
    // Setup (e.g., connect to test database)
  });

  beforeEach(async () => {
    // Reset state (e.g., clear database)
  });

  afterAll(async () => {
    // Cleanup (e.g., disconnect from database)
  });

  it('should [test end-to-end scenario]', async () => {
    // Test with real dependencies
  });
});
```

**Example**:
```[language]
[CONCRETE_INTEGRATION_TEST_EXAMPLE]
```

### End-to-End Tests

**Purpose**: Test complete user flows from start to finish

**Location**: `[e2e_test_directory]/`

**What to E2E test**:
- [Flow 1: e.g., "User registration → login → access protected resource"]
- [Flow 2: e.g., "Product search → add to cart → checkout"]
- [Flow 3: e.g., "Create account → verify email → complete profile"]

**Setup**:
- [Setup requirement 1: e.g., "Run application in test environment"]
- [Setup requirement 2: e.g., "Use headless browser for UI tests"]
- [Setup requirement 3: e.g., "Reset test database before each test"]

**Pattern**:
```[language]
describe('[User Flow]', () => {
  it('should [complete the flow successfully]', async () => {
    // Step 1: [User action]
    [step_1_code]

    // Step 2: [User action]
    [step_2_code]

    // Step 3: [User action]
    [step_3_code]

    // Assert final state
    [assertion_code]
  });
});
```

**Example**:
```[language]
[CONCRETE_E2E_TEST_EXAMPLE]
```

## Mocking Patterns

### When to Mock

**DO mock**:
- [Scenario 1: e.g., "External APIs in unit tests"]
- [Scenario 2: e.g., "Time-dependent functions (Date.now)"]
- [Scenario 3: e.g., "File system operations in unit tests"]
- [Scenario 4: e.g., "Expensive computations in unit tests"]

**DON'T mock**:
- [Scenario 1: e.g., "The system under test"]
- [Scenario 2: e.g., "Simple data structures"]
- [Scenario 3: e.g., "Internal dependencies in integration tests"]

### Mocking Library

**Tool**: [Jest / Sinon / Mock / etc.]

**Patterns**:

#### Mock External Service
```[language]
// Mock pattern for external service
[MOCK_EXAMPLE_1]
```

#### Mock Database
```[language]
// Mock pattern for database
[MOCK_EXAMPLE_2]
```

#### Spy on Function
```[language]
// Spy pattern
[SPY_EXAMPLE]
```

### Test Doubles

**Types**:
- **Stub**: Returns predefined values
- **Mock**: Verifies behavior (method calls, arguments)
- **Spy**: Records calls without changing behavior
- **Fake**: Working implementation for testing (e.g., in-memory database)

**Guidelines**:
- [Guideline 1: e.g., "Use stubs for simple value returns"]
- [Guideline 2: e.g., "Use mocks to verify interactions"]
- [Guideline 3: e.g., "Use fakes for complex dependencies"]

## Coverage Requirements

### Overall Coverage
- **Minimum**: [X]% overall test coverage
- **Target**: [Y]% overall test coverage

### Critical Path Coverage
- **Requirement**: [100]% coverage for [critical areas]
- **Critical areas**:
  - [Area 1: e.g., "Authentication and authorization"]
  - [Area 2: e.g., "Payment processing"]
  - [Area 3: e.g., "Data validation"]

### Edge Case Coverage
- **Requirement**: All error paths and edge cases tested
- **Examples**:
  - [Edge case 1: e.g., "Empty inputs"]
  - [Edge case 2: e.g., "Boundary values"]
  - [Edge case 3: e.g., "Concurrent access"]
  - [Edge case 4: e.g., "Network failures"]

### Measuring Coverage
```bash
# Run tests with coverage
[coverage_command]

# View coverage report
[coverage_report_command]

# Coverage thresholds
[coverage_threshold_config]
```

**Coverage Tools**: [Istanbul / nyc / Coverage.py / etc.]

## Test Organization

### Test File Structure
```[language]
// Recommended test structure
describe('[Component/Module Name]', () => {
  // Setup
  beforeEach(() => {
    // Common setup
  });

  // Happy path tests
  describe('when [normal condition]', () => {
    it('should [expected behavior]', () => {
      // Test implementation
    });
  });

  // Edge case tests
  describe('when [edge case condition]', () => {
    it('should [expected behavior]', () => {
      // Test implementation
    });
  });

  // Error case tests
  describe('when [error condition]', () => {
    it('should [expected error handling]', () => {
      // Test implementation
    });
  });
});
```

### Test Data Management

**Approach**: [Fixtures / Factories / Builders / Seeds]

**Location**: `[test_data_directory]/`

**Pattern**:
```[language]
// Test data pattern
[TEST_DATA_EXAMPLE]
```

**Guidelines**:
- [Guideline 1: e.g., "Use factories for flexible test data"]
- [Guideline 2: e.g., "Use fixtures for complex scenarios"]
- [Guideline 3: e.g., "Keep test data minimal and focused"]

## Test Commands

### Run All Tests
```bash
[run_all_tests_command]
```

### Run Unit Tests Only
```bash
[run_unit_tests_command]
```

### Run Integration Tests Only
```bash
[run_integration_tests_command]
```

### Run E2E Tests Only
```bash
[run_e2e_tests_command]
```

### Run Specific Test File
```bash
[run_specific_test_command] [file_path]
```

### Watch Mode
```bash
[watch_mode_command]
```

### Debug Tests
```bash
[debug_tests_command]
```

## Performance Testing

**When required**: [Scenarios where performance tests are needed]

**Tools**: [Performance testing tools]

**Baselines**:
- [Metric 1]: [Target value]
- [Metric 2]: [Target value]

**Pattern**:
```[language]
// Performance test pattern
[PERFORMANCE_TEST_EXAMPLE]
```

## Test Maintenance

### When to Update Tests

**Update tests when**:
- [Scenario 1: e.g., "Requirements change"]
- [Scenario 2: e.g., "Refactoring changes behavior"]
- [Scenario 3: e.g., "New edge cases discovered"]

**DON'T update tests when**:
- [Scenario 1: e.g., "Just to make them pass (fix code instead)"]
- [Scenario 2: e.g., "Internal refactoring (behavior unchanged)"]

### Flaky Tests

**Definition**: Tests that intermittently fail without code changes

**Common causes**:
- [Cause 1: e.g., "Race conditions"]
- [Cause 2: e.g., "Time-dependent logic"]
- [Cause 3: e.g., "External dependencies"]
- [Cause 4: e.g., "Test data pollution"]

**Solutions**:
- [Solution 1: e.g., "Use deterministic mocks"]
- [Solution 2: e.g., "Reset state between tests"]
- [Solution 3: e.g., "Add proper test isolation"]

### Test Smells

**Signs of bad tests**:
- [Smell 1: e.g., "Tests that test implementation details"]
- [Smell 2: e.g., "Tests with unclear assertions"]
- [Smell 3: e.g., "Tests that depend on execution order"]
- [Smell 4: e.g., "Tests with no assertions"]

**How to fix**:
- [Fix 1]
- [Fix 2]
- [Fix 3]

## Testing Best Practices

### AAA Pattern
- **Arrange**: Set up test data and context
- **Act**: Execute the behavior being tested
- **Assert**: Verify the outcome

### One Assertion Per Test

**Preference**: [Single assertion vs multiple assertions]

**Rationale**: [Why this approach is chosen]

### Test Naming

**Convention**: [Pattern for test names]

**Examples**:
- `should [action] when [condition]`
- `should return [result] given [input]`
- `should throw [error] when [invalid state]`

### Test Independence

**Requirement**: Each test should be independent

**Guidelines**:
- [Guideline 1: e.g., "No shared mutable state"]
- [Guideline 2: e.g., "Tests can run in any order"]
- [Guideline 3: e.g., "Use beforeEach for setup"]

### Readability

**Priority**: Tests should be easy to understand

**Guidelines**:
- [Guideline 1: e.g., "Use descriptive variable names"]
- [Guideline 2: e.g., "Keep tests focused and short"]
- [Guideline 3: e.g., "Extract helpers for common patterns"]

## Common Pitfalls

### Pitfall 1: [Description]

**Problem**: [What happens]

**Solution**: [How to avoid]

**Example**:
```[language]
// Bad
[BAD_TEST_EXAMPLE]

// Good
[GOOD_TEST_EXAMPLE]
```

### Pitfall 2: [Description]

**Problem**: [What happens]

**Solution**: [How to avoid]

**Example**:
```[language]
// Bad
[BAD_TEST_EXAMPLE]

// Good
[GOOD_TEST_EXAMPLE]
```

## CI/CD Integration

### Running Tests in CI

**Configuration**: [CI config file location]

**Pattern**:
```yaml
# CI configuration excerpt
[CI_CONFIG_EXAMPLE]
```

**Requirements**:
- [Requirement 1: e.g., "All tests must pass before merge"]
- [Requirement 2: e.g., "Coverage threshold enforced"]
- [Requirement 3: e.g., "E2E tests run on staging"]

## References

- [Link to PRD TDD requirements]
- [Link to testing framework documentation]
- [Link to related skills]

---

**Note**: This skill is generated from PRDs. Update this file as testing patterns evolve during development.
