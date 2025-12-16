---
name: pytest-advanced
description: |
  Advanced pytest patterns including fixtures, markers, plugins, and async testing.
  Use when implementing test infrastructure, organizing test suites, using pytest plugins,
  or setting up complex test scenarios with fixtures and parametrization.
  Triggered by: pytest, fixtures, parametrize, conftest, test organization, async testing.
---

# Advanced Pytest Patterns

Comprehensive guide to advanced pytest features for robust, maintainable test suites.

## Installation

```bash
# Install pytest with common plugins
uv add --dev pytest pytest-cov pytest-asyncio pytest-xdist pytest-mock

# Core plugins explained:
# pytest-cov: Code coverage reporting
# pytest-asyncio: Async/await test support
# pytest-xdist: Parallel test execution
# pytest-mock: Enhanced mocking with fixtures
```

## Configuration

### pyproject.toml Configuration

```toml
[tool.pytest.ini_options]
# Test discovery
testpaths = ["tests"]
python_files = ["test_*.py", "*_test.py"]
python_classes = ["Test*"]
python_functions = ["test_*"]

# Output and reporting
addopts = [
    "-v",                      # Verbose output
    "--strict-markers",        # Enforce marker registration
    "--strict-config",         # Enforce valid configuration
    "--tb=short",              # Shorter traceback format
    "--disable-warnings",      # Hide warnings (or use -W for control)
    "-ra",                     # Show summary of all test outcomes
    "--cov=src",              # Coverage for src directory
    "--cov-report=html",       # HTML coverage report
    "--cov-report=term-missing", # Terminal report with missing lines
    "--cov-fail-under=80",     # Fail if coverage below 80%
]

# Markers (custom test markers)
markers = [
    "slow: marks tests as slow (deselect with '-m \"not slow\"')",
    "integration: marks tests as integration tests",
    "unit: marks tests as unit tests",
    "smoke: marks tests as smoke tests for CI",
    "requires_network: marks tests that need network access",
    "requires_auth: marks tests that need authentication",
]

# Asyncio configuration
asyncio_mode = "auto"  # Automatically detect async tests

# Timeouts (requires pytest-timeout)
timeout = 300  # Default timeout: 5 minutes
timeout_method = "thread"

# Warnings
filterwarnings = [
    "error",                    # Treat warnings as errors
    "ignore::DeprecationWarning",  # Except deprecation warnings
    "ignore::PendingDeprecationWarning",
]

# Coverage configuration
[tool.coverage.run]
branch = true
source = ["src"]
omit = [
    "*/tests/*",
    "*/test_*.py",
    "*/__pycache__/*",
    "*/site-packages/*",
]

[tool.coverage.report]
exclude_lines = [
    "pragma: no cover",
    "def __repr__",
    "raise AssertionError",
    "raise NotImplementedError",
    "if __name__ == .__main__.:",
    "if TYPE_CHECKING:",
    "@abstractmethod",
]
precision = 2
show_missing = true

[tool.coverage.html]
directory = "htmlcov"
```

## Fixtures

### Basic Fixtures

```python
# tests/conftest.py
import pytest
from typing import Generator
from myapp.database import Database
from myapp.models import User

@pytest.fixture
def db() -> Generator[Database, None, None]:
    """Provide a database connection for tests."""
    database = Database(":memory:")  # In-memory SQLite
    database.create_tables()
    yield database
    database.close()

@pytest.fixture
def sample_user() -> User:
    """Provide a sample user for tests."""
    return User(id=1, name="Test User", email="test@example.com")

@pytest.fixture
def authenticated_client(client, sample_user):
    """Provide an authenticated HTTP client."""
    client.login(sample_user)
    return client

# Usage in tests
def test_user_creation(db: Database, sample_user: User):
    db.save(sample_user)
    assert db.get_user(sample_user.id) == sample_user
```

### Fixture Scopes

```python
import pytest
from typing import Generator

# Scope: function (default) - runs for each test
@pytest.fixture(scope="function")
def fresh_data() -> dict[str, str]:
    """New data for each test."""
    return {"key": "value"}

# Scope: class - runs once per test class
@pytest.fixture(scope="class")
def shared_resource() -> str:
    """Shared across all tests in a class."""
    return "shared_value"

# Scope: module - runs once per test module
@pytest.fixture(scope="module")
def module_db() -> Generator[Database, None, None]:
    """Database shared across module."""
    db = Database("test.db")
    yield db
    db.cleanup()

# Scope: session - runs once per test session
@pytest.fixture(scope="session")
def global_config() -> dict[str, str]:
    """Configuration shared across all tests."""
    return load_config("test_config.yaml")

# Scope comparison
# function: Each test gets fresh fixture
# class: Tests in same class share fixture
# module: Tests in same file share fixture
# session: All tests share fixture
```

