---
description: Check and configure integration testing for services, databases, and external dependencies
allowed-tools: Glob, Grep, Read, Write, Edit, Bash, AskUserQuestion, TodoWrite
argument-hint: "[--check-only] [--fix] [--framework <supertest|pytest|testcontainers>]"
---

# /configure:integration-tests

Check and configure integration testing infrastructure for testing service interactions, databases, and external dependencies.

## Context

This command validates integration testing setup and optionally configures frameworks for testing real service interactions (as opposed to unit tests with mocks or E2E browser tests).

**Integration Testing Stack by Language:**
- **JavaScript/TypeScript**: Supertest + Testcontainers
- **Python**: pytest + testcontainers-python + httpx
- **Rust**: cargo test with `#[ignore]` + testcontainers-rs
- **Go**: testing + testcontainers-go

**Key Difference from Unit Tests:**
- Integration tests interact with **real** databases, APIs, and services
- They test **component boundaries** and **data flow**
- They typically require **test fixtures** and **cleanup**

## Workflow

### Phase 1: Project Detection

Detect existing integration testing infrastructure:

| Indicator | Component | Status |
|-----------|-----------|--------|
| `tests/integration/` directory | Integration tests | Present |
| `testcontainers` in dependencies | Container testing | Configured |
| `supertest` in package.json | HTTP testing | Configured |
| `docker-compose.test.yml` | Test services | Present |
| `pytest.ini` with `integration` marker | pytest integration | Configured |

### Phase 2: Current State Analysis

Check for complete integration testing setup:

**Test Organization:**
- [ ] `tests/integration/` directory exists
- [ ] Integration tests separated from unit tests
- [ ] Test fixtures and factories present
- [ ] Database seeding/migration scripts

**JavaScript/TypeScript (Supertest):**
- [ ] `supertest` installed
- [ ] `@testcontainers/postgresql` or similar installed
- [ ] Test database configuration
- [ ] API endpoint tests present
- [ ] Authentication test helpers

**Python (pytest + testcontainers):**
- [ ] `testcontainers` installed
- [ ] `httpx` or `requests` for HTTP testing
- [ ] `pytest-asyncio` for async tests
- [ ] `integration` marker defined
- [ ] Database fixtures in `conftest.py`

**Container Infrastructure:**
- [ ] `docker-compose.test.yml` exists
- [ ] Test database container defined
- [ ] Redis/cache container (if needed)
- [ ] Message queue container (if needed)
- [ ] Network isolation configured

### Phase 3: Compliance Report

Generate formatted compliance report:

```
Integration Testing Compliance Report
======================================
Project: [name]
Language: [TypeScript | Python | Rust | Go]

Test Organization:
  Integration directory    tests/integration/         [✅ EXISTS | ❌ MISSING]
  Separated from unit      not in src/                [✅ CORRECT | ⚠️ MIXED]
  Test fixtures            tests/fixtures/            [✅ EXISTS | ⚠️ MISSING]
  Database seeds           tests/seeds/               [✅ EXISTS | ⏭️ N/A]

Framework Setup:
  HTTP testing             supertest/httpx            [✅ INSTALLED | ❌ MISSING]
  Container testing        testcontainers             [✅ INSTALLED | ⚠️ MISSING]
  Async support            pytest-asyncio             [✅ INSTALLED | ⏭️ N/A]

Infrastructure:
  docker-compose.test.yml  test services              [✅ EXISTS | ⚠️ MISSING]
  Test database            PostgreSQL/SQLite          [✅ CONFIGURED | ❌ MISSING]
  Service isolation        network config             [✅ CONFIGURED | ⚠️ MISSING]

CI/CD Integration:
  Integration test job     GitHub Actions             [✅ CONFIGURED | ❌ MISSING]
  Service containers       workflow services          [✅ CONFIGURED | ⚠️ MISSING]
  Parallel execution       matrix strategy            [✅ CONFIGURED | ⏭️ OPTIONAL]

Overall: [X issues found]

Recommendations:
  - Install testcontainers for database testing
  - Create docker-compose.test.yml for local testing
  - Add integration test job to CI workflow
```

### Phase 4: Configuration (if --fix or user confirms)

#### JavaScript/TypeScript Setup

**Install dependencies:**
```bash
bun add --dev supertest @types/supertest
bun add --dev @testcontainers/postgresql
bun add --dev testcontainers
```

