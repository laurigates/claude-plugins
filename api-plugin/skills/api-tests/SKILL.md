---
model: opus
created: 2025-12-16
modified: 2026-02-11
reviewed: 2025-12-16
description: Check and configure API contract testing with Pact, OpenAPI validation, and schema testing
allowed-tools: Glob, Grep, Read, Write, Edit, Bash(curl *), Bash(http *), Bash(jq *), AskUserQuestion, TodoWrite
argument-hint: "[--check-only] [--fix] [--type <pact|openapi|schema>]"
name: api-tests
---

# /configure:api-tests

Check and configure API contract testing infrastructure for validating API contracts, schemas, and consumer-provider agreements.

## When to Use This Skill

| Use this skill when... | Use another approach when... |
|------------------------|------------------------------|
| Setting up API contract testing (Pact, OpenAPI, schema) | Running existing API tests (use `bun test` or test runner directly) |
| Validating OpenAPI specification compliance | Editing OpenAPI spec content (use editor directly) |
| Adding breaking change detection to CI | General CI workflow setup (use `/configure:workflows`) |
| Checking API testing infrastructure status | Unit or integration test setup (use `/configure:tests` or `/configure:integration-tests`) |
| Configuring Pact consumer/provider workflows | Debugging specific API endpoint failures (use test runner with verbose output) |

## Context

- Package manager: !`test -f bun.lockb && echo "bun" || (test -f package-lock.json && echo "npm") || (test -f yarn.lock && echo "yarn") || echo "unknown"`
- Project language: !`test -f tsconfig.json && echo "TypeScript" || (test -f pyproject.toml && echo "Python") || (test -f package.json && echo "JavaScript") || echo "unknown"`
- Pact installed: !`grep -l "pact-foundation/pact\|pact-python" package.json requirements*.txt pyproject.toml 2>/dev/null`
- OpenAPI spec: !`find . -maxdepth 2 \( -name 'openapi.yaml' -o -name 'openapi.yml' -o -name 'openapi.json' -o -name 'swagger.json' -o -name 'swagger.yaml' \) 2>/dev/null`
- Schema validator: !`grep -l '"ajv"\|"zod"' package.json 2>/dev/null`
- OpenAPI validation lib: !`grep -l "swagger-parser\|@apidevtools" package.json 2>/dev/null`
- Pact contracts dir: !`test -d pacts && echo "EXISTS" || echo "MISSING"`
- Contract tests: !`find . -maxdepth 3 -type d -name 'contract' 2>/dev/null`
- API test files: !`find . -maxdepth 4 \( -name '*.pact.*' -o -name '*.openapi.*' -o -name '*.contract.*' \) 2>/dev/null`
- CI workflows: !`find .github/workflows -maxdepth 1 \( -name '*api*' -o -name '*contract*' -o -name '*pact*' \) 2>/dev/null`

## Parameters

Parse `$ARGUMENTS` for these flags:

| Flag | Description | Default |
|------|-------------|---------|
| `--check-only` | Report status without making changes | Off |
| `--fix` | Apply all fixes automatically without prompting | Off |
| `--type <type>` | Focus on specific type: `pact`, `openapi`, or `schema` | All types |

**API Testing Types:**

| Type | Use Case |
|------|----------|
| Pact | Microservices, multiple consumers, breaking change detection |
| OpenAPI | API-first development, documentation-driven testing |
| Schema | Simple validation, GraphQL APIs, single service |

## Execution

Execute this API testing compliance check:

### Step 1: Detect project infrastructure

Scan the project for existing API testing indicators:

| Indicator | Component | Check |
|-----------|-----------|-------|
| `pact` in dependencies | Pact contract testing | `package.json` or `pyproject.toml` |
| `openapi.yaml` or `swagger.json` | OpenAPI specification | Root or `docs/` directory |
| `@apidevtools/swagger-parser` | OpenAPI validation | `package.json` devDependencies |
| `ajv` or `zod` in dependencies | Schema validation | `package.json` dependencies |
| `pacts/` directory | Pact contracts | Project root |

If `--type` is specified, only check the relevant component.

### Step 2: Analyze current state

Check completeness of each API testing component:

