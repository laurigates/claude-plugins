---
description: Check and configure API contract testing with Pact, OpenAPI validation, and schema testing
allowed-tools: Glob, Grep, Read, Write, Edit, Bash, AskUserQuestion, TodoWrite
argument-hint: "[--check-only] [--fix] [--type <pact|openapi|schema>]"
---

# /configure:api-tests

Check and configure API contract testing infrastructure for validating API contracts, schemas, and consumer-provider agreements.

## Context

This command validates API testing setup and optionally configures contract testing, OpenAPI validation, and schema testing.

**API Testing Types:**
- **Contract Testing (Pact)** - Consumer-driven contracts between services
- **OpenAPI Validation** - Validate requests/responses against OpenAPI spec
- **Schema Testing** - JSON Schema validation for API responses
- **Snapshot Testing** - API response structure verification

**When to Use Each:**
| Type | Use Case |
|------|----------|
| Pact | Microservices, multiple consumers, breaking change detection |
| OpenAPI | API-first development, documentation-driven testing |
| Schema | Simple validation, GraphQL APIs, single service |

## Workflow

### Phase 1: Project Detection

Detect existing API testing infrastructure:

| Indicator | Component | Status |
|-----------|-----------|--------|
| `pact` in dependencies | Pact contract testing | Installed |
| `openapi.yaml` or `swagger.json` | OpenAPI specification | Present |
| `@apidevtools/swagger-parser` | OpenAPI validation | Configured |
| `ajv` in dependencies | JSON Schema validation | Configured |
| `pacts/` directory | Pact contracts | Present |

### Phase 2: Current State Analysis

Check for complete API testing setup:

**Contract Testing (Pact):**
- [ ] `@pact-foundation/pact` installed (JS) or `pact-python` (Python)
- [ ] Consumer tests defined
- [ ] Provider verification configured
- [ ] Pact Broker or PactFlow configured (optional)
- [ ] CI/CD pipeline integration

**OpenAPI Validation:**
- [ ] OpenAPI specification file exists
- [ ] Request validation middleware configured
- [ ] Response validation in tests
- [ ] Schema auto-generation configured
- [ ] Breaking change detection

**Schema Testing:**
- [ ] JSON Schema definitions exist
- [ ] `ajv` or similar validator installed
- [ ] Response validation helpers
- [ ] Schema versioning strategy

### Phase 3: Compliance Report

Generate formatted compliance report:

```
API Testing Compliance Report
==============================
Project: [name]
API Type: [REST | GraphQL | gRPC]

Contract Testing (Pact):
  @pact-foundation/pact    package.json               [✅ INSTALLED | ❌ MISSING]
  Consumer tests           tests/contract/consumer/   [✅ FOUND | ❌ NONE]
  Provider tests           tests/contract/provider/   [✅ FOUND | ❌ NONE]
  Pact Broker              CI configuration           [✅ CONFIGURED | ⏭️ OPTIONAL]
  can-i-deploy             CI gate                    [✅ CONFIGURED | ⏭️ OPTIONAL]

OpenAPI Validation:
  OpenAPI spec             openapi.yaml               [✅ EXISTS | ❌ MISSING]
  Spec version             OpenAPI 3.1                [✅ CURRENT | ⚠️ OUTDATED]
  Request validation       middleware                 [✅ CONFIGURED | ⚠️ MISSING]
  Response validation      test helpers               [✅ CONFIGURED | ⚠️ MISSING]
  Breaking change CI       oasdiff                    [✅ CONFIGURED | ⏭️ OPTIONAL]

Schema Testing:
  JSON Schemas             schemas/                   [✅ EXISTS | ⏭️ N/A]
  Schema validator         ajv/zod                    [✅ INSTALLED | ❌ MISSING]
  Response validation      test helpers               [✅ CONFIGURED | ⚠️ MISSING]

Overall: [X issues found]

Recommendations:
  - Add Pact consumer tests for service dependencies
  - Configure OpenAPI response validation in tests
  - Add breaking change detection to CI
```

### Phase 4: Configuration (if --fix or user confirms)

#### Pact Contract Testing (JavaScript/TypeScript)

**Install dependencies:**
```bash
bun add --dev @pact-foundation/pact @pact-foundation/pact-core
```

**Create `tests/contract/consumer/userService.pact.ts`:**
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

**Create `tests/contract/provider/userService.provider.ts`:**
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

#### Pact Contract Testing (Python)

**Install dependencies:**
```bash
uv add --group dev pact-python
```

**Create `tests/contract/consumer/test_user_service.py`:**
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

#### OpenAPI Validation (JavaScript/TypeScript)

**Install dependencies:**
```bash
bun add --dev @apidevtools/swagger-parser ajv ajv-formats
bun add --dev openapi-typescript  # For TypeScript types from OpenAPI
```

