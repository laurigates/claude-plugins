# API Plugin

A comprehensive Claude Code plugin for API integration and testing, providing specialized agents, skills, and commands for working with REST APIs.

## Overview

The API Plugin provides tools for:
- **API Testing**: Supertest (TypeScript/JavaScript) and httpx/pytest (Python)
- **API Integration**: Discovering, exploring, and integrating with REST APIs
- **Contract Testing**: Pact consumer-driven contracts
- **OpenAPI Validation**: Request/response validation against OpenAPI specs
- **Schema Testing**: JSON Schema and Zod validation

## Components

### Agents

#### `api-integration`
Specialized agent for exploring and integrating with REST APIs, especially when documentation is limited or unavailable.

**Use cases:**
- Discovering undocumented API endpoints
- Inferring schemas from API responses
- Detecting authentication methods
- Generating OpenAPI specifications
- Creating typed API clients

**Model**: Claude Opus 4.5

**Workflow:**
1. Probe for existing OpenAPI/Swagger specs
2. Discover API structure using httpie
3. Analyze responses with jq to infer schemas
4. Generate OpenAPI specification
5. Create typed client code with Orval or openapi-generator
6. Validate generated client against live API

### Skills

#### `api-testing`
Expert knowledge for HTTP API testing with Supertest (TypeScript/JavaScript) and httpx/pytest (Python).

**Covers:**
- Request testing (headers, query params, request bodies)
- Response validation (status codes, headers, JSON schemas)
- Authentication testing (Bearer tokens, cookies, OAuth)
- Error handling (4xx/5xx responses, validation errors)
- File upload and cookie testing
- GraphQL API testing
- Database integration testing
- Performance testing

**Technologies:**
- **TypeScript/JavaScript**: Supertest, Express, Vitest
- **Python**: httpx, pytest, FastAPI

#### `configure-api-tests`
Check and configure API contract testing infrastructure.

**Features:**
- Detect existing API testing setup
- Configure Pact contract testing
- Set up OpenAPI validation
- Configure schema testing with Zod or AJV
- Add breaking change detection to CI
- Generate comprehensive compliance reports

**Flags:**
- `--check-only` - Report status without offering fixes
- `--fix` - Apply all fixes automatically
- `--type <pact|openapi|schema>` - Focus on specific type

## Installation

Install this plugin in your Claude Code environment:

```bash
# From the plugin directory
cd /path/to/api-plugin

# The plugin is now available to Claude Code
```

## Usage

### Using the API Integration Agent

Invoke the agent when you need to explore or integrate with an API:

```
I need to integrate with the GitHub API. Can you help me discover the endpoints and generate a client?
```

The `api-integration` agent will:
1. Check for existing OpenAPI documentation
2. Discover available endpoints
3. Infer response schemas
4. Generate typed client code

### Using the API Testing Skill

The skill is automatically activated when discussing API testing:

```
How do I test a REST API endpoint with authentication using Supertest?
```

Or explicitly:

```
Using the api-testing skill, show me how to test file uploads in FastAPI
```

### Using the Configure Command

Check API testing compliance:

```bash
/configure:api-tests
```

Auto-fix all issues:

```bash
/configure:api-tests --fix
```

Configure only Pact contract testing:

```bash
/configure:api-tests --fix --type pact
```

## API Testing Types

### Contract Testing (Pact)
Consumer-driven contracts for microservices.

**When to use:**
- Multiple services with API dependencies
- Need to detect breaking changes early
- Want to test service integration without running all services

**Setup includes:**
- Consumer contract tests
- Provider verification
- Optional Pact Broker integration
- CI/CD pipeline configuration

### OpenAPI Validation
Validate requests and responses against OpenAPI specification.

**When to use:**
- API-first development
- Documentation-driven testing
- Need to ensure API implementation matches spec

**Setup includes:**
- OpenAPI specification file
- Request/response validation helpers
- Breaking change detection
- TypeScript types generation

### Schema Testing
JSON Schema or Zod validation for API responses.

