---
model: haiku
created: 2025-12-16
modified: 2026-02-14
reviewed: 2026-02-08
name: api-testing
description: |
  HTTP API testing for TypeScript (Supertest) and Python (httpx, pytest). Covers
  REST APIs, GraphQL, request/response validation, authentication, and error handling.
  Use when user mentions API testing, Supertest, httpx, REST testing, endpoint testing,
  HTTP response validation, or testing API routes.
allowed-tools: Bash(curl *), Bash(http *), Bash(jq *), Read, Edit, Write, Grep, Glob, TodoWrite
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
await request(app).get('/api/users').expect(200)

// POST request with body
await request(app).post('/api/users')
  .send({ name: 'John', email: 'john@example.com' }).expect(201)

// PUT request
await request(app).put('/api/users/1')
  .send({ name: 'Jane' }).expect(200)

// PATCH request
await request(app).patch('/api/users/1')
  .send({ email: 'jane@example.com' }).expect(200)

// DELETE request
await request(app).delete('/api/users/1').expect(204)
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
```

### Response Assertions

```typescript
describe('Response validation', () => {
  it('validates status code', async () => {
    await request(app).get('/api/users').expect(200)
  })

  it('validates headers', async () => {
    await request(app).get('/api/users')
      .expect('Content-Type', /json/).expect(200)
  })

  it('validates response body', async () => {
    const response = await request(app).get('/api/users/1').expect(200)
    expect(response.body).toEqual({
      id: 1,
      name: 'John Doe',
      email: 'john@example.com',
      createdAt: expect.any(String),
    })
  })

  it('validates array responses', async () => {
    const response = await request(app).get('/api/users').expect(200)
    expect(response.body).toBeInstanceOf(Array)
    expect(response.body).toHaveLength(5)
    expect(response.body[0]).toHaveProperty('id')
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
from fastapi.testclient import TestClient
from main import app

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
    assert "id" in data

def test_validation_error():
    response = client.post("/api/users", json={"name": "John"})
    assert response.status_code == 422  # FastAPI validation error

def test_not_found():
    response = client.get("/api/users/999")
    assert response.status_code == 404
```

For detailed examples including authentication testing, file uploads, cookie testing, database integration, schema validation, GraphQL testing, performance testing, best practices, and troubleshooting, see [REFERENCE.md](REFERENCE.md).

## Agentic Optimizations

| Context | Command |
|---------|---------|
| Quick test (Bun) | `bun test --dots --bail=1 api` |
| Quick test (pytest) | `pytest -x --tb=short tests/api/` |
| Run single test file | `bun test --dots path/to/test.ts` |
| Verbose on failure | `bun test --bail=1 api` |

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