### Autouse Fixtures

```python
import pytest
from unittest.mock import patch

# Automatically applied to all tests
@pytest.fixture(autouse=True)
def reset_state():
    """Reset global state before each test."""
    clear_cache()
    reset_config()
    yield
    # Cleanup after test

# Module-level autouse
@pytest.fixture(scope="module", autouse=True)
def setup_test_environment():
    """Set up environment for entire module."""
    os.environ["ENV"] = "test"
    yield
    del os.environ["ENV"]

# Mock external services automatically
@pytest.fixture(autouse=True)
def mock_external_api():
    """Mock external API for all tests."""
    with patch("myapp.external.api_call") as mock:
        mock.return_value = {"status": "ok"}
        yield mock
```

### Parametrized Fixtures

```python
import pytest

# Parametrized fixture
@pytest.fixture(params=["sqlite", "postgres", "mysql"])
def database_backend(request) -> str:
    """Test with multiple database backends."""
    return request.param

def test_query_execution(database_backend: str):
    """This test runs 3 times, once per backend."""
    db = Database(backend=database_backend)
    result = db.query("SELECT 1")
    assert result == 1

# Complex parametrization
@pytest.fixture(params=[
    pytest.param("fast", marks=pytest.mark.unit),
    pytest.param("slow", marks=pytest.mark.slow),
])
def execution_mode(request) -> str:
    return request.param

# Indirect parametrization
@pytest.fixture
def user(request) -> User:
    """Create user with parametrized attributes."""
    return User(**request.param)

@pytest.mark.parametrize("user", [
    {"name": "Alice", "age": 30},
    {"name": "Bob", "age": 25},
], indirect=True)
def test_user_validation(user: User):
    assert user.name in ["Alice", "Bob"]
```

### Factory Fixtures

```python
import pytest
from typing import Callable

@pytest.fixture
def user_factory() -> Callable[[str], User]:
    """Factory to create users on demand."""
    created_users: list[User] = []

    def _create_user(name: str, **kwargs) -> User:
        user = User(name=name, **kwargs)
        created_users.append(user)
        return user

    yield _create_user

    # Cleanup all created users
    for user in created_users:
        user.delete()

def test_multiple_users(user_factory):
    """Create multiple users in one test."""
    alice = user_factory("Alice", age=30)
    bob = user_factory("Bob", age=25)
    assert alice.name != bob.name
```

## Markers

### Built-in Markers

```python
import pytest

# Skip test unconditionally
@pytest.mark.skip(reason="Feature not implemented yet")
def test_future_feature():
    pass

# Skip test conditionally
@pytest.mark.skipif(sys.version_info < (3, 12), reason="Requires Python 3.12+")
def test_new_syntax():
    match value:
        case pattern:
            pass

# Expected failure (test runs but failure is acceptable)
@pytest.mark.xfail(reason="Known bug #123")
def test_buggy_feature():
    assert broken_function() == expected

# Expected failure with strict mode
@pytest.mark.xfail(strict=True, reason="Must fail or test fails")
def test_must_fail():
    assert False  # If this passes, test fails

# Parametrize test with multiple inputs
@pytest.mark.parametrize("input,expected", [
    (2, 4),
    (3, 9),
    (4, 16),
])
def test_square(input: int, expected: int):
    assert input ** 2 == expected

# Parametrize with ids for readable output
@pytest.mark.parametrize("value,expected", [
    pytest.param(0, False, id="zero"),
    pytest.param(1, True, id="one"),
    pytest.param(-1, True, id="negative"),
])
def test_truthiness(value: int, expected: bool):
    assert bool(value) == expected
```

### Custom Markers