**When to use:**
- Simple validation needs
- GraphQL APIs
- Single service applications
- Want type-safe schemas in code

**Setup includes:**
- Schema definitions (Zod or JSON Schema)
- Response validation helpers
- Type inference from schemas

## Examples

### Testing a REST API with Supertest (TypeScript)

```typescript
import { describe, it, expect } from 'vitest'
import request from 'supertest'
import { app } from './app'

describe('Users API', () => {
  it('creates a new user', async () => {
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

  it('requires authentication', async () => {
    await request(app)
      .get('/api/protected')
      .expect(401)

    await request(app)
      .get('/api/protected')
      .set('Authorization', 'Bearer valid-token')
      .expect(200)
  })
})
```

### Testing with httpx (Python)

```python
import pytest
from fastapi.testclient import TestClient
from main import app

@pytest.fixture
def client():
    return TestClient(app)

def test_create_user(client):
    response = client.post(
        "/api/users",
        json={"name": "John Doe", "email": "john@example.com"}
    )
    assert response.status_code == 201
    data = response.json()
    assert data["name"] == "John Doe"

def test_authentication(client):
    # Without token
    response = client.get("/api/protected")
    assert response.status_code == 401

    # With token
    response = client.get(
        "/api/protected",
        headers={"Authorization": "Bearer valid-token"}
    )
    assert response.status_code == 200
```

### Pact Contract Testing

```typescript
import { PactV4, MatchersV3 } from '@pact-foundation/pact';

const { like, regex, datetime } = MatchersV3;

const provider = new PactV4({
  consumer: 'frontend-app',
  provider: 'user-service',
});

describe('User Service Contract', () => {
  it('returns a user', async () => {
    await provider
      .addInteraction()
      .given('a user with ID 1 exists')
      .uponReceiving('a request to get user 1')
      .withRequest({
        method: 'GET',
        path: '/api/users/1',
      })
      .willRespondWith({
        status: 200,
        body: {
          id: like(1),
          name: like('John Doe'),
          email: regex(/^[\w.-]+@[\w.-]+\.\w+$/, 'john@example.com'),
          createdAt: datetime("yyyy-MM-dd'T'HH:mm:ss.SSSXXX"),
        },
      })
      .executeTest(async (mockServer) => {
        const response = await fetch(`${mockServer.url}/api/users/1`);
        expect(response.status).toBe(200);
      });
  });
});
```

## Best Practices

### Test Organization
- Group related endpoints in describe blocks
- Use fixtures for common setup
- Keep tests focused on single behavior
- Test both happy path and error cases

### Database State
- Reset database between tests
- Use transactions that rollback
- Seed minimal test data
- Avoid depending on test execution order

### Assertions
- Validate status codes first
- Check response structure
- Verify specific field values
- Test error message format

### Performance
- Mock expensive external service calls
- Use in-memory databases for tests
- Run tests in parallel when possible
- Keep test suites fast (< 30s for unit, < 5min for integration)

## CI/CD Integration

The plugin provides GitHub Actions workflow templates for:
- Consumer contract tests
- Provider verification
- OpenAPI validation
- Breaking change detection
- Pact artifact management

## Related Tools

- **Supertest**: HTTP assertions for Node.js
- **httpx**: Modern HTTP client for Python
- **Pact**: Consumer-driven contract testing
- **OpenAPI**: API specification standard
- **Zod**: TypeScript-first schema validation
- **AJV**: JSON Schema validator

## References

- [Supertest Documentation](https://github.com/ladjs/supertest)
- [httpx Documentation](https://www.python-httpx.org/)
- [Pact Documentation](https://docs.pact.io)
- [OpenAPI Specification](https://swagger.io/specification/)
- [Zod Documentation](https://zod.dev)
- [FastAPI Testing Guide](https://fastapi.tiangolo.com/tutorial/testing/)
- [Node.js Testing Best Practices](https://github.com/goldbergyoni/nodejs-testing-best-practices)

## Version

1.0.0

## Author

Lauri Gates

## License

See project license for details.
