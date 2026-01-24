---
model: haiku
created: 2025-12-16
modified: 2026-01-24
reviewed: 2026-01-24
name: hypothesis-testing
description: |
  Property-based testing with Hypothesis for discovering edge cases and validating invariants.
  Use when testing code with many possible inputs, verifying mathematical properties,
  testing serialization round-trips, or finding edge cases that example-based tests miss.
allowed-tools: Bash, Read, Grep, Glob
---

# Hypothesis Property-Based Testing

Automatically generate test cases to find edge cases and validate properties of your code.

## When to Use Hypothesis vs Example-Based Tests

| Use Hypothesis when... | Use example-based tests when... |
|------------------------|-------------------------------|
| Testing mathematical properties (commutative, associative) | Testing specific known edge cases |
| Many valid inputs need testing | Exact business logic with known values |
| Verifying serialization round-trips | Testing specific error messages |
| Finding edge cases you can't predict | Integration with external systems |
| Testing APIs with many parameters | Testing UI behavior |

## Installation

```bash
uv add --dev hypothesis pytest

# Optional extensions
uv add --dev hypothesis[numpy]   # NumPy strategies
uv add --dev hypothesis[django]  # Django model strategies
```

## Configuration

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
# Activate profile
from hypothesis import settings, Phase
settings.load_profile("ci")  # Use in conftest.py
```

## Basic Usage

```python
from hypothesis import given, example, assume
import hypothesis.strategies as st

# Test a property
@given(st.integers(), st.integers())
def test_addition_commutative(a, b):
    assert a + b == b + a

# Add explicit edge cases
@given(st.integers())
@example(0)
@example(-1)
@example(2**31 - 1)
def test_with_explicit_examples(x):
    assert process(x) is not None

# Skip invalid inputs
@given(st.floats(allow_nan=False, allow_infinity=False),
       st.floats(allow_nan=False, allow_infinity=False))
def test_safe_divide(a, b):
    assume(b != 0)
    result = a / b
    assert isinstance(result, float)
```

## Essential Strategies

```python
import hypothesis.strategies as st

# Primitives
st.integers()                          # Any integer
st.integers(min_value=0, max_value=100)  # Bounded
st.floats(allow_nan=False)             # Floats without NaN
st.booleans()                          # True/False
st.text()                              # Unicode strings
st.text(min_size=1, max_size=50)       # Bounded strings
st.binary()                            # Bytes

# Collections
st.lists(st.integers())                # List of ints
st.lists(st.text(), min_size=1)        # Non-empty list
st.dictionaries(st.text(), st.integers())  # Dict
st.tuples(st.integers(), st.text())    # Fixed tuple

# Special types
st.emails()                            # Valid emails
st.uuids()                             # UUID objects
st.datetimes()                         # datetime objects

# Choices
st.sampled_from(["a", "b", "c"])       # Pick from list
st.one_of(st.integers(), st.text())    # Union type
st.none() | st.integers()              # Optional int
```

### Custom Composite Strategies

```python
from hypothesis.strategies import composite

@composite
def users(draw):
    return {
        "id": draw(st.integers(min_value=1)),
        "name": draw(st.text(min_size=1, max_size=50)),
        "email": draw(st.emails()),
        "active": draw(st.booleans())
    }

@given(users())
def test_user_validation(user):
    assert user["id"] > 0
    assert "@" in user["email"]
```

### From Type Annotations

```python
from hypothesis import given
from hypothesis.strategies import from_type
from dataclasses import dataclass

@dataclass
class Config:
    name: str
    port: int
    debug: bool

@given(from_type(Config))
def test_config(config: Config):
    assert isinstance(config.name, str)
    assert isinstance(config.port, int)
```

## Common Property Patterns

```python
# 1. Round-trip (encode/decode)
@given(st.text())
def test_json_roundtrip(data):
    assert json.loads(json.dumps(data)) == data

# 2. Idempotency (applying twice = applying once)
@given(st.lists(st.integers()))
def test_sort_idempotent(items):
    assert sorted(sorted(items)) == sorted(items)

# 3. Invariant preservation
@given(st.lists(st.integers()))
def test_sort_preserves_length(items):
    assert len(sorted(items)) == len(items)

# 4. Oracle (compare implementations)
@given(st.integers(min_value=0, max_value=20))
def test_fibonacci(n):
    assert fast_fib(n) == slow_fib(n)
```

## CI Integration

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

## Agentic Optimizations

| Context | Command |
|---------|---------|
| Quick check | `pytest -x --hypothesis-seed=0 -q` |
| Fail fast | `pytest --hypothesis-profile=dev -x --tb=short` |
| CI mode | `pytest --hypothesis-profile=ci --hypothesis-show-statistics` |
| Reproducible | `pytest --hypothesis-seed=42` |
| Debug failing | `pytest -x -s --hypothesis-verbosity=debug` |
| No shrinking | Add `phases=[Phase.generate]` to `@settings` |

## Quick Reference

```python
# Core decorators
@given(strategy)              # Generate test inputs
@example(value)               # Add explicit test case
@settings(max_examples=500)   # Configure behavior

# Key settings
assume(condition)             # Skip invalid inputs
note(message)                 # Add debug info to failure
target(value)                 # Guide generation toward value
```

For advanced patterns (stateful testing, recursive data, settings), best practices, and debugging guides, see [REFERENCE.md](REFERENCE.md).
