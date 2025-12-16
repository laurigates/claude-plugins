---
description: Check and configure testing frameworks and infrastructure
allowed-tools: Glob, Grep, Read, Write, Edit, Bash, AskUserQuestion, TodoWrite, WebSearch, WebFetch
argument-hint: "[--check-only] [--fix] [--framework <vitest|jest|pytest|nextest>]"
---

# /configure:tests

Check and configure testing frameworks against best practices (Vitest, Jest, pytest, cargo-nextest).

## Context

This command validates testing infrastructure and optionally configures or upgrades to modern frameworks.

**Modern testing stack preferences:**
- **JavaScript/TypeScript**: Vitest (preferred) or Jest
- **Python**: pytest with pytest-cov
- **Rust**: cargo-nextest for improved performance

## Version Checking

**CRITICAL**: Before flagging outdated versions, verify latest releases:

1. **Vitest**: Check [vitest.dev](https://vitest.dev/) or [GitHub releases](https://github.com/vitest-dev/vitest/releases)
2. **Jest**: Check [jestjs.io](https://jestjs.io/) or [npm](https://www.npmjs.com/package/jest)
3. **pytest**: Check [pytest.org](https://pytest.org/) or [PyPI](https://pypi.org/project/pytest/)
4. **cargo-nextest**: Check [nexte.st](https://nexte.st/) or [GitHub releases](https://github.com/nextest-rs/nextest/releases)

Use WebSearch or WebFetch to verify current versions before reporting outdated frameworks.

## Workflow

### Phase 1: Framework Detection

Detect project language and existing test framework:

| Indicator | Language | Detected Framework |
|-----------|----------|-------------------|
| `vitest.config.*` | JavaScript/TypeScript | Vitest |
| `jest.config.*` | JavaScript/TypeScript | Jest |
| `pyproject.toml` [tool.pytest] | Python | pytest |
| `pytest.ini` | Python | pytest |
| `Cargo.toml` | Rust | cargo test |
| `.nextest.toml` | Rust | cargo-nextest |

### Phase 2: Current State Analysis

For each detected framework, check configuration:

**Vitest:**
- [ ] `vitest.config.ts` or `vitest.config.js` exists
- [ ] `globals: true` configured for compatibility
- [ ] `environment` set appropriately (jsdom, happy-dom, node)
- [ ] Coverage configured with `@vitest/coverage-v8` or `@vitest/coverage-istanbul`
- [ ] Watch mode exclusions configured

**Jest:**
- [ ] `jest.config.js` or `jest.config.ts` exists
- [ ] `testEnvironment` configured
- [ ] Coverage configuration present
- [ ] Transform configured for TypeScript/JSX
- [ ] Module path aliases configured

**pytest:**
- [ ] `pyproject.toml` has `[tool.pytest.ini_options]` section
- [ ] `testpaths` configured
- [ ] `addopts` includes useful flags (`-v`, `--strict-markers`)
- [ ] `markers` defined for test categorization
- [ ] `pytest-cov` installed

**cargo-nextest:**
- [ ] `.nextest.toml` exists
- [ ] Profile configurations (default, ci)
- [ ] Retry policy configured
- [ ] Test groups defined if needed

### Phase 3: Compliance Report

Generate formatted compliance report:

```
Testing Framework Compliance Report
====================================
Project: [name]
Language: [TypeScript | Python | Rust]
Framework: [Vitest 2.x | pytest 8.x | cargo-nextest 0.9.x]

Configuration:
  Config file             vitest.config.ts           [✅ EXISTS | ❌ MISSING]
  Test directory          tests/ or __tests__/       [✅ EXISTS | ⚠️ NON-STANDARD]
  Coverage provider       @vitest/coverage-v8        [✅ CONFIGURED | ❌ MISSING]
  Environment             jsdom                      [✅ CONFIGURED | ⚠️ NOT SET]
  Watch exclusions        node_modules, dist         [✅ CONFIGURED | ⚠️ INCOMPLETE]

Test Organization:
  Unit tests              src/**/*.test.ts           [✅ FOUND | ❌ NONE]
  Integration tests       tests/integration/         [✅ FOUND | ⏭️ N/A]
  E2E tests               tests/e2e/                 [✅ FOUND | ⏭️ N/A]

Scripts:
  test command            package.json scripts       [✅ CONFIGURED | ❌ MISSING]
  test:watch              package.json scripts       [✅ CONFIGURED | ⚠️ MISSING]
  test:coverage           package.json scripts       [✅ CONFIGURED | ❌ MISSING]

Overall: [X issues found]

Recommendations:
  - Add coverage configuration with 80% threshold
  - Configure watch mode exclusions
  - Add test:ui script for Vitest UI
```

### Phase 4: Configuration (if --fix or user confirms)

#### Vitest Configuration (Recommended for JS/TS)

**Install dependencies:**
```bash
npm install --save-dev vitest @vitest/ui @vitest/coverage-v8
# or
bun add --dev vitest @vitest/ui @vitest/coverage-v8
```

**Create `vitest.config.ts`:**
```typescript
import { defineConfig } from 'vitest/config';
import { resolve } from 'path';

export default defineConfig({
  test: {
    // Enable globals for compatibility with Jest-style tests
    globals: true,

    // Test environment (jsdom for DOM testing, node for backend)
    environment: 'jsdom', // or 'node', 'happy-dom'

    // Setup files to run before tests
    setupFiles: ['./tests/setup.ts'],

    // Coverage configuration
    coverage: {
      provider: 'v8', // or 'istanbul'
      reporter: ['text', 'json', 'html', 'lcov'],
      exclude: [
        'node_modules/',
        'dist/',
        'tests/',
        '**/*.config.*',
        '**/*.d.ts',
      ],
      thresholds: {
        lines: 80,
        functions: 80,
        branches: 80,
        statements: 80,
      },
    },

    // Watch mode exclusions
    watchExclude: ['**/node_modules/**', '**/dist/**', '**/.next/**'],

    // Test timeout
    testTimeout: 10000,

    // Include/exclude patterns
    include: ['**/*.{test,spec}.{js,mjs,cjs,ts,mts,cts,jsx,tsx}'],
    exclude: ['node_modules', 'dist', '.next', 'out'],
  },

  // Resolve aliases (if using path aliases)
  resolve: {
    alias: {
      '@': resolve(__dirname, './src'),
    },
  },
});
```

**Add npm scripts to `package.json`:**
```json
{
  "scripts": {
    "test": "vitest run",
    "test:watch": "vitest",
    "test:ui": "vitest --ui",
    "test:coverage": "vitest run --coverage",
    "test:ci": "vitest run --coverage --reporter=junit --reporter=default"
  }
}
```

#### Jest Configuration (Alternative)

**Create `jest.config.ts`:**
```typescript
import type { Config } from 'jest';

const config: Config = {
  preset: 'ts-jest',
  testEnvironment: 'jsdom',
  roots: ['<rootDir>/src', '<rootDir>/tests'],
  testMatch: ['**/__tests__/**/*.ts', '**/?(*.)+(spec|test).ts'],

  transform: {
    '^.+\\.tsx?$': ['ts-jest', {
      tsconfig: 'tsconfig.json',
    }],
  },

  collectCoverageFrom: [
    'src/**/*.{js,jsx,ts,tsx}',
    '!src/**/*.d.ts',
    '!src/**/*.stories.tsx',
  ],

  coverageThresholds: {
    global: {
      lines: 80,
      functions: 80,
      branches: 80,
      statements: 80,
    },
  },

  moduleNameMapper: {
    '^@/(.*)$': '<rootDir>/src/$1',
  },

  setupFilesAfterEnv: ['<rootDir>/tests/setup.ts'],
};

export default config;
```

#### Python pytest Configuration

**Update `pyproject.toml`:**
```toml
[tool.pytest.ini_options]
testpaths = ["tests"]
python_files = ["test_*.py", "*_test.py"]
python_classes = ["Test*"]
python_functions = ["test_*"]

addopts = [
    "-v",
    "--strict-markers",
    "--strict-config",
    "--cov=src",
    "--cov-report=term-missing",
    "--cov-report=html",
    "--cov-report=xml",
    "--cov-fail-under=80",
]

markers = [
    "unit: Unit tests",
    "integration: Integration tests",
    "e2e: End-to-end tests",
    "slow: Slow running tests",
]

[tool.coverage.run]
source = ["src"]
omit = [
    "*/tests/*",
    "*/migrations/*",
    "*/__init__.py",
]

[tool.coverage.report]
exclude_lines = [
    "pragma: no cover",
    "def __repr__",
    "if __name__ == .__main__.:",
    "raise AssertionError",
    "raise NotImplementedError",
    "if 0:",
    "if False:",
    "if TYPE_CHECKING:",
]
```

**Install dependencies:**
```bash
uv add --group dev pytest pytest-cov pytest-asyncio pytest-mock
```

#### Rust cargo-nextest Configuration

**Install cargo-nextest:**
```bash
cargo install cargo-nextest --locked
```

**Create `.nextest.toml`:**
```toml
[profile.default]
retries = 0
fail-fast = false

# Run tests with all features enabled
test-threads = "num-cpus"

[profile.ci]
retries = 2
fail-fast = true
test-threads = 2

# JUnit output for CI
[profile.ci.junit]
path = "target/nextest/ci/junit.xml"

[profile.default.junit]
path = "target/nextest/default/junit.xml"
```

**Add to `.cargo/config.toml` (optional):**
```toml
[alias]
test = "nextest run"
```

### Phase 5: Test Organization

Create standard test directory structure:

**JavaScript/TypeScript:**
```
tests/
├── setup.ts              # Test setup and global mocks
├── unit/                 # Unit tests
│   └── utils.test.ts
├── integration/          # Integration tests
│   └── api.test.ts
└── e2e/                  # E2E tests
    └── user-flow.test.ts
```

**Python:**
```
tests/
├── conftest.py           # pytest fixtures and configuration
├── unit/                 # Unit tests
│   └── test_utils.py
├── integration/          # Integration tests
│   └── test_api.py
└── e2e/                  # E2E tests
    └── test_user_flow.py
```

**Rust:**
```
tests/
├── integration_test.rs   # Integration tests
└── common/               # Shared test utilities
    └── mod.rs
```

### Phase 6: CI/CD Integration

Add test commands to GitHub Actions workflow:

**JavaScript/TypeScript (Vitest):**
```yaml
- name: Run tests
  run: npm test -- --reporter=junit --reporter=default --coverage

- name: Upload coverage
  uses: codecov/codecov-action@v4
  with:
    files: ./coverage/lcov.info
```

**Python (pytest):**
```yaml
- name: Run tests
  run: |
    uv run pytest --junitxml=junit.xml --cov-report=xml

- name: Upload coverage
  uses: codecov/codecov-action@v4
  with:
    files: ./coverage.xml
```

**Rust (cargo-nextest):**
```yaml
- name: Install nextest
  uses: taiki-e/install-action@nextest

- name: Run tests
  run: cargo nextest run --profile ci --no-fail-fast

- name: Upload test results
  uses: actions/upload-artifact@v4
  with:
    name: test-results
    path: target/nextest/ci/junit.xml
```

### Phase 7: Standards Tracking

Update `.fvh-standards.yaml`:

```yaml
standards_version: "2025.1"
last_configured: "[timestamp]"
components:
  tests: "2025.1"
  tests_framework: "[vitest|jest|pytest|nextest]"
  tests_coverage_threshold: 80
  tests_ci_integrated: true
```

### Phase 8: Migration Guide (if upgrading)

**Jest → Vitest Migration:**

1. **Update dependencies:**
   ```bash
   npm uninstall jest @types/jest
   npm install --save-dev vitest @vitest/ui @vitest/coverage-v8
   ```

2. **Rename config file:**
   ```bash
   mv jest.config.ts vitest.config.ts
   ```

3. **Update test imports:**
   ```typescript
   // Before (Jest)
   import { describe, it, expect } from '@jest/globals';

   // After (Vitest with globals)
   // No import needed if globals: true in config
   ```

4. **Update package.json scripts:**
   ```json
   {
     "scripts": {
       "test": "vitest run",
       "test:watch": "vitest"
     }
   }
   ```

**unittest → pytest Migration (Python):**

1. **Install pytest:**
   ```bash
   uv add --group dev pytest pytest-cov
   ```

2. **Convert test files:**
   ```python
   # Before (unittest)
   import unittest
   class TestExample(unittest.TestCase):
       def test_something(self):
           self.assertEqual(1, 1)

   # After (pytest)
   def test_something():
       assert 1 == 1
   ```

3. **Convert assertions:**
   - `self.assertEqual(a, b)` → `assert a == b`
   - `self.assertTrue(x)` → `assert x`
   - `self.assertRaises(Error)` → `with pytest.raises(Error):`

### Phase 9: Updated Compliance Report

```
Testing Configuration Complete
===============================

Framework: Vitest 2.x (preferred)
Language: TypeScript

Configuration Applied:
  ✅ vitest.config.ts created with best practices
  ✅ Coverage provider configured (@vitest/coverage-v8)
  ✅ Test environment set (jsdom)
  ✅ Watch exclusions configured
  ✅ Coverage thresholds set (80%)

Scripts Added:
  ✅ npm test (run tests once)
  ✅ npm run test:watch (watch mode)
  ✅ npm run test:ui (Vitest UI)
  ✅ npm run test:coverage (with coverage report)

Test Structure:
  ✅ tests/ directory created
  ✅ setup.ts configured
  ✅ Example tests added

Next Steps:
  1. Write your first test:
     npm run test:watch

  2. View test UI:
     npm run test:ui

  3. Check coverage:
     npm run test:coverage

  4. Verify CI integration:
     Check .github/workflows/ for test job

Documentation: docs/TESTING.md
```

## Flags

| Flag | Description |
|------|-------------|
| `--check-only` | Report status without offering fixes |
| `--fix` | Apply all fixes automatically without prompting |
| `--framework <framework>` | Override framework detection (vitest, jest, pytest, nextest) |

## Examples

```bash
# Check compliance and offer fixes
/configure:tests

# Check only, no modifications
/configure:tests --check-only

# Auto-fix all issues
/configure:tests --fix

# Force Vitest even if Jest is detected
/configure:tests --framework vitest
```

## Error Handling

- **No package.json found**: Cannot configure JS/TS tests, skip or error
- **Conflicting frameworks**: Warn about multiple test configs, require manual resolution
- **Missing dependencies**: Offer to install required packages
- **Invalid config syntax**: Report parse error, offer to replace with template

## See Also

- `/configure:coverage` - Configure coverage thresholds and reporting
- `/configure:all` - Run all FVH compliance checks
- `/test:run` - Universal test runner
- `/test:setup` - Comprehensive testing infrastructure setup
- **Vitest documentation**: https://vitest.dev
- **pytest documentation**: https://docs.pytest.org
- **cargo-nextest documentation**: https://nexte.st