```python
# tests/conftest.py
import pytest

def pytest_configure(config):
    """Register custom markers."""
    config.addinivalue_line(
        "markers", "slow: marks tests as slow (deselect with '-m \"not slow\"')"
    )
    config.addinivalue_line(
        "markers", "integration: marks tests as integration tests"
    )
    config.addinivalue_line(
        "markers", "requires_network: marks tests that need network access"
    )

# Usage in tests
@pytest.mark.slow
def test_large_computation():
    """This test takes a long time."""
    result = compute_for_hours()
    assert result is not None

@pytest.mark.integration
def test_database_integration(db):
    """Test database integration."""
    db.save_data({"key": "value"})
    assert db.load_data()["key"] == "value"

@pytest.mark.requires_network
def test_api_call():
    """Test external API call."""
    response = requests.get("https://api.example.com")
    assert response.status_code == 200

# Combine multiple markers
@pytest.mark.slow
@pytest.mark.integration
@pytest.mark.requires_network
def test_full_integration():
    """Slow integration test requiring network."""
    pass
```

### Running Tests by Marker

```bash
# Run only unit tests
pytest -m unit

# Run all except slow tests
pytest -m "not slow"

# Run integration or slow tests
pytest -m "integration or slow"

# Run integration but not slow tests
pytest -m "integration and not slow"

# Run specific markers with verbose output
pytest -v -m "unit and not requires_network"
```

## Plugins

### pytest-cov (Coverage)

```bash
# Install
uv add --dev pytest-cov

# Usage
pytest --cov=src --cov-report=html --cov-report=term-missing

# Configuration in pyproject.toml
[tool.pytest.ini_options]
addopts = ["--cov=src", "--cov-report=html", "--cov-fail-under=80"]

[tool.coverage.run]
branch = true
source = ["src"]

[tool.coverage.report]
exclude_lines = ["pragma: no cover", "if TYPE_CHECKING:"]
```

### pytest-asyncio (Async Testing)

```bash
# Install
uv add --dev pytest-asyncio

# Configuration
[tool.pytest.ini_options]
asyncio_mode = "auto"  # Automatically detect async tests
```

```python
import pytest

# Async test
@pytest.mark.asyncio
async def test_async_function():
    result = await async_operation()
    assert result == expected

# Async fixture
@pytest.fixture
async def async_client():
    client = await create_async_client()
    yield client
    await client.close()

@pytest.mark.asyncio
async def test_with_async_fixture(async_client):
    response = await async_client.get("/api/data")
    assert response.status == 200
```

### pytest-xdist (Parallel Execution)

```bash
# Install
uv add --dev pytest-xdist

# Run tests in parallel
pytest -n auto  # Use all available CPUs
pytest -n 4     # Use 4 workers

# Distribute tests across workers
pytest --dist loadfile  # Distribute by file
pytest --dist loadscope # Distribute by scope (module, class)
```

### pytest-mock (Enhanced Mocking)

```bash
# Install
uv add --dev pytest-mock

# Provides 'mocker' fixture
```

```python
def test_with_mock(mocker):
    """Use mocker fixture for easy mocking."""
    # Mock a function
    mock_api = mocker.patch("myapp.external.api_call")
    mock_api.return_value = {"data": "test"}

    # Mock a method
    mocker.patch.object(MyClass, "method", return_value=42)

    # Spy on a function (real function runs, but calls are recorded)
    spy = mocker.spy(myapp.utils, "helper_function")

    result = my_function()

    assert result == expected
    spy.assert_called_once_with("expected_arg")
```

### pytest-timeout

```bash
# Install
uv add --dev pytest-timeout

# Configuration
[tool.pytest.ini_options]
timeout = 300  # Default timeout: 5 minutes
timeout_method = "thread"
```

```python
# Per-test timeout
@pytest.mark.timeout(10)
def test_fast_function():
    """Must complete in 10 seconds."""
    pass

# Disable timeout for specific test
@pytest.mark.timeout(0)
def test_no_timeout():
    """Runs without timeout."""
    pass
```

### pytest-benchmark

```bash
# Install
uv add --dev pytest-benchmark

# Usage
def test_performance(benchmark):
    result = benchmark(function_to_test, arg1, arg2)
    assert result == expected

# Compare benchmarks
pytest --benchmark-compare=0001  # Compare to baseline
pytest --benchmark-save=baseline  # Save as baseline
```

## conftest.py Patterns

### Project Structure

```
tests/
├── conftest.py              # Root conftest (session-level fixtures)
├── unit/
│   ├── conftest.py          # Unit test fixtures
│   ├── test_models.py
│   └── test_utils.py
├── integration/
│   ├── conftest.py          # Integration test fixtures
│   ├── test_api.py
│   └── test_database.py
└── e2e/
    ├── conftest.py          # E2E test fixtures
    └── test_workflows.py
```

