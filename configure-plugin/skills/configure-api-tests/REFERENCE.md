# API Tests Reference

Templates and code examples for API contract testing configuration.

## Pact Contract Testing (JavaScript/TypeScript)

### Install Dependencies

```bash
bun add --dev @pact-foundation/pact @pact-foundation/pact-core
```

### Consumer Test Template (`tests/contract/consumer/userService.pact.ts`)

```typescript
import { PactV4, MatchersV3 } from '@pact-foundation/pact';
import { resolve } from 'path';

const { like, eachLike, regex, datetime } = MatchersV3;

const provider = new PactV4({
  consumer: 'frontend-app',
  provider: 'user-service',
  dir: resolve(__dirname, '../../../pacts'),
  logLevel: 'warn',
});

describe('User Service Contract', () => {
  describe('GET /api/users/:id', () => {
    it('returns a user when user exists', async () => {
      await provider
        .addInteraction()
        .given('a user with ID 1 exists')
        .uponReceiving('a request to get user 1')
        .withRequest({
          method: 'GET',
          path: '/api/users/1',
          headers: {
            Accept: 'application/json',
          },
        })
        .willRespondWith({
          status: 200,
          headers: {
            'Content-Type': 'application/json',
          },
          body: {
            id: like(1),
            name: like('John Doe'),
            email: regex(/^[\w.-]+@[\w.-]+\.\w+$/, 'john@example.com'),
            createdAt: datetime("yyyy-MM-dd'T'HH:mm:ss.SSSXXX"),
          },
        })
        .executeTest(async (mockServer) => {
          const response = await fetch(`${mockServer.url}/api/users/1`, {
            headers: { Accept: 'application/json' },
          });

          expect(response.status).toBe(200);

          const user = await response.json();
          expect(user).toHaveProperty('id');
          expect(user).toHaveProperty('name');
          expect(user).toHaveProperty('email');
        });
    });

    it('returns 404 when user does not exist', async () => {
      await provider
        .addInteraction()
        .given('no user with ID 999 exists')
        .uponReceiving('a request to get non-existent user')
        .withRequest({
          method: 'GET',
          path: '/api/users/999',
          headers: {
            Accept: 'application/json',
          },
        })
        .willRespondWith({
          status: 404,
          headers: {
            'Content-Type': 'application/json',
          },
          body: {
            error: like('User not found'),
            code: like('USER_NOT_FOUND'),
          },
        })
        .executeTest(async (mockServer) => {
          const response = await fetch(`${mockServer.url}/api/users/999`, {
            headers: { Accept: 'application/json' },
          });

          expect(response.status).toBe(404);
        });
    });
  });

  describe('POST /api/users', () => {
    it('creates a new user', async () => {
      await provider
        .addInteraction()
        .uponReceiving('a request to create a user')
        .withRequest({
          method: 'POST',
          path: '/api/users',
          headers: {
            'Content-Type': 'application/json',
            Accept: 'application/json',
          },
          body: {
            name: like('Jane Doe'),
            email: like('jane@example.com'),
          },
        })
        .willRespondWith({
          status: 201,
          headers: {
            'Content-Type': 'application/json',
          },
          body: {
            id: like(1),
            name: like('Jane Doe'),
            email: like('jane@example.com'),
            createdAt: datetime("yyyy-MM-dd'T'HH:mm:ss.SSSXXX"),
          },
        })
        .executeTest(async (mockServer) => {
          const response = await fetch(`${mockServer.url}/api/users`, {
            method: 'POST',
            headers: {
              'Content-Type': 'application/json',
              Accept: 'application/json',
            },
            body: JSON.stringify({
              name: 'Jane Doe',
              email: 'jane@example.com',
            }),
          });

          expect(response.status).toBe(201);
        });
    });
  });
});
```

### Provider Verification Template (`tests/contract/provider/userService.provider.ts`)

```typescript
import { Verifier } from '@pact-foundation/pact';
import { resolve } from 'path';
import { app } from '../../../src/app'; // Your Express/Fastify app
import { setupTestDatabase, seedProviderStates } from '../helpers/database';

describe('User Service Provider Verification', () => {
  let server: any;

  beforeAll(async () => {
    await setupTestDatabase();
    server = app.listen(3001);
  });

  afterAll(async () => {
    server.close();
  });

  it('validates the expectations of the consumer', async () => {
    const verifier = new Verifier({
      providerBaseUrl: 'http://localhost:3001',
      pactUrls: [resolve(__dirname, '../../../pacts/frontend-app-user-service.json')],
      // Or use Pact Broker:
      // pactBrokerUrl: process.env.PACT_BROKER_URL,
      // providerVersion: process.env.GIT_SHA,
      // publishVerificationResult: process.env.CI === 'true',

      stateHandlers: {
        'a user with ID 1 exists': async () => {
          await seedProviderStates({
            users: [{ id: 1, name: 'John Doe', email: 'john@example.com' }],
          });
        },
        'no user with ID 999 exists': async () => {
          // Ensure user 999 doesn't exist (default state after cleanup)
        },
      },
    });

    await verifier.verifyProvider();
  });
});
```

