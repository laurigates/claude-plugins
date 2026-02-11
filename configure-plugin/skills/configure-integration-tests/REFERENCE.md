# Integration Tests Reference

Configuration templates and code examples for integration testing.

## JavaScript/TypeScript Setup

### Install Dependencies

```bash
bun add --dev supertest @types/supertest
bun add --dev @testcontainers/postgresql
bun add --dev testcontainers
```

### Container Setup (`tests/integration/setup.ts`)

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

### API Test (`tests/integration/api.test.ts`)

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
      await request(app)
        .post('/api/users')
        .send({ name: 'Test User', email: 'test@example.com' })
        .expect(201);

      const response = await request(app)
        .get('/api/users')
        .expect(200);

      expect(response.body).toHaveLength(1);
      expect(response.body[0].name).toBe('Test User');
    });
  });

  describe('Authentication Flow', () => {
    it('should register and login user', async () => {
      const registerResponse = await request(app)
        .post('/api/auth/register')
        .send({
          email: 'newuser@example.com',
          password: 'securepassword123',
        })
        .expect(201);

      expect(registerResponse.body).toHaveProperty('token');

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

### Database Test (`tests/integration/database.test.ts`)

```typescript
import { describe, it, expect, beforeEach } from 'vitest';
import { db } from '../../src/db'; // Your database client
import './setup';

describe('Database Integration Tests', () => {
  beforeEach(async () => {
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

### Vitest Integration Config (`vitest.integration.config.ts`)

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

### Package.json Scripts

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

## Python Setup

### Install Dependencies

```bash
uv add --group dev testcontainers httpx pytest-asyncio
```

### pytest Configuration (`pyproject.toml`)

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
```

### conftest.py (`tests/integration/conftest.py`)

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

### API Test (`tests/integration/test_api.py`)

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
    register_response = await api_client.post(
        "/api/auth/register",
        json={"email": "newuser@example.com", "password": "secure123"},
    )
    assert register_response.status_code == 201

    login_response = await api_client.post(
        "/api/auth/login",
        json={"email": "newuser@example.com", "password": "secure123"},
    )
    assert login_response.status_code == 200
    token = login_response.json()["token"]

    protected_response = await api_client.get(
        "/api/profile",
        headers={"Authorization": f"Bearer {token}"},
    )
    assert protected_response.status_code == 200
```

## Docker Compose Test Configuration

### `docker-compose.test.yml`

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

## CI/CD Workflow Template

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

## Test Fixtures and Factories

### `tests/fixtures/factories.ts`

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
