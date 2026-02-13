---
model: haiku
created: 2025-12-16
modified: 2026-02-11
reviewed: 2025-12-16
description: Check and configure API contract testing with Pact, OpenAPI validation, and schema testing
allowed-tools: Glob, Grep, Read, Write, Edit, Bash, AskUserQuestion, TodoWrite
argument-hint: "[--check-only] [--fix] [--type <pact|openapi|schema>]"
name: configure-api-tests
---

# /configure:api-tests

Check and configure API contract testing infrastructure for validating API contracts, schemas, and consumer-provider agreements.

## When to Use This Skill

| Use this skill when... | Use another approach when... |
|------------------------|------------------------------|
| Setting up Pact consumer/provider contract tests | Writing individual unit tests (`/configure:tests`) |
| Configuring OpenAPI request/response validation | Validating a single API endpoint manually |
| Adding JSON Schema or Zod schema testing | Checking general test coverage (`/configure:coverage`) |
| Detecting breaking API changes in CI | Reviewing API design decisions (code-review agent) |
| Auditing API testing compliance across a project | Configuring general CI/CD workflows (`/configure:workflows`) |

## Context

- Project root: !`pwd`
- Package files: !`find . -maxdepth 1 \( -name 'package.json' -o -name 'pyproject.toml' \) 2>/dev/null`
- Pact deps: !`grep -l 'pact' package.json pyproject.toml 2>/dev/null`
- OpenAPI spec: !`find . -maxdepth 1 \( -name 'openapi.yaml' -o -name 'openapi.json' -o -name 'swagger.json' \) 2>/dev/null`
- Pact dir: !`find . -maxdepth 1 -type d -name 'pacts' 2>/dev/null`
- Contract tests: !`find tests -maxdepth 2 -type d -name 'contract' 2>/dev/null`
- Project standards: !`find . -maxdepth 1 -name '.project-standards.yaml' 2>/dev/null`

## Parameters

Parse from command arguments:

- `--check-only`: Report compliance status without modifications (CI/CD mode)
- `--fix`: Apply fixes automatically without prompting
- `--type <pact|openapi|schema>`: Focus on specific type

**API Testing Types:**

| Type | Use Case |
|------|----------|
| Pact | Microservices, multiple consumers, breaking change detection |
| OpenAPI | API-first development, documentation-driven testing |
| Schema | Simple validation, GraphQL APIs, single service |

## Execution

Execute this API testing compliance check:

### Step 1: Detect existing API testing infrastructure

Check for these indicators:

| Indicator | Component | Status |
|-----------|-----------|--------|
| `pact` in dependencies | Pact contract testing | Installed |
| `openapi.yaml` or `swagger.json` | OpenAPI specification | Present |
| `@apidevtools/swagger-parser` | OpenAPI validation | Configured |
| `ajv` in dependencies | JSON Schema validation | Configured |
| `pacts/` directory | Pact contracts | Present |

### Step 2: Analyze current state

For each detected component, check completeness:

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

### Step 3: Generate compliance report

Print a formatted compliance report:

```
API Testing Compliance Report
==============================
Project: [name]
API Type: [REST | GraphQL | gRPC]

Contract Testing (Pact):
  @pact-foundation/pact    package.json               [INSTALLED | MISSING]
  Consumer tests           tests/contract/consumer/   [FOUND | NONE]
  Provider tests           tests/contract/provider/   [FOUND | NONE]
  Pact Broker              CI configuration           [CONFIGURED | OPTIONAL]
  can-i-deploy             CI gate                    [CONFIGURED | OPTIONAL]

OpenAPI Validation:
  OpenAPI spec             openapi.yaml               [EXISTS | MISSING]
  Spec version             OpenAPI 3.1                [CURRENT | OUTDATED]
  Request validation       middleware                 [CONFIGURED | MISSING]
  Response validation      test helpers               [CONFIGURED | MISSING]
  Breaking change CI       oasdiff                    [CONFIGURED | OPTIONAL]

Schema Testing:
  JSON Schemas             schemas/                   [EXISTS | N/A]
  Schema validator         ajv/zod                    [INSTALLED | MISSING]
  Response validation      test helpers               [CONFIGURED | MISSING]

Overall: [X issues found]

Recommendations:
  - Add Pact consumer tests for service dependencies
  - Configure OpenAPI response validation in tests
  - Add breaking change detection to CI
```

If `--check-only`, stop here.

### Step 4: Configure API testing (if --fix or user confirms)

Apply fixes based on detected project type. Use templates from [REFERENCE.md](REFERENCE.md) for:

1. **Pact Contract Testing** - Install dependencies and create consumer/provider test files
2. **OpenAPI Validation** - Install validator and create test helpers
3. **Schema Testing with Zod** - Install Zod and create schema definitions
4. **Breaking Change Detection** - Install oasdiff and add CI check

For JavaScript/TypeScript projects, install with `bun add --dev`. For Python, install with `uv add --group dev`.

### Step 5: Configure CI/CD integration

Create `.github/workflows/api-tests.yml` with jobs for:
- Consumer contract tests
- Provider verification (with service containers if needed)
- OpenAPI spec validation
- Breaking change detection on PRs

Add npm/bun scripts to `package.json` for local testing. Use workflow templates from [REFERENCE.md](REFERENCE.md).

### Step 6: Update standards tracking

Update `.project-standards.yaml`:

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

### Step 7: Print final report

Print a summary of all changes applied, scripts added, and next steps for the user to verify the configuration.

For detailed templates and code examples, see [REFERENCE.md](REFERENCE.md).

## Agentic Optimizations

| Context | Command |
|---------|---------|
| Quick compliance check | `/configure:api-tests --check-only` |
| Auto-fix all issues | `/configure:api-tests --fix` |
| Pact contracts only | `/configure:api-tests --fix --type pact` |
| OpenAPI validation only | `/configure:api-tests --fix --type openapi` |
| Schema testing only | `/configure:api-tests --fix --type schema` |

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
- `/configure:all` - Run all compliance checks
- **Pact documentation**: https://docs.pact.io
- **OpenAPI specification**: https://swagger.io/specification
- **Zod documentation**: https://zod.dev
