---
model: opus
created: 2025-12-16
modified: 2025-12-16
reviewed: 2025-12-16
name: property-based-testing
description: |
  Property-based testing with fast-check (TypeScript/JavaScript) and Hypothesis (Python).
  Generate test cases automatically, find edge cases, and test mathematical properties.
  Use when user mentions property-based testing, fast-check, Hypothesis, generating
  test data, QuickCheck-style testing, or finding edge cases automatically.
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
uv add --dev hypothesis

# Using pip
pip install hypothesis
```

### Basic Example

```python
from hypothesis import given, strategies as st

@given(st.lists(st.integers()))
def test_reverse_twice_property(arr):
    assert reverse(reverse(arr)) == arr
    # Hypothesis automatically generates 100s of test cases!
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
| `st.dates()` / `st.datetimes()` | Date/time values |
| `st.builds(Class, ...)` | Build objects from strategies |

### Configuration

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

## Agentic Optimizations

| Context | Command |
|---------|---------|
| Quick TS test | `bunx vitest --dots --bail=1 --grep 'property'` |
| Quick Python test | `uv run pytest -x -q --tb=short -k 'property'` |
| CI TS test | `bunx vitest run --reporter=junit --grep 'property'` |
| CI Python test | `uv run pytest --hypothesis-show-statistics -q` |
| Reproducible | `fc.assert(prop, { seed: 42 })` or `@settings(derandomize=True)` |
| Fast iteration | `fc.assert(prop, { numRuns: 50 })` or `@settings(max_examples=50)` |

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