### Root conftest.py

```python
# tests/conftest.py
import pytest
from typing import Generator
from myapp import create_app
from myapp.database import Database

# Session-level fixtures
@pytest.fixture(scope="session")
def app():
    """Create application for testing."""
    app = create_app("testing")
    return app

@pytest.fixture(scope="session")
def db_engine():
    """Create database engine for testing."""
    engine = create_test_engine()
    yield engine
    engine.dispose()

# Hooks for pytest behavior customization
def pytest_configure(config):
    """Register custom markers."""
    config.addinivalue_line("markers", "slow: slow tests")
    config.addinivalue_line("markers", "integration: integration tests")

def pytest_collection_modifyitems(config, items):
    """Automatically mark tests based on path."""
    for item in items:
        if "integration" in item.nodeid:
            item.add_marker(pytest.mark.integration)
        if "slow" in item.nodeid:
            item.add_marker(pytest.mark.slow)

# Fixtures available to all tests
@pytest.fixture(autouse=True)
def reset_database(db_engine):
    """Reset database before each test."""
    clear_tables(db_engine)
    yield
    rollback_transaction(db_engine)
```

### Domain-Specific conftest.py

```python
# tests/integration/conftest.py
import pytest
from myapp.client import Client

@pytest.fixture
def authenticated_client(app) -> Client:
    """HTTP client with authentication."""
    client = app.test_client()
    client.login("test@example.com", "password")
    return client

@pytest.fixture
def sample_data(db):
    """Load sample data for integration tests."""
    db.load_fixtures("integration_data.json")
    yield
    db.clear_fixtures()

# tests/e2e/conftest.py
@pytest.fixture(scope="module")
def browser():
    """Selenium browser for E2E tests."""
    from selenium import webdriver
    driver = webdriver.Chrome()
    yield driver
    driver.quit()
```

## Async Testing Patterns

### Basic Async Tests

```python
import pytest
import asyncio

@pytest.mark.asyncio
async def test_async_function():
    """Simple async test."""
    result = await fetch_data()
    assert result is not None

@pytest.mark.asyncio
async def test_concurrent_operations():
    """Test concurrent async operations."""
    results = await asyncio.gather(
        fetch_user(1),
        fetch_user(2),
        fetch_user(3)
    )
    assert len(results) == 3
```

### Async Fixtures

```python
import pytest
from typing import AsyncGenerator

@pytest.fixture
async def async_client() -> AsyncGenerator[AsyncClient, None]:
    """Async HTTP client fixture."""
    async with AsyncClient() as client:
        yield client

@pytest.fixture(scope="module")
async def async_db() -> AsyncGenerator[AsyncDatabase, None]:
    """Async database connection."""
    db = AsyncDatabase("test.db")
    await db.connect()
    yield db
    await db.close()

@pytest.mark.asyncio
async def test_with_async_fixtures(async_client, async_db):
    """Use multiple async fixtures."""
    await async_db.save({"key": "value"})
    response = await async_client.get("/api/data")
    assert response.status_code == 200
```

### Event Loop Management

```python
import pytest
import asyncio

# Custom event loop for testing
@pytest.fixture(scope="session")
def event_loop():
    """Create event loop for entire test session."""
    policy = asyncio.get_event_loop_policy()
    loop = policy.new_event_loop()
    yield loop
    loop.close()

# Async fixture with explicit event loop
@pytest.fixture
async def async_resource(event_loop):
    """Resource requiring specific event loop."""
    resource = await create_resource()
    yield resource
    await resource.cleanup()
```

### Testing Async Context Managers

```python
@pytest.mark.asyncio
async def test_async_context_manager():
    """Test async context manager."""
    async with AsyncResource() as resource:
        result = await resource.process()
        assert result is not None

    # Verify cleanup happened
    assert resource.is_closed()
```

### Testing Async Generators

```python
@pytest.mark.asyncio
async def test_async_generator():
    """Test async generator."""
    results = []
    async for item in async_generator():
        results.append(item)

    assert len(results) == expected_count
    assert all(isinstance(item, ExpectedType) for item in results)
```

## Test Organization Best Practices

### 1. Test Structure (AAA Pattern)

```python
def test_user_creation():
    """Test user creation with valid data."""
    # Arrange: Set up test data
    user_data = {"name": "Alice", "email": "alice@example.com"}

    # Act: Perform the action
    user = create_user(user_data)

    # Assert: Verify the outcome
    assert user.name == "Alice"
    assert user.email == "alice@example.com"
    assert user.id is not None
```

