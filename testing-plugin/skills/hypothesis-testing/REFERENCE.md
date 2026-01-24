# Hypothesis Advanced Reference

Detailed patterns for stateful testing, recursive strategies, advanced settings, and debugging.

## Advanced Strategies

### Recursive Data

```python
from hypothesis import given
import hypothesis.strategies as st

# Recursive JSON-like structure
json_values = st.recursive(
    base=st.one_of(
        st.none(),
        st.booleans(),
        st.integers(),
        st.floats(allow_nan=False),
        st.text()
    ),
    extend=lambda children: st.one_of(
        st.lists(children),
        st.dictionaries(st.text(), children)
    ),
    max_leaves=50
)

@given(json_values)
def test_json_serialization(value):
    assert json.loads(json.dumps(value)) == value
```

### Filtered Strategies

```python
# Filter out unwanted values
positive_ints = st.integers().filter(lambda x: x > 0)
non_empty_text = st.text().filter(lambda s: len(s.strip()) > 0)
even_numbers = st.integers().filter(lambda x: x % 2 == 0)

# map: Transform generated values
upper_text = st.text().map(str.upper)
abs_ints = st.integers().map(abs)

# flatmap: Generate strategy based on previous value
def list_and_index(draw):
    items = draw(st.lists(st.integers(), min_size=1))
    index = draw(st.integers(min_value=0, max_value=len(items) - 1))
    return items, index
```

### Strategy Composition

```python
# Union types
st.one_of(st.integers(), st.text(), st.none())

# Optional values
st.none() | st.integers()  # Same as one_of(none(), integers())

# Fixed dictionaries with different strategies per key
st.fixed_dictionaries({
    "name": st.text(min_size=1),
    "age": st.integers(min_value=0, max_value=120),
    "scores": st.lists(st.floats(min_value=0, max_value=100))
})

# Builds: construct objects from strategies
st.builds(
    User,
    name=st.text(min_size=1),
    email=st.emails(),
    age=st.integers(min_value=18, max_value=120)
)
```

### Data Strategies for Complex Types

```python
# From type annotations (automatic)
from hypothesis.strategies import from_type

@given(from_type(list[int]))
def test_list(items):
    assert all(isinstance(x, int) for x in items)

# Register custom strategies for types
from hypothesis.strategies import register_type_strategy

register_type_strategy(MyCustomType, st.builds(
    MyCustomType,
    value=st.integers()
))

# From regex patterns
st.from_regex(r"[a-z]+@[a-z]+\.[a-z]{2,3}", fullmatch=True)
```

## Stateful Testing

### Rule-Based State Machines

```python
from hypothesis.stateful import RuleBasedStateMachine, rule, precondition, invariant
import hypothesis.strategies as st

class DatabaseStateMachine(RuleBasedStateMachine):
    """Test database operations as a state machine."""

    def __init__(self):
        super().__init__()
        self.db = Database()
        self.model = {}  # Simple dict as oracle

    @rule(key=st.text(min_size=1), value=st.integers())
    def put(self, key, value):
        """Insert a key-value pair."""
        self.db.put(key, value)
        self.model[key] = value

    @precondition(lambda self: len(self.model) > 0)
    @rule(key=st.sampled_from(lambda self: list(self.model.keys())))
    def get(self, key):
        """Retrieve a value by key."""
        assert self.db.get(key) == self.model[key]

    @precondition(lambda self: len(self.model) > 0)
    @rule(key=st.sampled_from(lambda self: list(self.model.keys())))
    def delete(self, key):
        """Delete a key."""
        self.db.delete(key)
        del self.model[key]

    @invariant()
    def size_matches(self):
        """Database size matches model."""
        assert self.db.size() == len(self.model)

# Run the state machine
TestDatabase = DatabaseStateMachine.TestCase
```

### Bundle-Based State Machines

```python
from hypothesis.stateful import Bundle, RuleBasedStateMachine, rule

class FileSystemMachine(RuleBasedStateMachine):
    files = Bundle("files")
    directories = Bundle("directories")

    @rule(target=directories, name=st.text(min_size=1, max_size=10))
    def create_directory(self, name):
        self.fs.mkdir(name)
        return name

    @rule(target=files, directory=directories, name=st.text(min_size=1))
    def create_file(self, directory, name):
        path = f"{directory}/{name}"
        self.fs.touch(path)
        return path

    @rule(path=files)
    def read_file(self, path):
        assert self.fs.exists(path)
```

## Advanced Settings

```python
from hypothesis import given, settings, HealthCheck, Phase, Verbosity

@settings(
    max_examples=1000,           # More thorough
    deadline=5000,               # 5 second deadline per example
    suppress_health_check=[
        HealthCheck.too_slow,    # Allow slow tests
        HealthCheck.data_too_large,  # Allow large data
        HealthCheck.filter_too_much, # Allow high filter rate
    ],
    phases=[
        Phase.explicit,          # Run @example cases
        Phase.reuse,             # Replay from database
        Phase.generate,          # Generate new examples
        Phase.shrink,            # Minimize failures
    ],
    verbosity=Verbosity.verbose, # Show all examples
    derandomize=True,            # Deterministic (for CI)
    database=None,               # Disable example database
)
@given(st.integers())
def test_with_custom_settings(x):
    assert process(x) is not None
```

