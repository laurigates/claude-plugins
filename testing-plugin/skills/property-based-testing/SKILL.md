---
created: 2025-12-16
modified: 2026-05-23
reviewed: 2025-12-16
name: property-based-testing
description: "Property-based testing with fast-check (TS/JS) and Hypothesis (Python). Use when generating test data, finding edge cases, testing properties, or writing QuickCheck-style tests."
user-invocable: false
allowed-tools: Bash, Read, Edit, Write, Grep, Glob, TodoWrite
---

# Property-Based Testing

Expert knowledge for property-based testing - automatically generating test cases to verify code properties rather than testing specific examples.

## When to Use This Skill

| Use this skill when... | Use another skill instead when... |
|------------------------|----------------------------------|
| Testing mathematical properties (commutative, associative) | Writing specific example-based unit tests |
| Testing encode/decode roundtrips | Setting up test runner configuration |
| Finding edge cases automatically | Doing E2E browser testing |
| Validating data transformations and invariants | Analyzing test quality or smells |
| Testing API contracts with generated data | Running mutation testing |

## Core Expertise

**Property-Based Testing Concept**
- **Traditional testing**: Test specific examples
- **Property-based testing**: Test properties that should hold for all inputs
- **Generators**: Automatically create diverse test inputs
- **Shrinking**: Minimize failing cases to simplest example
- **Coverage**: Explore edge cases humans might miss

**When to Use Property-Based Testing**
- Mathematical operations (commutative, associative properties)
- Encoders/decoders (roundtrip properties)
- Parsers and serializers
- Data transformations
- API contracts
- Invariants and constraints

## TypeScript/JavaScript (fast-check)

### Installation

```bash
# Using Bun
bun add -d fast-check

# Using npm
npm install -D fast-check
```

### Basic Example

```typescript
import { test } from 'vitest'
import * as fc from 'fast-check'

// Property-based test
test('reverse twice returns original - property based', () => {
  fc.assert(
    fc.property(
      fc.array(fc.integer()), // Generate random arrays of integers
      (arr) => {
        expect(reverse(reverse(arr))).toEqual(arr)
      }
    )
  )
})
// fast-check automatically generates 100s of test cases!
```

### Key Generators (Quick Reference)

| Generator | Description |
|-----------|-------------|
| `fc.integer()` | Any integer (with optional min/max) |
| `fc.nat()` | Natural numbers (>= 0) |
| `fc.float()` / `fc.double()` | Floating-point numbers |
| `fc.string()` | Any string (with optional length) |
| `fc.emailAddress()` | Email format strings |
| `fc.array(arb)` | Arrays of arbitrary type |
| `fc.record({...})` | Object with typed fields |
| `fc.boolean()` | Boolean values |
| `fc.constantFrom(...)` | Pick from options |
| `fc.tuple(...)` | Fixed-size tuples |
| `fc.oneof(...)` | Union types |
| `fc.option(arb)` | Value or null |
| `fc.date()` | Date objects |

### Common Properties to Test

| Property | Pattern | Example |
|----------|---------|---------|
| Roundtrip | `f(g(x)) = x` | encode/decode, serialize/parse |
| Idempotence | `f(f(x)) = f(x)` | sort, normalize, format |
| Commutativity | `f(a,b) = f(b,a)` | add, merge, union |
| Associativity | `f(f(a,b),c) = f(a,f(b,c))` | add, concat |
| Identity | `f(x, id) = x` | multiply by 1, add 0 |
| Inverse | `f(g(x)) = x` | encrypt/decrypt |

### Configuration

```typescript
fc.assert(property, {
  numRuns: 1000,      // Run 1000 tests (default: 100)
  seed: 42,           // Reproducible tests
  endOnFailure: true, // Stop after first failure
})
```

### Preconditions

```typescript
fc.pre(b !== 0) // Skip cases where b is 0
```

## Python (Hypothesis)

### Installation

```bash
# Using uv
uv add --dev hypothesis pytest

# Optional extensions
uv add --dev hypothesis[numpy]   # NumPy strategies
uv add --dev hypothesis[django]  # Django model strategies
```

### Configuration

