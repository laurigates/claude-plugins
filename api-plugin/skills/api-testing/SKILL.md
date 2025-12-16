---
name: api-testing
description: |
  HTTP API testing for TypeScript (Supertest) and Python (httpx, pytest). Covers
  REST APIs, GraphQL, request/response validation, authentication, and error handling.
  Use when user mentions API testing, Supertest, httpx, REST testing, endpoint testing,
  HTTP response validation, or testing API routes.
allowed-tools: Bash, Read, Edit, Write, Grep, Glob, TodoWrite
---

# API Testing

Expert knowledge for testing HTTP APIs with Supertest (TypeScript/JavaScript) and httpx/pytest (Python).

## Core Expertise

**API Testing Capabilities**
- **Request testing**: Headers, query params, request bodies
- **Response validation**: Status codes, headers, JSON schemas
- **Authentication**: Bearer tokens, cookies, OAuth flows
- **Error handling**: 4xx/5xx responses, validation errors
- **Integration**: Database state, external services
- **Performance**: Response times, load testing basics

## TypeScript/JavaScript (Supertest)

### Installation

```bash
# Using Bun
bun add -d supertest @types/supertest

# Using npm
npm install -D supertest @types/supertest
```

### Basic Setup with Express

```typescript
// app.ts
import express from 'express'

export const app = express()
app.use(express.json())

app.get('/api/health', (req, res) => {
  res.json({ status: 'ok' })
})

app.post('/api/users', (req, res) => {
  const { name, email } = req.body
  if (!name || !email) {
    return res.status(400).json({ error: 'Missing required fields' })
  }
  res.status(201).json({ id: 1, name, email })
})
```

```typescript
// app.test.ts
import { describe, it, expect } from 'vitest'
import request from 'supertest'
import { app } from './app'

describe('API Tests', () => {
  it('returns health status', async () => {
    const response = await request(app)
      .get('/api/health')
      .expect(200)

    expect(response.body).toEqual({ status: 'ok' })
  })

  it('creates a user', async () => {
    const response = await request(app)
      .post('/api/users')
      .send({ name: 'John Doe', email: 'john@example.com' })
      .expect(201)

    expect(response.body).toMatchObject({
      id: expect.any(Number),
      name: 'John Doe',
      email: 'john@example.com',
    })
  })

  it('validates required fields', async () => {
    const response = await request(app)
      .post('/api/users')
      .send({ name: 'John Doe' })
      .expect(400)

    expect(response.body.error).toBeDefined()
  })
})
```

### Request Methods

```typescript
import request from 'supertest'
import { app } from './app'

// GET request
await request(app)
  .get('/api/users')
  .expect(200)

// POST request with body
await request(app)
  .post('/api/users')
  .send({ name: 'John', email: 'john@example.com' })
  .expect(201)

// PUT request
await request(app)
  .put('/api/users/1')
  .send({ name: 'Jane' })
  .expect(200)

// PATCH request
await request(app)
  .patch('/api/users/1')
  .send({ email: 'jane@example.com' })
  .expect(200)

// DELETE request
await request(app)
  .delete('/api/users/1')
  .expect(204)
```

### Headers and Query Parameters

```typescript
// Set headers
await request(app)
  .get('/api/protected')
  .set('Authorization', 'Bearer token123')
  .set('Content-Type', 'application/json')
  .expect(200)

// Query parameters
await request(app)
  .get('/api/users')
  .query({ page: 1, limit: 10 })
  .expect(200)

// Multiple query parameters
await request(app)
  .get('/api/search')
  .query({ q: 'john', sort: 'name', order: 'asc' })
  .expect(200)
```

### Response Assertions

```typescript
describe('Response validation', () => {
  it('validates status code', async () => {
    await request(app)
      .get('/api/users')
      .expect(200)
  })

  it('validates headers', async () => {
    await request(app)
      .get('/api/users')
      .expect('Content-Type', /json/)
      .expect(200)
  })

  it('validates response body', async () => {
    const response = await request(app)
      .get('/api/users/1')
      .expect(200)

    expect(response.body).toEqual({
      id: 1,
      name: 'John Doe',
      email: 'john@example.com',
      createdAt: expect.any(String),
    })
  })

  it('validates array responses', async () => {
    const response = await request(app)
      .get('/api/users')
      .expect(200)

    expect(response.body).toBeInstanceOf(Array)
    expect(response.body).toHaveLength(5)
    expect(response.body[0]).toHaveProperty('id')
  })
})
```

### Authentication Testing

```typescript
describe('Authentication', () => {
  let authToken: string

  beforeAll(async () => {
    // Login to get token
    const response = await request(app)
      .post('/api/auth/login')
      .send({ email: 'user@example.com', password: 'password123' })  // pragma: allowlist secret
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
      .send({ email: 'user@example.com', password: 'password' })  // pragma: allowlist secret
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

## Python (httpx + pytest)

### Installation

```bash
# Using uv
uv add --dev httpx pytest-asyncio

# Using pip
pip install httpx pytest-asyncio
```

### Basic Setup with FastAPI

```python
# main.py
from fastapi import FastAPI, HTTPException
from pydantic import BaseModel

app = FastAPI()

class User(BaseModel):
    name: str
    email: str

@app.get("/api/health")
def health_check():
    return {"status": "ok"}

@app.post("/api/users", status_code=201)
def create_user(user: User):
    return {"id": 1, "name": user.name, "email": user.email}

@app.get("/api/users/{user_id}")
def get_user(user_id: int):
    if user_id == 999:
        raise HTTPException(status_code=404, detail="User not found")
    return {"id": user_id, "name": "John Doe", "email": "john@example.com"}
```

```python
# test_main.py
import pytest
from httpx import AsyncClient
from fastapi.testclient import TestClient
from main import app

# Synchronous testing
client = TestClient(app)

def test_health_check():
    response = client.get("/api/health")
    assert response.status_code == 200
    assert response.json() == {"status": "ok"}

def test_create_user():
    response = client.post(
        "/api/users",
        json={"name": "John Doe", "email": "john@example.com"}
    )
    assert response.status_code == 201
    data = response.json()
    assert data["name"] == "John Doe"
    assert data["email"] == "john@example.com"
    assert "id" in data

def test_validation_error():
    response = client.post("/api/users", json={"name": "John"})
    assert response.status_code == 422  # FastAPI validation error

def test_not_found():
    response = client.get("/api/users/999")
    assert response.status_code == 404
```

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
        json={"email": "user@example.com", "password": "password123"}  # pragma: allowlist secret
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
        json={"email": "user@example.com", "password": "password123"}  # pragma: allowlist secret
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
        json={"email": "user@example.com", "password": "password"}  # pragma: allowlist secret
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
- Avoid depending on test execution order

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
    .send({ email: 'user@example.com', password: 'password' })  // pragma: allowlist secret

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

## See Also

- `vitest-testing` - Unit testing framework
- `python-testing` - Python pytest patterns
- `playwright-testing` - E2E API testing
- `test-quality-analysis` - Test quality patterns

## References

- Supertest: https://github.com/ladjs/supertest
- httpx: https://www.python-httpx.org/
- FastAPI Testing: https://fastapi.tiangolo.com/tutorial/testing/
- Node.js Testing Best Practices: https://github.com/goldbergyoni/nodejs-testing-best-practices