### Profile Management

```python
# conftest.py
from hypothesis import settings, Verbosity

settings.register_profile("dev", max_examples=50, deadline=1000)
settings.register_profile("ci", max_examples=500, deadline=5000,
                          verbosity=Verbosity.verbose)
settings.register_profile("debug", max_examples=10, deadline=None,
                          verbosity=Verbosity.debug)

# Load from environment
import os
settings.load_profile(os.getenv("HYPOTHESIS_PROFILE", "dev"))
```

## Best Practices

### 1. Start Simple, Add Complexity

```python
# Start with basic property
@given(st.integers())
def test_increment(x):
    assert x + 1 > x  # Fails for max int!

# Fix with bounded input or assume
@given(st.integers(max_value=2**63 - 2))
def test_increment_bounded(x):
    assert x + 1 > x
```

### 2. Test Properties, Not Implementations

```python
# Good: test a property
@given(st.lists(st.integers()))
def test_reverse_involution(items):
    assert list(reversed(list(reversed(items)))) == items

# Bad: testing implementation details
@given(st.lists(st.integers()))
def test_reverse_implementation(items):
    for i, item in enumerate(reversed(items)):
        assert item == items[len(items) - 1 - i]
```

### 3. Use assume() Sparingly

```python
# Prefer constrained strategies
@given(st.integers(min_value=1))      # Better
def test_positive(x):
    assert x > 0

# Over filtering with assume
@given(st.integers())                  # Worse
def test_positive_assume(x):
    assume(x > 0)
    assert x > 0
```

### 4. Combine with Example-Based

```python
@given(st.lists(st.integers()))
@example([])           # Empty list
@example([42])         # Single element
@example([1, 1, 1])   # All same
def test_comprehensive(items):
    result = process(items)
    assert len(result) == len(items)
```

### 5. Use target() for Coverage

```python
@given(st.lists(st.integers(), min_size=1))
def test_with_targeting(items):
    result = complex_sort(items)
    # Guide hypothesis toward larger lists
    target(float(len(items)))
    assert is_sorted(result)
```

## Debugging Failing Tests

### Verbose Mode

```python
@given(st.lists(st.integers()))
@settings(
    verbosity=Verbosity.debug,
    max_examples=10,
    phases=[Phase.generate],  # Skip shrinking
    print_blob=True           # Print input data
)
def test_debug(items):
    result = buggy_function(items)
    assert result is not None
```

### Reproduce Specific Failure

```python
# Use @example with the failing case from output
@given(st.lists(st.integers()))
@example([1, 2, -2147483648])  # Specific failing case
def test_reproduce_failure(items):
    result = process(items)
    assert result is not None
```

### Using note() for Debug Info

```python
@given(st.dictionaries(st.text(), st.integers()))
def test_with_notes(data):
    note(f"Input size: {len(data)}")
    note(f"Keys: {list(data.keys())[:5]}")
    result = transform(data)
    note(f"Output: {result}")
    assert validate(result)
```

### Hypothesis Database

```bash
# Failing examples stored in .hypothesis/examples/
# Delete to reset:
rm -rf .hypothesis/

# Or disable database in settings:
@settings(database=None)
```

## Common Patterns

### Testing Collections

```python
@given(st.lists(st.integers()))
def test_list_properties(items):
    # Sorting preserves elements
    sorted_items = sorted(items)
    assert sorted(sorted_items) == sorted_items  # Idempotent
    assert len(sorted_items) == len(items)  # Preserves length
    assert set(sorted_items) == set(items)  # Preserves elements
```

### Testing String Operations

```python
@given(st.text(), st.text())
def test_string_operations(s1, s2):
    # Concatenation
    assert (s1 + s2).startswith(s1)
    assert (s1 + s2).endswith(s2)
    assert len(s1 + s2) == len(s1) + len(s2)

    # Strip
    assert s1.strip() == s1.strip().strip()  # Idempotent
```

### Testing Numeric Operations

```python
@given(st.floats(allow_nan=False, allow_infinity=False, min_value=-1e10, max_value=1e10))
def test_numeric_stability(x):
    # Round-trip through string
    assert float(str(x)) == pytest.approx(x)
```

### Testing Data Structures

```python
@composite
def sorted_lists(draw):
    """Generate pre-sorted lists."""
    items = draw(st.lists(st.integers()))
    return sorted(items)

@given(sorted_lists(), st.integers())
def test_binary_search(items, target):
    idx = binary_search(items, target)
    if idx >= 0:
        assert items[idx] == target
    else:
        assert target not in items
```