**Create `tests/integration/setup.ts`:**
```typescript
import { PostgreSqlContainer, StartedPostgreSqlContainer } from '@testcontainers/postgresql';
import { afterAll, beforeAll } from 'vitest';

let postgresContainer: StartedPostgreSqlContainer;

export async function setupTestDatabase(): Promise<string> {
  postgresContainer = await new PostgreSqlContainer('postgres:16-alpine')
    .withDatabase('test_db')
    .withUsername('test')
    .withPassword('test')
    .start();

  return postgresContainer.getConnectionUri();
}

export async function teardownTestDatabase(): Promise<void> {
  if (postgresContainer) {
    await postgresContainer.stop();
  }
}

// Global setup for all integration tests
beforeAll(async () => {
  const connectionUri = await setupTestDatabase();
  process.env.DATABASE_URL = connectionUri;
}, 60000); // 60s timeout for container startup

afterAll(async () => {
  await teardownTestDatabase();
});
```

**Create `tests/integration/api.test.ts`:**
```typescript
import { describe, it, expect, beforeAll, afterAll } from 'vitest';
import request from 'supertest';
import { app } from '../../src/app'; // Your Express/Fastify app
import './setup'; // Import container setup

describe('API Integration Tests', () => {
  describe('GET /api/users', () => {
    it('should return empty array when no users exist', async () => {
      const response = await request(app)
        .get('/api/users')
        .expect('Content-Type', /json/)
        .expect(200);

      expect(response.body).toEqual([]);
    });

    it('should return users after creation', async () => {
      // Create a user
      await request(app)
        .post('/api/users')
        .send({ name: 'Test User', email: 'test@example.com' })
        .expect(201);

      // Fetch users
      const response = await request(app)
        .get('/api/users')
        .expect(200);

      expect(response.body).toHaveLength(1);
      expect(response.body[0].name).toBe('Test User');
    });
  });

  describe('Authentication Flow', () => {
    it('should register and login user', async () => {
      // Register
      const registerResponse = await request(app)
        .post('/api/auth/register')
        .send({
          email: 'newuser@example.com',
          password: 'securepassword123',
        })
        .expect(201);

      expect(registerResponse.body).toHaveProperty('token');

      // Login
      const loginResponse = await request(app)
        .post('/api/auth/login')
        .send({
          email: 'newuser@example.com',
          password: 'securepassword123',
        })
        .expect(200);

      expect(loginResponse.body).toHaveProperty('token');
    });
  });
});
```

**Create `tests/integration/database.test.ts`:**
```typescript
import { describe, it, expect, beforeEach } from 'vitest';
import { db } from '../../src/db'; // Your database client
import './setup';

describe('Database Integration Tests', () => {
  beforeEach(async () => {
    // Clean up before each test
    await db.query('TRUNCATE users CASCADE');
  });

  it('should insert and retrieve user', async () => {
    const result = await db.query(
      'INSERT INTO users (name, email) VALUES ($1, $2) RETURNING *',
      ['Test User', 'test@example.com']
    );

    expect(result.rows[0]).toMatchObject({
      name: 'Test User',
      email: 'test@example.com',
    });

    const fetchResult = await db.query('SELECT * FROM users WHERE id = $1', [
      result.rows[0].id,
    ]);

    expect(fetchResult.rows[0].name).toBe('Test User');
  });

  it('should enforce unique email constraint', async () => {
    await db.query(
      'INSERT INTO users (name, email) VALUES ($1, $2)',
      ['User 1', 'duplicate@example.com']
    );

    await expect(
      db.query(
        'INSERT INTO users (name, email) VALUES ($1, $2)',
        ['User 2', 'duplicate@example.com']
      )
    ).rejects.toThrow(/unique constraint/i);
  });
});
```

#### Python Setup

**Install dependencies:**
```bash
uv add --group dev testcontainers httpx pytest-asyncio
```

**Update `pyproject.toml`:**
```toml
[tool.pytest.ini_options]
markers = [
    "unit: Unit tests (fast, no external dependencies)",
    "integration: Integration tests (require services/containers)",
    "e2e: End-to-end tests (full system)",
    "slow: Slow running tests",
]

# Default to running unit tests only
addopts = "-m 'not integration and not e2e'"

[tool.pytest.ini_options.integration]
# Run with: pytest -m integration
addopts = "-m integration --tb=short"
```

**Create `tests/integration/conftest.py`:**
```python
import pytest
from testcontainers.postgres import PostgresContainer
from httpx import AsyncClient
import asyncio

@pytest.fixture(scope="session")
def event_loop():
    """Create event loop for async tests."""
    loop = asyncio.get_event_loop_policy().new_event_loop()
    yield loop
    loop.close()

@pytest.fixture(scope="session")
def postgres_container():
    """Start PostgreSQL container for integration tests."""
    with PostgresContainer("postgres:16-alpine") as postgres:
        yield postgres

@pytest.fixture(scope="session")
def database_url(postgres_container):
    """Get database URL from container."""
    return postgres_container.get_connection_url()

@pytest.fixture
async def db_session(database_url):
    """Create database session with automatic cleanup."""
    from sqlalchemy.ext.asyncio import create_async_engine, AsyncSession
    from sqlalchemy.orm import sessionmaker

    # Convert to async URL
    async_url = database_url.replace("postgresql://", "postgresql+asyncpg://")
    engine = create_async_engine(async_url)

    async_session = sessionmaker(
        engine, class_=AsyncSession, expire_on_commit=False
    )

    async with async_session() as session:
        yield session
        await session.rollback()

@pytest.fixture
async def api_client(database_url):
    """Create test client for API."""
    import os
    os.environ["DATABASE_URL"] = database_url

    from app.main import app  # Your FastAPI/Flask app

    async with AsyncClient(app=app, base_url="http://test") as client:
        yield client
```

