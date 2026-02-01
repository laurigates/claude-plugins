---
model: haiku
created: 2025-12-16
modified: 2026-01-24
reviewed: 2026-01-24
name: pytest-advanced
description: |
  Advanced pytest patterns including fixtures, markers, parametrization, and parallel execution.
  Use when implementing test infrastructure, organizing test suites, writing fixtures,
  or running tests with coverage. Covers pytest-cov, pytest-asyncio, pytest-xdist, pytest-mock.
allowed-tools: Bash(pytest *), Bash(python *), Bash(uv run *), Read, Grep, Glob
---

# Advanced Pytest Patterns

Advanced pytest features for robust, maintainable test suites.

## When to Use This Skill

| Use this skill when... | Use python-testing instead when... |
|------------------------|-------------------------------------|
| Writing fixtures with scopes/factories | Basic test structure questions |
| Parametrizing with complex data | Simple assert patterns |
| Setting up pytest plugins (cov, xdist) | Running existing tests |
| Organizing conftest.py hierarchy | Test discovery basics |
| Async testing with pytest-asyncio | Synchronous unit tests |

## Installation

```bash
# Core + common plugins
uv add --dev pytest pytest-cov pytest-asyncio pytest-xdist pytest-mock
```

## Configuration (pyproject.toml)

```toml
[tool.pytest.ini_options]
testpaths = ["tests"]
addopts = [
    "-v",
    "--strict-markers",
    "--tb=short",
    "-ra",
    "--cov=src",
    "--cov-report=term-missing",
    "--cov-fail-under=80",
]
markers = [
    "slow: marks tests as slow (deselect with '-m \"not slow\"')",
    "integration: marks tests as integration tests",
]
asyncio_mode = "auto"

[tool.coverage.run]
branch = true
source = ["src"]

[tool.coverage.report]
exclude_lines = ["pragma: no cover", "if TYPE_CHECKING:", "@abstractmethod"]
```

## Fixtures

### Scopes and Lifecycle

```python
import pytest
from typing import Generator

# function (default) - fresh per test
@pytest.fixture
def db() -> Generator[Database, None, None]:
    database = Database(":memory:")
    database.create_tables()
    yield database
    database.close()

# session - shared across all tests
@pytest.fixture(scope="session")
def app():
    return create_app("testing")

# autouse - applies automatically
@pytest.fixture(autouse=True)
def reset_state():
    clear_cache()
    yield
```

| Scope | Lifetime |
|-------|----------|
| `function` | Each test (default) |
| `class` | Each test class |
| `module` | Each test file |
| `session` | Entire test run |

### Parametrized Fixtures

```python
@pytest.fixture(params=["sqlite", "postgres", "mysql"])
def database_backend(request) -> str:
    return request.param  # Test runs 3 times

# Indirect parametrization
@pytest.fixture
def user(request) -> User:
    return User(**request.param)

@pytest.mark.parametrize("user", [
    {"name": "Alice", "age": 30},
    {"name": "Bob", "age": 25},
], indirect=True)
def test_user_validation(user: User):
    assert user.name
```

### Factory Pattern

```python
@pytest.fixture
def user_factory() -> Callable[[str], User]:
    created: list[User] = []
    def _create(name: str, **kwargs) -> User:
        user = User(name=name, **kwargs)
        created.append(user)
        return user
    yield _create
    for u in created:
        u.delete()
```

## Markers

```python
# Built-in markers
@pytest.mark.skip(reason="Not implemented")
@pytest.mark.skipif(sys.version_info < (3, 12), reason="Requires 3.12+")
@pytest.mark.xfail(reason="Known bug #123")
@pytest.mark.timeout(10)

# Parametrize
@pytest.mark.parametrize("input,expected", [
    pytest.param(2, 4, id="two"),
    pytest.param(3, 9, id="three"),
    pytest.param(-2, 4, id="negative"),
])
def test_square(input: int, expected: int):
    assert input ** 2 == expected
```

```bash
# Run by marker
pytest -m unit                    # Only unit tests
pytest -m "not slow"              # Skip slow tests
pytest -m "integration and not slow"  # Combine markers
```

## Key Plugins

| Plugin | Purpose | Key Command |
|--------|---------|-------------|
| pytest-cov | Coverage | `pytest --cov=src --cov-report=term-missing` |
| pytest-xdist | Parallel | `pytest -n auto` |
| pytest-asyncio | Async tests | `asyncio_mode = "auto"` in config |
| pytest-mock | Mocking | `mocker` fixture |
| pytest-timeout | Timeouts | `@pytest.mark.timeout(10)` |

### Async Testing (pytest-asyncio)

```python
@pytest.mark.asyncio
async def test_async_function():
    result = await fetch_data()
    assert result is not None

@pytest.fixture
async def async_client() -> AsyncGenerator[AsyncClient, None]:
    async with AsyncClient() as client:
        yield client
```

### Mocking (pytest-mock)

```python
def test_with_mock(mocker):
    mock_api = mocker.patch("myapp.external.api_call")
    mock_api.return_value = {"data": "test"}
    result = my_function()
    assert result["data"] == "test"
    mock_api.assert_called_once()
```

## Running Tests

```bash
# Execution
pytest                           # All tests
pytest tests/test_models.py::test_user  # Specific test
pytest -k "user and not slow"    # Pattern matching

# Parallel
pytest -n auto                   # All CPUs
pytest -n 4                      # 4 workers

# Coverage
pytest --cov=src --cov-report=html --cov-report=term-missing

# Failed tests
pytest --lf                      # Last failed only
pytest --ff                      # Failed first
pytest -x                        # Stop on first failure
pytest --maxfail=3               # Stop after 3

# Debugging
pytest -x --pdb                  # Debug on failure
pytest -s                        # Show print output
pytest --collect-only            # Dry run
```

## CI Integration

```yaml
# .github/workflows/test.yml
- name: Run tests
  run: |
    uv run pytest \
      --cov=src \
      --cov-report=xml \
      --cov-report=term-missing \
      --junitxml=test-results.xml
```

## Agentic Optimizations

| Context | Command |
|---------|---------|
| Quick check | `pytest -x --tb=short -q` |
| Fail fast | `pytest -x --maxfail=1 --tb=short` |
| Parallel fast | `pytest -n auto -x --tb=short -q` |
| Specific test | `pytest tests/test_foo.py::test_bar -v` |
| By marker | `pytest -m "not slow" -x --tb=short` |
| Coverage check | `pytest --cov=src --cov-fail-under=80 -q` |
| CI mode | `pytest --junitxml=results.xml --cov-report=xml -q` |
| Last failed | `pytest --lf --tb=short` |
| Debug | `pytest -x --pdb -s` |

For detailed patterns on conftest.py hierarchy, async testing, test organization, and common patterns, see [REFERENCE.md](REFERENCE.md).
