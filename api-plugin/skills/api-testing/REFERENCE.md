# API Testing - Reference

Detailed reference material for API testing with Supertest (TypeScript/JavaScript) and httpx/pytest (Python).

## TypeScript/JavaScript (Supertest) - Extended Examples

### Authentication Testing

```typescript
describe('Authentication', () => {
  let authToken: string

  beforeAll(async () => {
    // Login to get token
    const response = await request(app)
      .post('/api/auth/login')
      .send({ email: 'user@example.com', password: 'password123' })  // gitleaks:allow
      .expect(200)

    authToken = response.body.token
  })

  it('accesses protected endpoint with token', async () => {
    await request(app)
      .get('/api/protected')
      .set('Authorization', `Bearer ${authToken}`)
      .expect(200)
  })

  it('rejects requests without token', async () => {
    await request(app)
      .get('/api/protected')
      .expect(401)
  })

  it('rejects requests with invalid token', async () => {
    await request(app)
      .get('/api/protected')
      .set('Authorization', 'Bearer invalid-token')
      .expect(401)
  })
})
```

### File Upload Testing

```typescript
import fs from 'fs'
import path from 'path'

it('uploads a file', async () => {
  const response = await request(app)
    .post('/api/upload')
    .attach('file', path.resolve(__dirname, 'test-file.pdf'))
    .field('description', 'Test document')
    .expect(200)

  expect(response.body).toMatchObject({
    filename: expect.any(String),
    size: expect.any(Number),
  })
})
```

### Cookie Testing

```typescript
describe('Cookie handling', () => {
  it('sets and reads cookies', async () => {
    // Login sets cookie
    const loginResponse = await request(app)
      .post('/api/auth/login')
      .send({ email: 'user@example.com', password: 'password' })  // gitleaks:allow
      .expect(200)

    const cookies = loginResponse.headers['set-cookie']

    // Use cookie in subsequent request
    await request(app)
      .get('/api/profile')
      .set('Cookie', cookies)
      .expect(200)
  })
})
```

### Error Handling

```typescript
describe('Error handling', () => {
  it('handles validation errors', async () => {
    const response = await request(app)
      .post('/api/users')
      .send({ email: 'invalid-email' })
      .expect(400)

    expect(response.body).toMatchObject({
      error: 'Validation failed',
      details: expect.arrayContaining([
        expect.objectContaining({
          field: 'email',
          message: expect.any(String),
        }),
      ]),
    })
  })

  it('handles not found errors', async () => {
    await request(app)
      .get('/api/users/999999')
      .expect(404)
  })

  it('handles server errors gracefully', async () => {
    const response = await request(app)
      .post('/api/error-prone-endpoint')
      .expect(500)

    expect(response.body).toHaveProperty('error')
  })
})
```

## Python (httpx + pytest) - Extended Examples

### Async Testing with httpx

```python
import pytest
from httpx import AsyncClient
from main import app

@pytest.mark.asyncio
async def test_async_health_check():
    async with AsyncClient(app=app, base_url="http://test") as client:
        response = await client.get("/api/health")
        assert response.status_code == 200
        assert response.json() == {"status": "ok"}

@pytest.mark.asyncio
async def test_async_create_user():
    async with AsyncClient(app=app, base_url="http://test") as client:
        response = await client.post(
            "/api/users",
            json={"name": "Jane Doe", "email": "jane@example.com"}
        )
        assert response.status_code == 201
        data = response.json()
        assert data["name"] == "Jane Doe"
```

### Fixtures for Common Setup

```python
import pytest
from httpx import AsyncClient
from fastapi.testclient import TestClient
from main import app

@pytest.fixture
def client():
    """Synchronous test client"""
    return TestClient(app)

@pytest.fixture
async def async_client():
    """Async test client"""
    async with AsyncClient(app=app, base_url="http://test") as client:
        yield client

@pytest.fixture
def auth_token(client):
    """Get authentication token"""
    response = client.post(
        "/api/auth/login",
        json={"email": "user@example.com", "password": "password123"}  # gitleaks:allow
    )
    return response.json()["token"]

# Usage
def test_protected_endpoint(client, auth_token):
    response = client.get(
        "/api/protected",
        headers={"Authorization": f"Bearer {auth_token}"}
    )
    assert response.status_code == 200
```