### 2. Test Naming Conventions

```python
# Pattern: test_<function>_<scenario>_<expected_result>

def test_divide_by_zero_raises_error():
    """Division by zero raises ZeroDivisionError."""
    with pytest.raises(ZeroDivisionError):
        divide(10, 0)

def test_user_login_with_valid_credentials_succeeds():
    """User login succeeds with valid credentials."""
    result = login("user@example.com", "correct_password")
    assert result.success is True

def test_api_call_with_invalid_token_returns_401():
    """API call with invalid token returns 401 Unauthorized."""
    response = api_call(token="invalid")
    assert response.status_code == 401
```

### 3. Test Grouping with Classes

```python
class TestUserAuthentication:
    """Group related authentication tests."""

    def test_login_success(self, user):
        """Successful login."""
        assert login(user.email, user.password).success

    def test_login_wrong_password(self, user):
        """Login fails with wrong password."""
        assert not login(user.email, "wrong").success

    def test_logout(self, authenticated_user):
        """Logout clears session."""
        logout(authenticated_user)
        assert not is_authenticated(authenticated_user)

class TestUserRegistration:
    """Group registration tests."""

    def test_register_new_user(self):
        """Register new user successfully."""
        pass

    def test_register_duplicate_email(self, existing_user):
        """Registration fails with duplicate email."""
        pass
```

### 4. Parametrization for Data-Driven Tests

```python
@pytest.mark.parametrize("input,expected", [
    pytest.param(0, 0, id="zero"),
    pytest.param(1, 1, id="one"),
    pytest.param(2, 4, id="two"),
    pytest.param(3, 9, id="three"),
    pytest.param(-2, 4, id="negative"),
])
def test_square(input: int, expected: int):
    """Test square function with various inputs."""
    assert square(input) == expected

# Complex parametrization
@pytest.mark.parametrize("user_data,should_succeed", [
    ({"name": "Alice", "email": "alice@example.com"}, True),
    ({"name": "", "email": "alice@example.com"}, False),
    ({"name": "Bob", "email": "invalid"}, False),
    ({"name": "Charlie"}, False),  # Missing email
])
def test_user_validation(user_data: dict, should_succeed: bool):
    """Test user validation with various inputs."""
    if should_succeed:
        user = create_user(user_data)
        assert user is not None
    else:
        with pytest.raises(ValidationError):
            create_user(user_data)
```

### 5. Test Data Management

```python
# tests/fixtures/users.json
{
  "users": [
    {"id": 1, "name": "Alice", "email": "alice@example.com"},
    {"id": 2, "name": "Bob", "email": "bob@example.com"}
  ]
}

# tests/conftest.py
import json
import pytest

@pytest.fixture
def users_data():
    """Load user test data from JSON."""
    with open("tests/fixtures/users.json") as f:
        return json.load(f)["users"]

@pytest.fixture
def sample_users(db, users_data):
    """Create sample users in database."""
    users = [db.create_user(data) for data in users_data]
    yield users
    for user in users:
        db.delete_user(user.id)
```

## Common Patterns

### Testing Exceptions

```python
import pytest

# Assert exception is raised
def test_divide_by_zero():
    with pytest.raises(ZeroDivisionError):
        divide(10, 0)

# Assert exception message
def test_invalid_input():
    with pytest.raises(ValueError, match="must be positive"):
        process(-1)

# Capture exception for inspection
def test_custom_exception():
    with pytest.raises(CustomError) as exc_info:
        trigger_error()

    assert exc_info.value.code == 42
    assert "details" in exc_info.value.message
```

### Testing Warnings

```python
import warnings
import pytest

def test_deprecated_function():
    """Test that deprecated function raises warning."""
    with pytest.warns(DeprecationWarning, match="deprecated"):
        deprecated_function()

def test_no_warnings():
    """Test that no warnings are raised."""
    with warnings.catch_warnings():
        warnings.simplefilter("error")
        safe_function()  # Raises if any warning
```

### Mocking and Patching

```python
from unittest.mock import patch, Mock, MagicMock

def test_external_api_call(mocker):
    """Mock external API call."""
    # Mock function
    mock_response = Mock()
    mock_response.json.return_value = {"data": "test"}
    mocker.patch("requests.get", return_value=mock_response)

    result = fetch_data_from_api()
    assert result["data"] == "test"

def test_database_interaction(mocker):
    """Mock database calls."""
    mock_db = mocker.patch("myapp.database.Database")
    mock_db.return_value.query.return_value = [{"id": 1}]

    result = get_users()
    assert len(result) == 1
    mock_db.return_value.query.assert_called_once()
```

