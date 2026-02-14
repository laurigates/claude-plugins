# Mutation Testing - Reference

Detailed reference material for mutation testing with Stryker and mutmut.

## Stryker Configuration

```typescript
// stryker.config.mjs
/** @type {import('@stryker-mutator/api/core').PartialStrykerOptions} */
export default {
  packageManager: 'bun',
  reporters: ['html', 'clear-text', 'progress', 'dashboard'],
  testRunner: 'vitest',
  coverageAnalysis: 'perTest',

  // Files to mutate
  mutate: [
    'src/**/*.ts',
    '!src/**/*.test.ts',
    '!src/**/*.spec.ts',
    '!src/**/*.d.ts',
  ],

  // Thresholds for CI
  thresholds: {
    high: 80,
    low: 60,
    break: 60, // Fail build if below this
  },

  // Incremental mode (faster)
  incremental: true,
  incrementalFile: '.stryker-tmp/incremental.json',

  // Concurrency
  concurrency: 4,

  // Timeout
  timeoutMS: 60000,
}
```

## Common Mutation Types (TypeScript/JavaScript)

```typescript
// Arithmetic Operator
// Original: a + b
// Mutants: a - b, a * b, a / b

// Relational Operator
// Original: a > b
// Mutants: a >= b, a < b, a <= b, a === b

// Conditional Boundary
// Original: a >= 10
// Mutants: a > 10, a < 10

// Logical Operator
// Original: a && b
// Mutants: a || b, a, b

// Unary Operator
// Original: !condition
// Mutants: condition

// String Literal
// Original: 'hello'
// Mutants: '', 'Stryker was here!'

// Boolean Literal
// Original: true
// Mutants: false

// Array Declaration
// Original: [1, 2, 3]
// Mutants: []
```

## Common Mutation Types (Python)

```python
# Arithmetic operators
# Original: a + b -> a - b, a * b, a / b, a // b, a % b

# Comparison operators
# Original: a > b -> a >= b, a < b, a <= b, a == b, a != b

# Logical operators
# Original: a and b -> a or b, a, b

# Assignment operators
# Original: a += 1 -> a -= 1, a *= 1, a /= 1

# Boolean literals
# Original: True -> False

# Number literals
# Original: 42 -> 43, 41

# String literals
# Original: "hello" -> "XXhelloXX", ""
```

## Ignoring Specific Mutations

### Stryker

```typescript
// Disable mutation for a block
// Stryker disable all
function debugOnlyCode() {
  console.log('This won\'t be mutated')
}
// Stryker restore all

// Disable specific mutator
// Stryker disable next-line ArithmeticOperator
const total = price + tax
```

### mutmut

```python
# Exclude entire function
# pragma: no mutate
def legacy_code():
    pass

# Exclude specific line
result = expensive_computation()  # pragma: no mutate
```

## mutmut Configuration

```toml
# pyproject.toml
[tool.mutmut]
paths_to_mutate = "src/"
backup = false
runner = "python -m pytest -x --assert=plain -q"
tests_dir = "tests/"
```

## mutmut Filtering Results

```bash
# Show only survived mutants
uv run mutmut results | grep "^Survived"

# Show killed mutants
uv run mutmut results | grep "^Killed"

# Show mutants for specific file
uv run mutmut show src/calculator.py
```

## CI/CD Integration

### Stryker (GitHub Actions)

```yaml
# .github/workflows/mutation.yml
name: Mutation Testing

on:
  pull_request:
    branches: [main]

jobs:
  mutation:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Setup Bun
        uses: oven-sh/setup-bun@v1

      - name: Install dependencies
        run: bun install

      - name: Run mutation tests
        run: bun run stryker run

      - name: Upload mutation report
        uses: actions/upload-artifact@v3
        if: always()
        with:
          name: mutation-report
          path: reports/mutation/html/
```

### mutmut (GitHub Actions)

```yaml
# .github/workflows/mutation.yml
name: Mutation Testing

on:
  pull_request:
    branches: [main]

jobs:
  mutation:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Install uv
        uses: astral-sh/setup-uv@v1

      - name: Install dependencies
        run: uv sync

      - name: Run mutation tests
        run: uv run mutmut run

      - name: Show results
        if: always()
        run: uv run mutmut results

      - name: Generate HTML report
        if: always()
        run: uv run mutmut html

      - name: Upload report
        uses: actions/upload-artifact@v3
        if: always()
        with:
          name: mutation-report
          path: html/
```

## Survived Mutants Analysis

**Common Reasons Mutants Survive:**

### 1. Missing assertions

```typescript
// Mutant survives
test('processes data', () => {
  processData(input)
  // No assertion!
})

// Fix: Add assertion
test('processes data', () => {
  const result = processData(input)
  expect(result).toEqual(expected)
})
```

### 2. Weak assertions

```python
# Mutant survives
def test_calculation():
    result = calculate(10, 5)
    assert result > 0  # Too weak!

# Fix: Specific assertion
def test_calculation():
    result = calculate(10, 5)
    assert result == 15
```