### Headers and Query Parameters

```python
def test_with_headers(client):
    response = client.get(
        "/api/protected",
        headers={
            "Authorization": "Bearer token123",
            "Content-Type": "application/json"
        }
    )
    assert response.status_code == 200

def test_with_query_params(client):
    response = client.get(
        "/api/users",
        params={"page": 1, "limit": 10, "sort": "name"}
    )
    assert response.status_code == 200
    assert len(response.json()) <= 10
```

### Authentication Testing

```python
import pytest
from fastapi.testclient import TestClient
from main import app

@pytest.fixture
def authenticated_client():
    client = TestClient(app)
    # Login
    response = client.post(
        "/api/auth/login",
        json={"email": "user@example.com", "password": "password123"}  # gitleaks:allow
    )
    token = response.json()["token"]

    # Add token to client headers
    client.headers["Authorization"] = f"Bearer {token}"
    return client

def test_access_protected_resource(authenticated_client):
    response = authenticated_client.get("/api/protected")
    assert response.status_code == 200

def test_reject_unauthenticated(client):
    response = client.get("/api/protected")
    assert response.status_code == 401
```

### File Upload Testing

```python
def test_file_upload(client, tmp_path):
    # Create temporary test file
    test_file = tmp_path / "test.txt"
    test_file.write_text("test content")

    with open(test_file, "rb") as f:
        response = client.post(
            "/api/upload",
            files={"file": ("test.txt", f, "text/plain")},
            data={"description": "Test file"}
        )

    assert response.status_code == 200
    assert response.json()["filename"] == "test.txt"
```

### Cookie Testing

```python
def test_cookie_handling(client):
    # Login sets cookie
    response = client.post(
        "/api/auth/login",
        json={"email": "user@example.com", "password": "password"}  # gitleaks:allow
    )
    assert "session" in response.cookies

    # Cookie automatically included in subsequent requests
    response = client.get("/api/profile")
    assert response.status_code == 200
```

### Database Integration Testing

```python
import pytest
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker
from main import app, get_db, Base

# Test database
SQLALCHEMY_DATABASE_URL = "sqlite:///./test.db"
engine = create_engine(SQLALCHEMY_DATABASE_URL)
TestingSessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)

@pytest.fixture
def db():
    """Create test database"""
    Base.metadata.create_all(bind=engine)
    yield
    Base.metadata.drop_all(bind=engine)

@pytest.fixture
def client(db):
    """Override database dependency"""
    def override_get_db():
        try:
            db = TestingSessionLocal()
            yield db
        finally:
            db.close()

    app.dependency_overrides[get_db] = override_get_db
    return TestClient(app)

def test_create_and_retrieve_user(client):
    # Create user
    response = client.post(
        "/api/users",
        json={"name": "John", "email": "john@example.com"}
    )
    assert response.status_code == 201
    user_id = response.json()["id"]

    # Retrieve user
    response = client.get(f"/api/users/{user_id}")
    assert response.status_code == 200
    assert response.json()["name"] == "John"
```

## API Schema Validation

### JSON Schema Validation (TypeScript)

```typescript
import Ajv from 'ajv'

const ajv = new Ajv()

const userSchema = {
  type: 'object',
  properties: {
    id: { type: 'number' },
    name: { type: 'string' },
    email: { type: 'string', format: 'email' },
    createdAt: { type: 'string', format: 'date-time' },
  },
  required: ['id', 'name', 'email'],
}

it('validates user schema', async () => {
  const response = await request(app)
    .get('/api/users/1')
    .expect(200)

  const validate = ajv.compile(userSchema)
  expect(validate(response.body)).toBe(true)
})
```

