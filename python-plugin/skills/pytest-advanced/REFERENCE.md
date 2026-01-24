# pytest Advanced Reference

Detailed patterns for conftest.py organization, async testing, test structure, and common testing recipes.

## conftest.py Patterns

### Project Structure

```
tests/
├── conftest.py              # Root (session-level fixtures)
├── unit/
│   ├── conftest.py          # Unit test fixtures
│   └── test_models.py
├── integration/
│   ├── conftest.py          # Integration test fixtures
│   └── test_api.py
└── e2e/
    ├── conftest.py          # E2E test fixtures
    └── test_workflows.py
```

### Root conftest.py

```python
import pytest
from myapp import create_app

@pytest.fixture(scope="session")
def app():
    return create_app("testing")

@pytest.fixture(scope="session")
def db_engine():
    engine = create_test_engine()
    yield engine
    engine.dispose()

def pytest_configure(config):
    config.addinivalue_line("markers", "slow: slow tests")
    config.addinivalue_line("markers", "integration: integration tests")

def pytest_collection_modifyitems(config, items):
    """Automatically mark tests based on path."""
    for item in items:
        if "integration" in item.nodeid:
            item.add_marker(pytest.mark.integration)

@pytest.fixture(autouse=True)
def reset_database(db_engine):
    clear_tables(db_engine)
    yield
    rollback_transaction(db_engine)
```

### Domain-Specific conftest.py

```python
# tests/integration/conftest.py
@pytest.fixture
def authenticated_client(app) -> Client:
    client = app.test_client()
    client.login("test@example.com", "password")
    return client

@pytest.fixture
def sample_data(db):
    db.load_fixtures("integration_data.json")
    yield
    db.clear_fixtures()
```

## Async Testing Patterns

### Basic Async Tests

```python
import pytest
import asyncio

@pytest.mark.asyncio
async def test_async_function():
    result = await fetch_data()
    assert result is not None

@pytest.mark.asyncio
async def test_concurrent_operations():
    results = await asyncio.gather(
        fetch_user(1), fetch_user(2), fetch_user(3)
    )
    assert len(results) == 3
```

### Async Fixtures

```python
from typing import AsyncGenerator

@pytest.fixture
async def async_client() -> AsyncGenerator[AsyncClient, None]:
    async with AsyncClient() as client:
        yield client

@pytest.fixture(scope="module")
async def async_db() -> AsyncGenerator[AsyncDatabase, None]:
    db = AsyncDatabase("test.db")
    await db.connect()
    yield db
    await db.close()
```

### Event Loop Management

```python
@pytest.fixture(scope="session")
def event_loop():
    policy = asyncio.get_event_loop_policy()
    loop = policy.new_event_loop()
    yield loop
    loop.close()
```

### Testing Async Context Managers

```python
@pytest.mark.asyncio
async def test_async_context_manager():
    async with AsyncResource() as resource:
        result = await resource.process()
        assert result is not None
    assert resource.is_closed()
```

### Testing Async Generators

```python
@pytest.mark.asyncio
async def test_async_generator():
    results = []
    async for item in async_generator():
        results.append(item)
    assert len(results) == expected_count
```

## Test Organization Best Practices

### AAA Pattern

```python
def test_user_creation():
    # Arrange
    user_data = {"name": "Alice", "email": "alice@example.com"}

    # Act
    user = create_user(user_data)

    # Assert
    assert user.name == "Alice"
    assert user.id is not None
```

### Naming Conventions

```python
# Pattern: test_<function>_<scenario>_<expected_result>
def test_divide_by_zero_raises_error(): ...
def test_user_login_with_valid_credentials_succeeds(): ...
def test_api_call_with_invalid_token_returns_401(): ...
```

### Test Grouping with Classes

