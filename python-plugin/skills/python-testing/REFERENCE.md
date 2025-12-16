# Python Testing - Comprehensive Reference

Complete guide to Python testing with pytest.

## Table of Contents

1. [Test Discovery](#test-discovery)
2. [Fixtures](#fixtures)
3. [Parametrization](#parametrization)
4. [Markers](#markers)
5. [Coverage](#coverage)
6. [Mocking](#mocking)
7. [Async Testing](#async-testing)
8. [Best Practices](#best-practices)

---

## Test Discovery

pytest automatically discovers tests following these conventions:

**File names:** `test_*.py` or `*_test.py`
**Function names:** `test_*`
**Class names:** `Test*`
**Methods:** `test_*`

---

## Fixtures

Fixtures provide reusable setup/teardown code:

```python
import pytest

@pytest.fixture
def client():
    return TestClient()

@pytest.fixture(scope="module")
def db():
    db = setup_db()
    yield db
    teardown_db()

@pytest.fixture(autouse=True)
def reset_state():
    # Runs before each test
    clear_state()
```

**Scopes:** function (default), class, module, package, session

---

## Parametrization

Run the same test with different inputs:

```python
@pytest.mark.parametrize("input,expected", [
    (1, 2),
    (2, 4),
    (3, 6),
])
def test_double(input, expected):
    assert double(input) == expected
```

---

## Markers

Custom test markers for organization:

```python
@pytest.mark.slow
@pytest.mark.integration
def test_complex_operation():
    pass
```

Run: `pytest -m slow`

---

## Coverage

```bash
pytest --cov=src --cov-report=html
pytest --cov --cov-report=term-missing
```

---

## Mocking

```python
from unittest.mock import patch

@patch('module.api_call')
def test_mocked(mock_api):
    mock_api.return_value = {"data": "test"}
    assert fetch_data() == {"data": "test"}
```

---

## Async Testing

```python
@pytest.mark.asyncio
async def test_async():
    result = await async_function()
    assert result is not None
```

---

## Best Practices

1. One assertion per test
2. Use descriptive test names
3. Organize tests in classes
4. Use fixtures for setup
5. Mock external dependencies
6. Aim for 80%+ coverage

---

## References

- **pytest docs**: https://docs.pytest.org/
- **pytest-cov**: https://pytest-cov.readthedocs.io/
- **pytest-asyncio**: https://pytest-asyncio.readthedocs.io/