### Pydantic Validation (Python)

```python
from pydantic import BaseModel, EmailStr, validator

class UserResponse(BaseModel):
    id: int
    name: str
    email: EmailStr
    created_at: str

    @validator('name')
    def name_must_not_be_empty(cls, v):
        if not v.strip():
            raise ValueError('Name cannot be empty')
        return v

def test_user_response_schema(client):
    response = client.get("/api/users/1")
    assert response.status_code == 200

    # Validate response against schema
    user = UserResponse(**response.json())
    assert user.id == 1
    assert isinstance(user.email, str)
```

## Performance Testing

### Response Time Assertions (TypeScript)

```typescript
it('responds within acceptable time', async () => {
  const start = Date.now()

  await request(app)
    .get('/api/users')
    .expect(200)

  const duration = Date.now() - start
  expect(duration).toBeLessThan(100) // 100ms threshold
})
```

### Response Time Assertions (Python)

```python
import time

def test_response_time(client):
    start = time.time()

    response = client.get("/api/users")

    duration = time.time() - start
    assert response.status_code == 200
    assert duration < 0.1  # 100ms threshold
```

## Best Practices

**Test Organization**
- Group related endpoints in `describe` blocks
- Use `beforeEach` for common setup
- Keep tests focused on single behavior
- Test both happy path and error cases

**Database State**
- Reset database between tests
- Use transactions that rollback
- Seed minimal test data
- Ensure each test is independent and self-contained

**Assertions**
- Validate status codes first
- Check response structure
- Verify specific field values
- Test error message format

**Mocking External Services**
```typescript
import { vi } from 'vitest'

// Mock external API
vi.mock('./externalAPI', () => ({
  fetchUserData: vi.fn(() => Promise.resolve({ status: 'ok' })),
}))
```

```python
from unittest.mock import patch

@patch('main.external_api.fetch_user_data')
def test_with_mocked_external_service(mock_fetch, client):
    mock_fetch.return_value = {"status": "ok"}

    response = client.get("/api/users/1")
    assert response.status_code == 200
```

**Common Patterns**

```typescript
// Test factory for creating test data
function createTestUser(overrides = {}) {
  return {
    name: 'Test User',
    email: 'test@example.com',
    ...overrides,
  }
}

// Reusable authentication helper
async function authenticateUser(app: Express) {
  const response = await request(app)
    .post('/api/auth/login')
    .send({ email: 'user@example.com', password: 'password' })  // gitleaks:allow

  return response.body.token
}
```

## GraphQL API Testing

### TypeScript (Supertest)

```typescript
it('queries GraphQL endpoint', async () => {
  const query = `
    query GetUser($id: ID!) {
      user(id: $id) {
        id
        name
        email
      }
    }
  `

  const response = await request(app)
    .post('/graphql')
    .send({ query, variables: { id: '1' } })
    .expect(200)

  expect(response.body.data.user).toMatchObject({
    id: '1',
    name: expect.any(String),
    email: expect.any(String),
  })
})
```

### Python (httpx)

```python
def test_graphql_query(client):
    query = """
    query GetUser($id: ID!) {
      user(id: $id) {
        id
        name
        email
      }
    }
    """

    response = client.post(
        "/graphql",
        json={"query": query, "variables": {"id": "1"}}
    )

    assert response.status_code == 200
    data = response.json()["data"]
    assert data["user"]["id"] == "1"
    assert "name" in data["user"]
```

## Troubleshooting

**Port already in use**
```typescript
// Use random port for testing
const server = app.listen(0) // 0 = random available port
const port = server.address().port
```

**Database connection issues**
```python
# Use separate test database
@pytest.fixture(scope="session")
def db_engine():
    engine = create_engine("sqlite:///./test.db")
    yield engine
    engine.dispose()
```

**Slow tests**
```typescript
// Mock expensive operations
vi.mock('./slowService', () => ({
  processData: vi.fn(() => Promise.resolve('mocked')),
}))
```
