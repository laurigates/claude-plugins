---
name: python-testing
description: |
  Python testing with pytest, coverage, fixtures, parametrization, and mocking.
  Covers test organization, conftest.py, markers, async testing, and TDD workflows.
  Use when user mentions pytest, unit tests, test coverage, fixtures, mocking,
  or writing Python tests.
---

# Python Testing

Quick reference for Python testing with pytest, coverage, fixtures, and best practices.

## When This Skill Applies

- Writing unit tests and integration tests
- Test-driven development (TDD)
- Test fixtures and parametrization
- Coverage analysis
- Mocking and patching
- Async testing

## Quick Reference

### Running Tests

```bash
# Basic test run
uv run pytest

# Verbose output
uv run pytest -v

# Show print statements
uv run pytest -s

# Stop at first failure
uv run pytest -x

# Run specific test
uv run pytest tests/test_module.py::test_function

# Run by keyword
uv run pytest -k "test_user"
```

### Test Coverage

```bash
# Run with coverage
uv run pytest --cov

# HTML report
uv run pytest --cov --cov-report=html

# Show missing lines
uv run pytest --cov --cov-report=term-missing

# Coverage for specific module
uv run pytest --cov=mymodule tests/
```

### Fixtures

```python
import pytest

@pytest.fixture
def sample_data():
    return {"key": "value"}

@pytest.fixture(scope="module")
def db_connection():
    conn = create_connection()
    yield conn
    conn.close()

def test_with_fixture(sample_data):
    assert sample_data["key"] == "value"
```

### Parametrize Tests

```python
import pytest

@pytest.mark.parametrize("input,expected", [
    ("hello", "HELLO"),
    ("world", "WORLD"),
    ("test", "TEST"),
])
def test_uppercase(input: str, expected: str):
    assert input.upper() == expected

@pytest.mark.parametrize("value,is_valid", [
    (1, True),
    (0, False),
    (-1, False),
])
def test_validation(value, is_valid):
    assert validate(value) == is_valid
```

### Markers

```python
import pytest

@pytest.mark.slow
def test_slow_operation():
    # Long-running test
    pass

@pytest.mark.skip(reason="Not implemented yet")
def test_future_feature():
    pass

@pytest.mark.skipif(sys.platform == "win32", reason="Unix only")
def test_unix_specific():
    pass

@pytest.mark.xfail
def test_known_issue():
    # Expected to fail
    pass
```

```bash
# Run only marked tests
uv run pytest -m slow
uv run pytest -m "not slow"
```

### Async Testing

```python
import pytest

@pytest.mark.asyncio
async def test_async_function():
    result = await async_operation()
    assert result == expected_value

@pytest.fixture
async def async_client():
    client = AsyncClient()
    await client.connect()
    yield client
    await client.disconnect()
```

### Mocking

```python
from unittest.mock import Mock, patch, MagicMock

def test_with_mock():
    mock_obj = Mock()
    mock_obj.method.return_value = "mocked"
    assert mock_obj.method() == "mocked"

@patch('module.external_api')
def test_with_patch(mock_api):
    mock_api.return_value = {"status": "success"}
    result = call_external_api()
    assert result["status"] == "success"

# pytest-mock (cleaner)
def test_with_mocker(mocker):
    mock = mocker.patch('module.function')
    mock.return_value = 42
    assert function() == 42
```

## Test Organization

```
project/
├── src/
│   └── myproject/
│       ├── __init__.py
│       └── module.py
└── tests/
    ├── __init__.py
    ├── conftest.py          # Shared fixtures
    ├── test_module.py
    └── integration/
        └── test_api.py
```

## conftest.py

```python
# tests/conftest.py
import pytest

@pytest.fixture(scope="session")
def app_config():
    return {"debug": True, "testing": True}

@pytest.fixture(autouse=True)
def reset_db():
    setup_database()
    yield
    teardown_database()
```

## pyproject.toml Configuration

```toml
[tool.pytest.ini_options]
testpaths = ["tests"]
python_files = ["test_*.py", "*_test.py"]
python_classes = ["Test*"]
python_functions = ["test_*"]
addopts = [
    "-v",
    "--strict-markers",
    "--cov=src",
    "--cov-report=term-missing",
]
markers = [
    "slow: marks tests as slow",
    "integration: marks tests as integration tests",
]

[tool.coverage.run]
source = ["src"]
omit = ["*/tests/*", "*/test_*.py"]

[tool.coverage.report]
exclude_lines = [
    "pragma: no cover",
    "def __repr__",
    "raise AssertionError",
    "raise NotImplementedError",
    "if __name__ == .__main__.:",
]
```

## Common Testing Patterns

### Test Exceptions

```python
import pytest

def test_raises_exception():
    with pytest.raises(ValueError):
        function_that_raises()

def test_raises_with_message():
    with pytest.raises(ValueError, match="Invalid input"):
        function_that_raises()
```

### Test Warnings

```python
import pytest

def test_deprecation_warning():
    with pytest.warns(DeprecationWarning):
        deprecated_function()
```

### Temporary Files

```python
def test_with_tmp_path(tmp_path):
    file_path = tmp_path / "test.txt"
    file_path.write_text("content")
    assert file_path.read_text() == "content"
```

## TDD Workflow

```bash
# 1. RED: Write failing test
uv run pytest tests/test_new_feature.py
# FAILED

# 2. GREEN: Implement minimal code
uv run pytest tests/test_new_feature.py
# PASSED

# 3. REFACTOR: Improve code
uv run pytest  # All tests pass
```

## See Also

- `uv-project-management` - Adding pytest to projects
- `python-code-quality` - Combining tests with linting
- `python-development` - Core Python development patterns

## References

- Official docs: https://docs.pytest.org/
- Detailed guide: See REFERENCE.md in this skill directory