## Pact Contract Testing (Python)

### Install Dependencies

```bash
uv add --group dev pact-python
```

### Consumer Test Template (`tests/contract/consumer/test_user_service.py`)

```python
import pytest
from pact import Consumer, Provider, Like, EachLike, Term
import requests

pact = Consumer('frontend-app').has_pact_with(
    Provider('user-service'),
    pact_dir='./pacts',
    log_dir='./logs',
)

@pytest.fixture(scope='module')
def pact_setup():
    pact.start_service()
    yield pact
    pact.stop_service()

def test_get_user(pact_setup):
    """Test getting a user by ID."""
    expected = {
        'id': Like(1),
        'name': Like('John Doe'),
        'email': Term(r'^[\w.-]+@[\w.-]+\.\w+$', 'john@example.com'),
    }

    (pact_setup
        .given('a user with ID 1 exists')
        .upon_receiving('a request to get user 1')
        .with_request('GET', '/api/users/1')
        .will_respond_with(200, body=expected))

    with pact_setup:
        result = requests.get(f'{pact_setup.uri}/api/users/1')

    assert result.status_code == 200
    assert 'id' in result.json()
    assert 'name' in result.json()

def test_get_nonexistent_user(pact_setup):
    """Test 404 response for non-existent user."""
    (pact_setup
        .given('no user with ID 999 exists')
        .upon_receiving('a request to get non-existent user')
        .with_request('GET', '/api/users/999')
        .will_respond_with(404, body={
            'error': Like('User not found'),
            'code': Like('USER_NOT_FOUND'),
        }))

    with pact_setup:
        result = requests.get(f'{pact_setup.uri}/api/users/999')

    assert result.status_code == 404
```

## OpenAPI Validation (JavaScript/TypeScript)

### Install Dependencies

```bash
bun add --dev @apidevtools/swagger-parser ajv ajv-formats
bun add --dev openapi-typescript  # For TypeScript types from OpenAPI
```

### OpenAPI Validator (`tests/api/openapi-validator.ts`)

```typescript
import Ajv from 'ajv';
import addFormats from 'ajv-formats';
import SwaggerParser from '@apidevtools/swagger-parser';
import { OpenAPIV3 } from 'openapi-types';

export class OpenAPIValidator {
  private ajv: Ajv;
  private spec: OpenAPIV3.Document | null = null;
  private schemas: Map<string, object> = new Map();

  constructor() {
    this.ajv = new Ajv({ allErrors: true, strict: false });
    addFormats(this.ajv);
  }

  async loadSpec(specPath: string): Promise<void> {
    this.spec = await SwaggerParser.validate(specPath) as OpenAPIV3.Document;

    if (this.spec.components?.schemas) {
      for (const [name, schema] of Object.entries(this.spec.components.schemas)) {
        this.schemas.set(name, schema);
        this.ajv.addSchema(schema, `#/components/schemas/${name}`);
      }
    }
  }

  validateResponse(
    path: string,
    method: string,
    statusCode: number,
    body: unknown
  ): { valid: boolean; errors: string[] } {
    if (!this.spec) {
      throw new Error('OpenAPI spec not loaded. Call loadSpec() first.');
    }

    const pathItem = this.spec.paths?.[path];
    if (!pathItem) {
      return { valid: false, errors: [`Path ${path} not found in spec`] };
    }

    const operation = pathItem[method.toLowerCase() as keyof OpenAPIV3.PathItemObject] as OpenAPIV3.OperationObject;
    if (!operation) {
      return { valid: false, errors: [`Method ${method} not found for path ${path}`] };
    }

    const response = operation.responses?.[statusCode] || operation.responses?.['default'];
    if (!response) {
      return { valid: false, errors: [`Status ${statusCode} not defined for ${method} ${path}`] };
    }

    const responseObj = response as OpenAPIV3.ResponseObject;
    const content = responseObj.content?.['application/json'];
    if (!content?.schema) {
      return { valid: true, errors: [] };
    }

    const validate = this.ajv.compile(content.schema);
    const valid = validate(body);

    return {
      valid: !!valid,
      errors: validate.errors?.map(e => `${e.instancePath} ${e.message}`) || [],
    };
  }

  validateRequest(
    path: string,
    method: string,
    body: unknown
  ): { valid: boolean; errors: string[] } {
    if (!this.spec) {
      throw new Error('OpenAPI spec not loaded. Call loadSpec() first.');
    }

    const pathItem = this.spec.paths?.[path];
    if (!pathItem) {
      return { valid: false, errors: [`Path ${path} not found in spec`] };
    }

    const operation = pathItem[method.toLowerCase() as keyof OpenAPIV3.PathItemObject] as OpenAPIV3.OperationObject;
    if (!operation?.requestBody) {
      return { valid: true, errors: [] };
    }

    const requestBody = operation.requestBody as OpenAPIV3.RequestBodyObject;
    const content = requestBody.content?.['application/json'];
    if (!content?.schema) {
      return { valid: true, errors: [] };
    }

    const validate = this.ajv.compile(content.schema);
    const valid = validate(body);

    return {
      valid: !!valid,
      errors: validate.errors?.map(e => `${e.instancePath} ${e.message}`) || [],
    };
  }
}