```toml
# pyproject.toml
[tool.hypothesis]
max_examples = 200
deadline = 1000

[tool.hypothesis.profiles.dev]
max_examples = 50
deadline = 1000

[tool.hypothesis.profiles.ci]
max_examples = 500
deadline = 5000
verbosity = "verbose"
```

```python
# Activate profile in conftest.py
from hypothesis import settings
settings.load_profile("ci")
```

### Basic Example

```python
from hypothesis import given, example, assume
import hypothesis.strategies as st

# Test a property
@given(st.integers(), st.integers())
def test_addition_commutative(a, b):
    assert a + b == b + a

# Add explicit edge cases with @example
@given(st.integers())
@example(0)
@example(-1)
@example(2**31 - 1)
def test_with_explicit_examples(x):
    assert process(x) is not None
```

### Key Strategies (Quick Reference)

| Strategy | Description |
|----------|-------------|
| `st.integers()` | Any integer (with optional bounds) |
| `st.floats()` | Floating-point numbers |
| `st.text()` | Any string (with optional size) |
| `st.binary()` | Byte strings |
| `st.lists(strat)` | Lists of given strategy |
| `st.sets(strat)` | Unique value sets |
| `st.dictionaries(k, v)` | Dictionaries |
| `st.booleans()` | Boolean values |
| `st.sampled_from(...)` | Pick from options |
| `st.tuples(...)` | Fixed-size tuples |
| `st.one_of(...)` | Union types |
| `st.emails()` | Valid email addresses |
| `st.uuids()` | UUID objects |
| `st.dates()` / `st.datetimes()` | Date/time values |
| `st.builds(Class, ...)` | Build objects from strategies |

### Configuration (Settings)

```python
from hypothesis import given, settings, strategies as st

@settings(max_examples=1000, deadline=None)
@given(st.lists(st.integers()))
def test_with_custom_settings(arr):
    assert sort(arr) == sorted(arr)
```

### Assumptions

```python
from hypothesis import assume
assume(b != 0)  # Skip cases where b is 0
```

### Stateful Testing

Hypothesis supports stateful testing via `RuleBasedStateMachine` for testing sequences of operations against invariants.

### CI Integration

```yaml
# .github/workflows/test.yml
- name: Run hypothesis tests
  run: |
    uv run pytest \
      --hypothesis-show-statistics \
      --hypothesis-profile=ci \
      --hypothesis-seed=${{ github.run_number }}

- name: Upload hypothesis database
  uses: actions/upload-artifact@v4
  if: failure()
  with:
    name: hypothesis-examples
    path: .hypothesis/
```

### Quick Reference

```python
# Core decorators
@given(strategy)              # Generate test inputs
@example(value)               # Add explicit test case
@settings(max_examples=500)   # Configure behavior

# Key helpers
assume(condition)             # Skip invalid inputs
note(message)                 # Add debug info to failure output
target(value)                 # Guide generation toward value
```

## Agentic Optimizations

| Context | Command |
|---------|---------|
| Quick TS test | `bunx vitest --dots --bail=1 --grep 'property'` |
| Quick Python test | `uv run pytest -x -q --tb=short -k 'property'` |
| CI TS test | `bunx vitest run --reporter=junit --grep 'property'` |
| CI Python test | `uv run pytest --hypothesis-profile=ci --hypothesis-show-statistics -q` |
| Reproducible | `fc.assert(prop, { seed: 42 })` or `pytest --hypothesis-seed=42` |
| Fast iteration | `fc.assert(prop, { numRuns: 50 })` or `pytest --hypothesis-profile=dev -x` |
| Debug failing | `pytest -x -s --hypothesis-verbosity=debug` |
| No shrinking | Add `phases=[Phase.generate]` to `@settings` |

For detailed examples, advanced patterns, and best practices, see [REFERENCE.md](REFERENCE.md).

## See Also

- `vitest-testing` - Unit testing framework
- `python-testing` - Python pytest testing
- `test-quality-analysis` - Detecting test smells
- `mutation-testing` - Validate test effectiveness

## References

- fast-check: https://fast-check.dev/
- Hypothesis: https://hypothesis.readthedocs.io/
- Property-Based Testing: https://fsharpforfunandprofit.com/posts/property-based-testing/