### Temporary Files and Directories

```python
import pytest
from pathlib import Path

def test_file_processing(tmp_path: Path):
    """Test with temporary directory."""
    # tmp_path is a Path object to a temporary directory
    test_file = tmp_path / "test.txt"
    test_file.write_text("test content")

    result = process_file(test_file)
    assert result.success

def test_config_file(tmp_path: Path):
    """Test with temporary config file."""
    config_file = tmp_path / "config.yaml"
    config_file.write_text("setting: value")

    app = create_app(config_file)
    assert app.config["setting"] == "value"
```

## Running Tests

```bash
# Basic test execution
pytest                          # Run all tests
pytest tests/unit/             # Run specific directory
pytest tests/test_models.py    # Run specific file
pytest tests/test_models.py::test_user_creation  # Run specific test

# Verbosity and output
pytest -v                      # Verbose output
pytest -vv                     # Extra verbose
pytest -q                      # Quiet output
pytest --tb=short              # Short traceback
pytest --tb=no                 # No traceback
pytest -ra                     # Show summary of all outcomes

# Test selection
pytest -k "user"               # Run tests matching "user"
pytest -k "not slow"           # Skip tests matching "slow"
pytest -m unit                 # Run tests with "unit" marker
pytest -m "not integration"    # Skip integration tests

# Parallel execution
pytest -n auto                 # Use all CPUs
pytest -n 4                    # Use 4 workers

# Coverage
pytest --cov=src --cov-report=html --cov-report=term-missing

# Failed tests
pytest --lf                    # Run last failed tests
pytest --ff                    # Run failed first, then others
pytest --sw                    # Stop on first failure
pytest --maxfail=3             # Stop after 3 failures

# Debugging
pytest --pdb                   # Drop into debugger on failure
pytest -x --pdb                # Stop on first failure and debug
pytest --trace                 # Drop into debugger at start of each test

# Output capture
pytest -s                      # Disable output capture (show print statements)
pytest --capture=no            # Same as -s

# Test collection
pytest --collect-only          # Show what tests would run (don't execute)
pytest --markers               # Show available markers
pytest --fixtures              # Show available fixtures
```

## CI Integration

```yaml
# .github/workflows/test.yml
name: Tests

on: [push, pull_request]

jobs:
  test:
    runs-on: ubuntu-latest
    strategy:
      matrix:
        python-version: ["3.11", "3.12"]

    steps:
      - uses: actions/checkout@v4

      - name: Install uv
        uses: astral-sh/setup-uv@v2
        with:
          enable-cache: true

      - name: Set up Python ${{ matrix.python-version }}
        run: uv python install ${{ matrix.python-version }}

      - name: Install dependencies
        run: uv sync --all-extras --dev

      - name: Run tests with coverage
        run: |
          uv run pytest \
            --cov=src \
            --cov-report=xml \
            --cov-report=term-missing \
            --junitxml=test-results.xml

      - name: Upload coverage to Codecov
        uses: codecov/codecov-action@v4
        with:
          file: ./coverage.xml
          fail_ci_if_error: true

      - name: Upload test results
        uses: actions/upload-artifact@v4
        if: always()
        with:
          name: test-results-${{ matrix.python-version }}
          path: test-results.xml
```

## Resources

- **pytest documentation**: https://docs.pytest.org/
- **pytest-asyncio**: https://pytest-asyncio.readthedocs.io/
- **pytest-cov**: https://pytest-cov.readthedocs.io/
- **pytest-xdist**: https://pytest-xdist.readthedocs.io/
- **pytest plugins**: https://docs.pytest.org/en/latest/reference/plugin_list.html

## Summary

Advanced pytest provides:
- **Fixtures**: Reusable test dependencies with flexible scoping
- **Markers**: Test categorization and conditional execution
- **Plugins**: Extended functionality (coverage, async, parallel, mocking)
- **conftest.py**: Centralized fixture and configuration management
- **Async support**: First-class async/await testing with pytest-asyncio
- **Parametrization**: Data-driven testing with readable output
- **Parallel execution**: Fast test runs with pytest-xdist
- **Coverage reporting**: Track test coverage with pytest-cov