export async function createValidator(specPath: string = './openapi.yaml'): Promise<OpenAPIValidator> {
  const validator = new OpenAPIValidator();
  await validator.loadSpec(specPath);
  return validator;
}
```

### OpenAPI Test Template (`tests/api/users.openapi.test.ts`)

```typescript
import { describe, it, expect, beforeAll } from 'vitest';
import request from 'supertest';
import { app } from '../../src/app';
import { createValidator, OpenAPIValidator } from './openapi-validator';

describe('Users API - OpenAPI Compliance', () => {
  let validator: OpenAPIValidator;

  beforeAll(async () => {
    validator = await createValidator('./openapi.yaml');
  });

  describe('GET /api/users', () => {
    it('response matches OpenAPI schema', async () => {
      const response = await request(app)
        .get('/api/users')
        .expect(200);

      const result = validator.validateResponse('/api/users', 'GET', 200, response.body);

      expect(result.valid).toBe(true);
      if (!result.valid) {
        console.error('Validation errors:', result.errors);
      }
    });
  });

  describe('POST /api/users', () => {
    it('request matches OpenAPI schema', async () => {
      const requestBody = {
        name: 'Test User',
        email: 'test@example.com',
      };

      const requestValidation = validator.validateRequest('/api/users', 'POST', requestBody);
      expect(requestValidation.valid).toBe(true);

      const response = await request(app)
        .post('/api/users')
        .send(requestBody)
        .expect(201);

      const responseValidation = validator.validateResponse('/api/users', 'POST', 201, response.body);
      expect(responseValidation.valid).toBe(true);
    });

    it('rejects invalid request body', async () => {
      const invalidBody = {
        name: 123, // Should be string
        // Missing required email
      };

      const validation = validator.validateRequest('/api/users', 'POST', invalidBody);
      expect(validation.valid).toBe(false);
      expect(validation.errors.length).toBeGreaterThan(0);
    });
  });

  describe('GET /api/users/:id', () => {
    it('404 response matches OpenAPI schema', async () => {
      const response = await request(app)
        .get('/api/users/99999')
        .expect(404);

      const result = validator.validateResponse('/api/users/{id}', 'GET', 404, response.body);
      expect(result.valid).toBe(true);
    });
  });
});
```

## OpenAPI Breaking Change Detection

### Install oasdiff

```bash
bun add --dev @oasdiff/oasdiff
# Or via homebrew
brew install oasdiff
```

### CI Workflow Step

```yaml
- name: Check for breaking API changes
  run: |
    git fetch origin main
    git show origin/main:openapi.yaml > openapi-main.yaml

    oasdiff breaking openapi-main.yaml openapi.yaml --fail-on ERR
    oasdiff changelog openapi-main.yaml openapi.yaml
```

## Schema Testing with Zod

### Install Dependencies

```bash
bun add zod
bun add --dev @anatine/zod-openapi  # Optional: generate OpenAPI from Zod
```

### Schema Definitions (`src/schemas/user.ts`)

```typescript
import { z } from 'zod';

export const UserSchema = z.object({
  id: z.number().int().positive(),
  name: z.string().min(1).max(100),
  email: z.string().email(),
  createdAt: z.string().datetime(),
  updatedAt: z.string().datetime().optional(),
});

export const CreateUserSchema = UserSchema.omit({
  id: true,
  createdAt: true,
  updatedAt: true,
});

export const UpdateUserSchema = CreateUserSchema.partial();