**Create `tests/integration/test_api.py`:**
```python
import pytest
from httpx import AsyncClient

pytestmark = pytest.mark.integration

@pytest.mark.asyncio
async def test_create_user(api_client: AsyncClient):
    """Test user creation through API."""
    response = await api_client.post(
        "/api/users",
        json={"name": "Test User", "email": "test@example.com"},
    )

    assert response.status_code == 201
    data = response.json()
    assert data["name"] == "Test User"
    assert "id" in data

@pytest.mark.asyncio
async def test_get_users(api_client: AsyncClient):
    """Test fetching users list."""
    # Create a user first
    await api_client.post(
        "/api/users",
        json={"name": "Test User", "email": "test@example.com"},
    )

    response = await api_client.get("/api/users")

    assert response.status_code == 200
    data = response.json()
    assert len(data) >= 1

@pytest.mark.asyncio
async def test_authentication_flow(api_client: AsyncClient):
    """Test complete auth flow: register -> login -> access protected."""
    # Register
    register_response = await api_client.post(
        "/api/auth/register",
        json={"email": "newuser@example.com", "password": "secure123"},
    )
    assert register_response.status_code == 201

    # Login
    login_response = await api_client.post(
        "/api/auth/login",
        json={"email": "newuser@example.com", "password": "secure123"},
    )
    assert login_response.status_code == 200
    token = login_response.json()["token"]

    # Access protected endpoint
    protected_response = await api_client.get(
        "/api/profile",
        headers={"Authorization": f"Bearer {token}"},
    )
    assert protected_response.status_code == 200
```

#### Docker Compose Test Configuration

**Create `docker-compose.test.yml`:**
```yaml
version: '3.8'

services:
  test-db:
    image: postgres:16-alpine
    environment:
      POSTGRES_USER: test
      POSTGRES_PASSWORD: test
      POSTGRES_DB: test_db
    ports:
      - "5433:5432"
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U test -d test_db"]
      interval: 5s
      timeout: 5s
      retries: 5
    tmpfs:
      - /var/lib/postgresql/data  # Use tmpfs for faster tests

  test-redis:
    image: redis:7-alpine
    ports:
      - "6380:6379"
    healthcheck:
      test: ["CMD", "redis-cli", "ping"]
      interval: 5s
      timeout: 5s
      retries: 5

  # Optional: Message queue for event-driven tests
  test-rabbitmq:
    image: rabbitmq:3-alpine
    ports:
      - "5673:5672"
    healthcheck:
      test: ["CMD", "rabbitmq-diagnostics", "check_running"]
      interval: 10s
      timeout: 5s
      retries: 5

networks:
  default:
    name: integration-test-network
```

**Add npm scripts to `package.json`:**
```json
{
  "scripts": {
    "test:integration": "vitest run --config vitest.integration.config.ts",
    "test:integration:watch": "vitest --config vitest.integration.config.ts",
    "test:integration:docker": "docker compose -f docker-compose.test.yml up -d && npm run test:integration && docker compose -f docker-compose.test.yml down",
    "docker:test:up": "docker compose -f docker-compose.test.yml up -d",
    "docker:test:down": "docker compose -f docker-compose.test.yml down -v"
  }
}
```

**Create `vitest.integration.config.ts`:**
```typescript
import { defineConfig } from 'vitest/config';

export default defineConfig({
  test: {
    include: ['tests/integration/**/*.test.ts'],
    setupFiles: ['tests/integration/setup.ts'],
    testTimeout: 30000, // 30s for container operations
    hookTimeout: 60000, // 60s for container startup
    pool: 'forks', // Use forks for isolation
    poolOptions: {
      forks: {
        singleFork: true, // Run sequentially to avoid port conflicts
      },
    },
    env: {
      NODE_ENV: 'test',
    },
  },
});
```

### Phase 5: CI/CD Integration

**Add to `.github/workflows/test.yml`:**