### 3. Dead code

```typescript
function example(x: number) {
  if (x > 10) {
    return 'large'
  }
  if (x < 0) {
    return 'negative'
  }
  return 'small'
  // Unreachable code mutated but never executed
}

// Fix: Remove dead code or add test
test('handles edge case', () => {
  expect(example(0)).toBe('small')
})
```

### 4. Equivalent mutants

```typescript
// Original
const result = x + 0

// Mutant (mathematically equivalent)
const result = x - 0

// Both produce same result - valid survivor
```

## Best Practices

**When to Run Mutation Tests**
- After achieving high code coverage (80%+)
- Before major releases
- On critical business logic modules
- When test quality is questioned
- In CI for important branches

**Incremental Approach**
1. Start with core business logic modules
2. Fix survived mutants
3. Gradually expand coverage
4. Integrate into CI pipeline
5. Maintain high mutation score

**Performance Optimization**
```typescript
// Stryker
export default {
  // Only mutate changed files
  incremental: true,

  // Focus on important files
  mutate: ['src/core/**/*.ts', 'src/utils/**/*.ts'],

  // Skip slow tests
  disableTypeChecks: '{src,test}/**/*.ts',

  // Adjust concurrency
  concurrency: 4,
}
```

```bash
# mutmut - incremental runs
uv run mutmut run --paths-to-mutate=src/core/
```

**Common Pitfalls**
- Running mutation tests before basic coverage
- Expecting 100% mutation score
- Not excluding generated code
- Treating equivalent mutants as failures
- Running full mutation suite on every commit

**Integration with Coverage**
```bash
# 1. First, ensure good coverage
vitest --coverage
# Target: 80%+ coverage

# 2. Then, validate test quality with mutations
npx stryker run
# Target: 80%+ mutation score
```

## Workflow Examples

### TypeScript/Vitest/Stryker

```bash
# 1. Write tests with coverage
bun test --coverage

# 2. Check coverage report
open coverage/index.html
# Ensure 80%+ coverage

# 3. Run mutation testing
npx stryker run

# 4. Check mutation report
open reports/mutation/html/index.html

# 5. Fix survived mutants by improving tests
# (Review each survived mutant)

# 6. Re-run mutation tests
npx stryker run --incremental
```

### Python/pytest/mutmut

```bash
# 1. Write tests with coverage
uv run pytest --cov

# 2. Check coverage report
uv run pytest --cov --cov-report=html
open htmlcov/index.html
# Ensure 80%+ coverage

# 3. Run mutation testing
uv run mutmut run

# 4. Check results
uv run mutmut results

# 5. Investigate survived mutants
uv run mutmut show <id>

# 6. Fix weak tests

# 7. Re-run on updated files
uv run mutmut run --paths-to-mutate=src/fixed_module.py
```

## Improving Weak Tests

### Pattern: Insufficient Assertions

```typescript
// Before: Mutation survives
test('calculates sum', () => {
  const result = sum([1, 2, 3])
  expect(result).toBeGreaterThan(0) // Weak!
})

// After: Mutation killed
test('calculates sum correctly', () => {
  expect(sum([1, 2, 3])).toBe(6)
  expect(sum([0, 0, 0])).toBe(0)
  expect(sum([-1, 1])).toBe(0)
  expect(sum([])).toBe(0)
})
```

### Pattern: Missing Edge Cases

```python
# Before: Mutation survives
def test_divide():
    result = divide(10, 2)
    assert result == 5

# After: Mutation killed
def test_divide():
    assert divide(10, 2) == 5
    assert divide(9, 3) == 3
    assert divide(7, 2) == 3.5
    with pytest.raises(ZeroDivisionError):
        divide(10, 0)
```

### Pattern: Boundary Conditions

```typescript
// Before: Mutation survives
test('validates age', () => {
  expect(isValidAge(25)).toBe(true)
})

// After: Mutation killed (tests boundaries)
test('validates age boundaries', () => {
  expect(isValidAge(18)).toBe(true)   // Min valid
  expect(isValidAge(17)).toBe(false)  // Just below
  expect(isValidAge(100)).toBe(true)  // Max valid
  expect(isValidAge(101)).toBe(false) // Just above
  expect(isValidAge(0)).toBe(false)
  expect(isValidAge(-1)).toBe(false)
})
```

## Troubleshooting

**Mutation tests taking too long**
```typescript
// Stryker: Increase concurrency
export default {
  concurrency: Math.max(os.cpus().length - 1, 1),
  timeoutMS: 30000,
}
```

```bash
# mutmut: Use caching
uv run mutmut run --use-coverage
```

**Too many survived mutants**
- Focus on critical modules first
- Add specific assertions
- Test boundary conditions
- Review mutation details

**All tests failing**
```bash
# Verify tests pass before mutations
bun test  # or uv run pytest
```

**False positives (equivalent mutants)**
```typescript
// Ignore mathematically equivalent mutants
// Stryker disable next-line all
const result = x + 0
```