```python
class TestUserAuthentication:
    def test_login_success(self, user):
        assert login(user.email, user.password).success

    def test_login_wrong_password(self, user):
        assert not login(user.email, "wrong").success

    def test_logout(self, authenticated_user):
        logout(authenticated_user)
        assert not is_authenticated(authenticated_user)
```

### Complex Parametrization

```python
@pytest.mark.parametrize("user_data,should_succeed", [
    ({"name": "Alice", "email": "alice@example.com"}, True),
    ({"name": "", "email": "alice@example.com"}, False),
    ({"name": "Bob", "email": "invalid"}, False),
    ({"name": "Charlie"}, False),
])
def test_user_validation(user_data: dict, should_succeed: bool):
    if should_succeed:
        assert create_user(user_data) is not None
    else:
        with pytest.raises(ValidationError):
            create_user(user_data)
```

### Test Data Management

```python
@pytest.fixture
def users_data():
    with open("tests/fixtures/users.json") as f:
        return json.load(f)["users"]

@pytest.fixture
def sample_users(db, users_data):
    users = [db.create_user(data) for data in users_data]
    yield users
    for user in users:
        db.delete_user(user.id)
```

## Common Patterns

### Testing Exceptions

```python
# Assert exception is raised
def test_divide_by_zero():
    with pytest.raises(ZeroDivisionError):
        divide(10, 0)

# Assert exception message
def test_invalid_input():
    with pytest.raises(ValueError, match="must be positive"):
        process(-1)

# Capture for inspection
def test_custom_exception():
    with pytest.raises(CustomError) as exc_info:
        trigger_error()
    assert exc_info.value.code == 42
```

### Testing Warnings

```python
def test_deprecated_function():
    with pytest.warns(DeprecationWarning, match="deprecated"):
        deprecated_function()
```

### Mocking and Patching

```python
def test_external_api_call(mocker):
    mock_response = Mock()
    mock_response.json.return_value = {"data": "test"}
    mocker.patch("requests.get", return_value=mock_response)
    result = fetch_data_from_api()
    assert result["data"] == "test"

def test_database_interaction(mocker):
    mock_db = mocker.patch("myapp.database.Database")
    mock_db.return_value.query.return_value = [{"id": 1}]
    result = get_users()
    assert len(result) == 1
    mock_db.return_value.query.assert_called_once()
```

### Temporary Files

```python
def test_file_processing(tmp_path: Path):
    test_file = tmp_path / "test.txt"
    test_file.write_text("test content")
    result = process_file(test_file)
    assert result.success

def test_config_file(tmp_path: Path):
    config_file = tmp_path / "config.yaml"
    config_file.write_text("setting: value")
    app = create_app(config_file)
    assert app.config["setting"] == "value"
```

## Plugin Details

### pytest-cov (Coverage)

```bash
pytest --cov=src --cov-report=html --cov-report=term-missing
pytest --cov=src --cov-fail-under=80  # Fail if below threshold
```

```toml
[tool.coverage.run]
branch = true
source = ["src"]
omit = ["*/tests/*", "*/__pycache__/*"]

[tool.coverage.report]
exclude_lines = [
    "pragma: no cover",
    "if TYPE_CHECKING:",
    "@abstractmethod",
    "raise NotImplementedError",
]
```

### pytest-xdist (Parallel)

```bash
pytest -n auto          # All CPUs
pytest -n 4             # 4 workers
pytest --dist loadfile  # Distribute by file
pytest --dist loadscope # Distribute by scope
```

### pytest-timeout

```python
@pytest.mark.timeout(10)
def test_fast(): ...

@pytest.mark.timeout(0)
def test_no_timeout(): ...
```

```toml
[tool.pytest.ini_options]
timeout = 300
timeout_method = "thread"
```

### pytest-benchmark

```python
def test_performance(benchmark):
    result = benchmark(function_to_test, arg1, arg2)
    assert result == expected
```

```bash
pytest --benchmark-compare=0001  # Compare to baseline
pytest --benchmark-save=baseline  # Save as baseline
```