export const UserListSchema = z.array(UserSchema);

export type User = z.infer<typeof UserSchema>;
export type CreateUser = z.infer<typeof CreateUserSchema>;
export type UpdateUser = z.infer<typeof UpdateUserSchema>;
```

### Schema Test Template (`tests/api/schema.test.ts`)

```typescript
import { describe, it, expect } from 'vitest';
import request from 'supertest';
import { app } from '../../src/app';
import { UserSchema, UserListSchema } from '../../src/schemas/user';

describe('API Schema Validation', () => {
  describe('GET /api/users', () => {
    it('response matches User list schema', async () => {
      const response = await request(app)
        .get('/api/users')
        .expect(200);

      const result = UserListSchema.safeParse(response.body);

      expect(result.success).toBe(true);
      if (!result.success) {
        console.error('Schema errors:', result.error.format());
      }
    });
  });

  describe('GET /api/users/:id', () => {
    it('response matches User schema', async () => {
      const response = await request(app)
        .get('/api/users/1')
        .expect(200);

      const result = UserSchema.safeParse(response.body);

      expect(result.success).toBe(true);
    });
  });
});
```

## CI/CD Workflow Template

### `.github/workflows/api-tests.yml`

```yaml
name: API Contract Tests

on:
  push:
    branches: [main]
  pull_request:
    paths:
      - 'openapi.yaml'
      - 'src/api/**'
      - 'tests/contract/**'

jobs:
  consumer-tests:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - uses: oven-sh/setup-bun@v2

      - name: Install dependencies
        run: bun install --frozen-lockfile

      - name: Run consumer contract tests
        run: bun run test:contract:consumer

      - name: Upload pacts
        uses: actions/upload-artifact@v4
        with:
          name: pacts
          path: pacts/

  provider-tests:
    runs-on: ubuntu-latest
    needs: consumer-tests
    services:
      postgres:
        image: postgres:16-alpine
        env:
          POSTGRES_USER: test
          POSTGRES_PASSWORD: test
          POSTGRES_DB: test_db
        ports:
          - 5432:5432

    steps:
      - uses: actions/checkout@v4

      - uses: oven-sh/setup-bun@v2

      - name: Install dependencies
        run: bun install --frozen-lockfile

      - name: Download pacts
        uses: actions/download-artifact@v4
        with:
          name: pacts
          path: pacts/

      - name: Run provider verification
        run: bun run test:contract:provider
        env:
          DATABASE_URL: postgresql://test:test@localhost:5432/test_db

  openapi-validation:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
        with:
          fetch-depth: 0

      - name: Validate OpenAPI spec
        run: |
          bunx @apidevtools/swagger-cli validate openapi.yaml

      - name: Check for breaking changes
        if: github.event_name == 'pull_request'
        run: |
          git fetch origin main
          git show origin/main:openapi.yaml > openapi-main.yaml || echo "No existing spec"

          if [ -f openapi-main.yaml ]; then
            bunx oasdiff breaking openapi-main.yaml openapi.yaml --fail-on ERR
          fi

  # Optional: Publish to Pact Broker
  publish-pacts:
    runs-on: ubuntu-latest
    needs: [consumer-tests, provider-tests]
    if: github.ref == 'refs/heads/main'
    steps:
      - uses: actions/checkout@v4

      - name: Download pacts
        uses: actions/download-artifact@v4
        with:
          name: pacts
          path: pacts/

      - name: Publish to Pact Broker
        run: |
          curl -X PUT \
            -H "Content-Type: application/json" \
            -d @pacts/frontend-app-user-service.json \
            "${{ secrets.PACT_BROKER_URL }}/pacts/provider/user-service/consumer/frontend-app/version/${{ github.sha }}"
        env:
          PACT_BROKER_TOKEN: ${{ secrets.PACT_BROKER_TOKEN }}
```

## Package.json Scripts

```json
{
  "scripts": {
    "test:contract": "bun run test:contract:consumer && bun run test:contract:provider",
    "test:contract:consumer": "vitest run tests/contract/consumer/",
    "test:contract:provider": "vitest run tests/contract/provider/",
    "test:openapi": "vitest run tests/api/*.openapi.test.ts",
    "test:schema": "vitest run tests/api/schema.test.ts",
    "openapi:validate": "bunx @apidevtools/swagger-cli validate openapi.yaml",
    "openapi:bundle": "bunx @apidevtools/swagger-cli bundle openapi.yaml -o dist/openapi.json",
    "openapi:types": "bunx openapi-typescript openapi.yaml -o src/types/api.d.ts"
  }
}
```