```yaml
jobs:
  unit-tests:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: oven-sh/setup-bun@v2
      - run: bun install --frozen-lockfile
      - run: bun test

  integration-tests:
    runs-on: ubuntu-latest
    needs: unit-tests  # Run after unit tests pass

    services:
      postgres:
        image: postgres:16-alpine
        env:
          POSTGRES_USER: test
          POSTGRES_PASSWORD: test
          POSTGRES_DB: test_db
        ports:
          - 5432:5432
        options: >-
          --health-cmd pg_isready
          --health-interval 10s
          --health-timeout 5s
          --health-retries 5

      redis:
        image: redis:7-alpine
        ports:
          - 6379:6379
        options: >-
          --health-cmd "redis-cli ping"
          --health-interval 10s
          --health-timeout 5s
          --health-retries 5

    steps:
      - uses: actions/checkout@v4

      - uses: oven-sh/setup-bun@v2

      - name: Install dependencies
        run: bun install --frozen-lockfile

      - name: Run database migrations
        run: bun run db:migrate
        env:
          DATABASE_URL: postgresql://test:test@localhost:5432/test_db

      - name: Run integration tests
        run: bun run test:integration
        env:
          DATABASE_URL: postgresql://test:test@localhost:5432/test_db
          REDIS_URL: redis://localhost:6379

      - name: Upload test results
        uses: actions/upload-artifact@v4
        if: always()
        with:
          name: integration-test-results
          path: test-results/
```

### Phase 6: Test Fixtures and Factories

**Create `tests/fixtures/factories.ts`:**
```typescript
import { faker } from '@faker-js/faker';

export interface UserFactory {
  name: string;
  email: string;
  password?: string;
}

export function createUserData(overrides: Partial<UserFactory> = {}): UserFactory {
  return {
    name: faker.person.fullName(),
    email: faker.internet.email(),
    password: faker.internet.password({ length: 12 }),
    ...overrides,
  };
}

export function createManyUsers(count: number, overrides: Partial<UserFactory> = {}): UserFactory[] {
  return Array.from({ length: count }, () => createUserData(overrides));
}

// Database seeding helper
export async function seedDatabase(db: any) {
  const users = createManyUsers(10);

  for (const user of users) {
    await db.query(
      'INSERT INTO users (name, email) VALUES ($1, $2)',
      [user.name, user.email]
    );
  }

  return users;
}
```

### Phase 7: Standards Tracking

Update `.fvh-standards.yaml`:

```yaml
standards_version: "2025.1"
last_configured: "[timestamp]"
components:
  integration_tests: "2025.1"
  integration_tests_framework: "[supertest|pytest|testcontainers]"
  integration_tests_containers: true
  integration_tests_ci: true
```

### Phase 8: Updated Compliance Report

```
Integration Testing Configuration Complete
===========================================

Framework: Supertest + Testcontainers
Language: TypeScript

Configuration Applied:
  ✅ supertest installed for HTTP testing
  ✅ testcontainers installed for database containers
  ✅ tests/integration/ directory created
  ✅ vitest.integration.config.ts created

Test Infrastructure:
  ✅ Container setup with PostgreSQL
  ✅ Database cleanup between tests
  ✅ Test fixtures and factories

Scripts Added:
  ✅ bun run test:integration (run tests)
  ✅ bun run test:integration:watch (watch mode)
  ✅ bun run test:integration:docker (with docker-compose)

CI/CD:
  ✅ Integration test job added to workflow
  ✅ Service containers configured
  ✅ Runs after unit tests pass

Next Steps:
  1. Start test containers:
     bun run docker:test:up

  2. Run integration tests:
     bun run test:integration

  3. Stop containers:
     bun run docker:test:down

  4. Run full suite with containers:
     bun run test:integration:docker

Documentation:
  - Supertest: https://github.com/ladjs/supertest
  - Testcontainers: https://testcontainers.com
```

## Flags

| Flag | Description |
|------|-------------|
| `--check-only` | Report status without offering fixes |
| `--fix` | Apply all fixes automatically without prompting |
| `--framework <framework>` | Override framework detection (supertest, pytest, testcontainers) |

## Examples

```bash
# Check compliance and offer fixes
/configure:integration-tests

# Check only, no modifications
/configure:integration-tests --check-only

# Auto-fix all issues
/configure:integration-tests --fix

# Force specific framework
/configure:integration-tests --fix --framework pytest
```

## Error Handling

- **No app entry point found**: Ask user to specify app location
- **Docker not available**: Warn about testcontainers requirement
- **Database type unknown**: Ask user to specify database type
- **Port conflicts**: Suggest alternative ports in docker-compose

## See Also

- `/configure:tests` - Unit testing configuration
- `/configure:api-tests` - API contract testing
- `/configure:coverage` - Coverage configuration
- `/configure:all` - Run all FVH compliance checks
- **Testcontainers documentation**: https://testcontainers.com
- **Supertest documentation**: https://github.com/ladjs/supertest