**Create `tests/api/openapi-validator.ts`:**
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

    // Register all schemas from components
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
      // No schema defined, consider valid
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

// Helper for tests
export async function createValidator(specPath: string = './openapi.yaml'): Promise<OpenAPIValidator> {
  const validator = new OpenAPIValidator();
  await validator.loadSpec(specPath);
  return validator;
}
```

**Create `tests/api/users.openapi.test.ts`:**
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

#### OpenAPI Breaking Change Detection

**Install oasdiff:**
```bash
# Via npm/bun
bun add --dev @oasdiff/oasdiff

# Or via homebrew
brew install oasdiff
```

**Add to CI workflow:**
```yaml
- name: Check for breaking API changes
  run: |
    # Fetch main branch spec
    git fetch origin main
    git show origin/main:openapi.yaml > openapi-main.yaml

    # Check for breaking changes
    oasdiff breaking openapi-main.yaml openapi.yaml --fail-on ERR

    # Generate changelog
    oasdiff changelog openapi-main.yaml openapi.yaml
```

#### Schema Testing with Zod

**Install dependencies:**
```bash
bun add zod
bun add --dev @anatine/zod-openapi  # Optional: generate OpenAPI from Zod
```

**Create `src/schemas/user.ts`:**
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

**Create `tests/api/schema.test.ts`:**
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
      // Assuming user 1 exists
      const response = await request(app)
        .get('/api/users/1')
        .expect(200);

      const result = UserSchema.safeParse(response.body);

      expect(result.success).toBe(true);
    });
  });
});
```

### Phase 5: CI/CD Integration

**Create `.github/workflows/api-tests.yml`:**

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

**Add npm scripts to `package.json`:**
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

### Phase 6: Standards Tracking

Update `.fvh-standards.yaml`:

```yaml
standards_version: "2025.1"
last_configured: "[timestamp]"
components:
  api_tests: "2025.1"
  api_tests_contract: "[pact|none]"
  api_tests_openapi: true
  api_tests_schema: "[zod|ajv|none]"
  api_tests_breaking_change_ci: true
```

### Phase 7: Updated Compliance Report

```
API Testing Configuration Complete
===================================

Contract Testing: Pact
Schema Validation: Zod
OpenAPI: 3.1

Configuration Applied:
  ✅ @pact-foundation/pact installed
  ✅ Consumer contract tests created
  ✅ Provider verification configured
  ✅ OpenAPI validator created
  ✅ Zod schemas configured

Test Structure:
  ✅ tests/contract/consumer/ - Consumer tests
  ✅ tests/contract/provider/ - Provider verification
  ✅ tests/api/*.openapi.test.ts - OpenAPI validation
  ✅ pacts/ - Generated contracts

Scripts Added:
  ✅ bun run test:contract (all contract tests)
  ✅ bun run test:contract:consumer (consumer only)
  ✅ bun run test:contract:provider (provider only)
  ✅ bun run test:openapi (OpenAPI validation)
  ✅ bun run openapi:validate (spec validation)

CI/CD:
  ✅ Consumer tests job
  ✅ Provider verification job
  ✅ OpenAPI breaking change detection
  ✅ Pact artifact upload

Next Steps:
  1. Run consumer tests:
     bun run test:contract:consumer

  2. Verify provider:
     bun run test:contract:provider

  3. Validate OpenAPI spec:
     bun run openapi:validate

  4. Check API compliance:
     bun run test:openapi

Documentation:
  - Pact: https://docs.pact.io
  - OpenAPI: https://swagger.io/specification
  - Zod: https://zod.dev
```

## Flags

| Flag | Description |
|------|-------------|
| `--check-only` | Report status without offering fixes |
| `--fix` | Apply all fixes automatically without prompting |
| `--type <type>` | Focus on specific type (pact, openapi, schema) |

## Examples

```bash
# Check compliance and offer fixes
/configure:api-tests

# Check only, no modifications
/configure:api-tests --check-only

# Auto-fix all issues
/configure:api-tests --fix

# Configure Pact only
/configure:api-tests --fix --type pact

# Configure OpenAPI validation only
/configure:api-tests --fix --type openapi
```

## Error Handling

- **No OpenAPI spec found**: Offer to create template
- **Pact version mismatch**: Suggest upgrade path
- **Schema validation fails**: Report specific errors
- **Pact Broker not configured**: Provide setup instructions

## See Also

- `/configure:tests` - Unit testing configuration
- `/configure:integration-tests` - Integration testing
- `/configure:all` - Run all FVH compliance checks
- **Pact documentation**: https://docs.pact.io
- **OpenAPI specification**: https://swagger.io/specification
- **Zod documentation**: https://zod.dev