**Contract Testing (Pact):**
1. Check if `@pact-foundation/pact` (JS/TS) or `pact-python` (Python) is installed
2. Look for consumer tests in `tests/contract/consumer/`
3. Look for provider verification in `tests/contract/provider/`
4. Check for Pact Broker configuration in CI files
5. Check for `can-i-deploy` CI gate

**OpenAPI Validation:**
1. Verify OpenAPI specification file exists and is valid
2. Check for request validation middleware
3. Check for response validation in tests
4. Look for breaking change detection (oasdiff)

**Schema Testing:**
1. Check for JSON Schema or Zod definitions
2. Verify validator is installed (`ajv` or `zod`)
3. Look for response validation test helpers

### Step 3: Generate compliance report

Print a formatted compliance report:

```
API Testing Compliance Report
==============================
Project: [name]
API Type: [REST | GraphQL | gRPC]

Contract Testing (Pact):
  Package:                   [INSTALLED | MISSING]
  Consumer tests:            [FOUND | NONE]
  Provider tests:            [FOUND | NONE]
  Pact Broker:               [CONFIGURED | OPTIONAL]

OpenAPI Validation:
  OpenAPI spec:              [EXISTS | MISSING]
  Spec version:              [CURRENT | OUTDATED]
  Request validation:        [CONFIGURED | MISSING]
  Response validation:       [CONFIGURED | MISSING]
  Breaking change CI:        [CONFIGURED | OPTIONAL]

Schema Testing:
  JSON Schemas:              [EXISTS | N/A]
  Schema validator:          [INSTALLED | MISSING]
  Response validation:       [CONFIGURED | MISSING]

Overall: [X issues found]
Recommendations: [list specific actions]
```

If `--check-only` is set, stop here.

### Step 4: Apply configuration

If `--fix` is set or user confirms, apply fixes for missing components. Use the project language detected in Context to select TypeScript or Python templates.

For each missing component, create the appropriate files using templates from [REFERENCE.md](REFERENCE.md):

1. **Pact Contract Testing**: Install dependencies, create consumer test template, create provider verification template
2. **OpenAPI Validation**: Install validation libraries, create OpenAPI validator helper, create compliance tests
3. **Schema Testing (Zod)**: Install Zod, create schema definitions, create schema validation tests
4. **OpenAPI Breaking Change Detection**: Install oasdiff, add CI step

### Step 5: Configure CI/CD integration

Create or update `.github/workflows/api-tests.yml` with jobs for:
1. Consumer contract tests
2. Provider verification (with database service if needed)
3. OpenAPI spec validation and breaking change detection
4. Pact artifact publishing (main branch only)

Add test scripts to `package.json`. Use CI workflow template from [REFERENCE.md](REFERENCE.md).

### Step 6: Update standards tracking

Update `.project-standards.yaml` with API testing configuration:

```yaml
components:
  api_tests: "2025.1"
  api_tests_contract: "[pact|none]"
  api_tests_openapi: true
  api_tests_schema: "[zod|ajv|none]"
  api_tests_breaking_change_ci: true
```

### Step 7: Generate final report

Print a summary of all changes applied including:
- Configuration files created
- Dependencies installed
- Test commands available (with exact `bun run` / `npm run` commands)
- CI/CD jobs configured
- Recommended next steps for verification

## Agentic Optimizations

| Context | Command |
|---------|---------|
| Quick status check | `/configure:api-tests --check-only` |
| Auto-fix all issues | `/configure:api-tests --fix` |
| Pact-only setup | `/configure:api-tests --fix --type pact` |
| OpenAPI-only setup | `/configure:api-tests --fix --type openapi` |
| Check for OpenAPI spec | `find . -maxdepth 2 \( -name 'openapi.yaml' -o -name 'swagger.json' \) 2>/dev/null` |
| Check Pact installed | `grep -l "pact-foundation" package.json 2>/dev/null` |

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

| Error | Resolution |
|-------|------------|
| No OpenAPI spec found | Offer to create template |
| Pact version mismatch | Suggest upgrade path |
| Schema validation fails | Report specific errors |
| Pact Broker not configured | Provide setup instructions |

## See Also

- `/configure:tests` - Unit testing configuration
- `/configure:integration-tests` - Integration testing
- `/configure:all` - Run all compliance checks
- [Pact documentation](https://docs.pact.io)
- [OpenAPI specification](https://swagger.io/specification)
- [Zod documentation](https://zod.dev)
