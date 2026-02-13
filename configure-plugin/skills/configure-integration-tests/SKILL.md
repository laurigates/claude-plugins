---
model: haiku
created: 2025-12-16
modified: 2026-02-11
reviewed: 2025-12-16
description: Check and configure integration testing for services, databases, and external dependencies
allowed-tools: Glob, Grep, Read, Write, Edit, Bash, AskUserQuestion, TodoWrite
argument-hint: "[--check-only] [--fix] [--framework <supertest|pytest|testcontainers>]"
name: configure-integration-tests
---

# /configure:integration-tests

Check and configure integration testing infrastructure for testing service interactions, databases, and external dependencies.

## When to Use This Skill

| Use this skill when... | Use another approach when... |
|------------------------|------------------------------|
| Setting up integration testing infrastructure with Supertest, pytest, or Testcontainers | Writing individual integration test cases for specific endpoints |
| Creating docker-compose.test.yml for local test service containers | Running existing integration tests (`bun test`, `pytest -m integration`) |
| Auditing integration test setup for completeness (fixtures, factories, CI) | Configuring unit test runners (`/configure:tests` instead) |
| Adding integration test jobs to GitHub Actions with service containers | Debugging a specific failing integration test |
| Separating integration tests from unit tests in project structure | Setting up API contract testing (`/configure:api-tests` instead) |

## Context

- Project root: !`pwd`
- Package files: !`find . -maxdepth 1 \( -name 'package.json' -o -name 'pyproject.toml' -o -name 'Cargo.toml' -o -name 'go.mod' \) 2>/dev/null`
- Integration tests dir: !`find tests -maxdepth 1 -type d -name 'integration' 2>/dev/null`
- Docker compose test: !`find . -maxdepth 1 -name 'docker-compose.test.yml' 2>/dev/null`
- Vitest integration config: !`find . -maxdepth 1 -name 'vitest.integration.config.*' 2>/dev/null`
- Supertest dep: !`grep -l 'supertest' package.json 2>/dev/null`
- Testcontainers dep: !`grep -l 'testcontainers' package.json pyproject.toml 2>/dev/null`
- Project standards: !`find . -maxdepth 1 -name '.project-standards.yaml' 2>/dev/null`

## Parameters

Parse from command arguments:

- `--check-only`: Report compliance status without modifications (CI/CD mode)
- `--fix`: Apply fixes automatically without prompting
- `--framework <supertest|pytest|testcontainers>`: Override framework detection

**Integration Testing Stacks:**
- **JavaScript/TypeScript**: Supertest + Testcontainers
- **Python**: pytest + testcontainers-python + httpx
- **Rust**: cargo test with `#[ignore]` + testcontainers-rs
- **Go**: testing + testcontainers-go

**Key Difference from Unit Tests:**
- Integration tests interact with **real** databases, APIs, and services
- They test **component boundaries** and **data flow**
- They typically require **test fixtures** and **cleanup**

## Execution

Execute this integration testing compliance check:

### Step 1: Detect existing integration testing infrastructure

Check for these indicators:

| Indicator | Component | Status |
|-----------|-----------|--------|
| `tests/integration/` directory | Integration tests | Present |
| `testcontainers` in dependencies | Container testing | Configured |
| `supertest` in package.json | HTTP testing | Configured |
| `docker-compose.test.yml` | Test services | Present |
| `pytest.ini` with `integration` marker | pytest integration | Configured |

### Step 2: Analyze current state

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
- [ ] Network isolation configured

### Step 3: Generate compliance report

Print a formatted compliance report:

```
Integration Testing Compliance Report
======================================
Project: [name]
Language: [TypeScript | Python | Rust | Go]

Test Organization:
  Integration directory    tests/integration/         [EXISTS | MISSING]
  Separated from unit      not in src/                [CORRECT | MIXED]
  Test fixtures            tests/fixtures/            [EXISTS | MISSING]
  Database seeds           tests/seeds/               [EXISTS | N/A]

Framework Setup:
  HTTP testing             supertest/httpx            [INSTALLED | MISSING]
  Container testing        testcontainers             [INSTALLED | MISSING]
  Async support            pytest-asyncio             [INSTALLED | N/A]

Infrastructure:
  docker-compose.test.yml  test services              [EXISTS | MISSING]
  Test database            PostgreSQL/SQLite          [CONFIGURED | MISSING]
  Service isolation        network config             [CONFIGURED | MISSING]

CI/CD Integration:
  Integration test job     GitHub Actions             [CONFIGURED | MISSING]
  Service containers       workflow services          [CONFIGURED | MISSING]

Overall: [X issues found]

Recommendations:
  - Install testcontainers for database testing
  - Create docker-compose.test.yml for local testing
  - Add integration test job to CI workflow
```

If `--check-only`, stop here.

### Step 4: Configure integration testing (if --fix or user confirms)

Apply configuration based on detected project type. Use templates from [REFERENCE.md](REFERENCE.md):

1. **Install dependencies** (supertest, testcontainers, etc.)
2. **Create test directory** (`tests/integration/`) with setup files
3. **Create sample tests** for API endpoints and database operations
4. **Create Vitest integration config** (JS/TS) or pytest markers (Python)
5. **Add scripts** to package.json or create run commands

### Step 5: Create container infrastructure

Create `docker-compose.test.yml` with:
- PostgreSQL test database (tmpfs for speed)
- Redis test instance (if needed)
- Network isolation

Add corresponding npm/bun scripts for managing test containers. Use templates from [REFERENCE.md](REFERENCE.md).

### Step 6: Configure CI/CD integration

Add integration test job to `.github/workflows/test.yml` with:
- Service containers (postgres, redis)
- Database migration step
- Integration test execution
- Artifact upload for test results

Use the CI workflow template from [REFERENCE.md](REFERENCE.md).

### Step 7: Create test fixtures and factories

Create `tests/fixtures/factories.ts` (or Python equivalent) with:
- Data factory functions using faker
- Database seeding helpers
- Cleanup utilities

Use factory templates from [REFERENCE.md](REFERENCE.md).

### Step 8: Update standards tracking

Update `.project-standards.yaml`:

```yaml
standards_version: "2025.1"
last_configured: "[timestamp]"
components:
  integration_tests: "2025.1"
  integration_tests_framework: "[supertest|pytest|testcontainers]"
  integration_tests_containers: true
  integration_tests_ci: true
```

### Step 9: Print final report

Print a summary of changes applied, scripts added, and next steps for running integration tests.

For detailed templates and code examples, see [REFERENCE.md](REFERENCE.md).

## Agentic Optimizations

| Context | Command |
|---------|---------|
| Quick compliance check | `/configure:integration-tests --check-only` |
| Auto-fix all issues | `/configure:integration-tests --fix` |
| Run integration tests (JS) | `bun test tests/integration --dots --bail=1` |
| Run integration tests (Python) | `pytest -m integration -x -q` |
| Start test containers | `docker compose -f docker-compose.test.yml up -d` |
| Check container health | `docker compose -f docker-compose.test.yml ps --format json | jq -c '.[] | {Name, State}'` |

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
- `/configure:all` - Run all compliance checks
- **Testcontainers documentation**: https://testcontainers.com
- **Supertest documentation**: https://github.com/ladjs/supertest
