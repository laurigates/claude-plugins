# Testing Configuration Reference

## Report Template

```
Testing Framework Compliance Report
====================================
Project: [name]
Language: [TypeScript | Python | Rust]
Framework: [Vitest 2.x | pytest 8.x | cargo-nextest 0.9.x]

Configuration:
  Config file             <file>                     EXISTS/MISSING
  Test directory          <dir>                      EXISTS/NON-STANDARD
  Coverage provider       <provider>                 CONFIGURED/MISSING
  Environment             <env>                      CONFIGURED/NOT SET
  Watch exclusions        <patterns>                 CONFIGURED/INCOMPLETE

Test Organization:
  Unit tests              <pattern>                  FOUND/NONE
  Integration tests       <dir>                      FOUND/N/A
  E2E tests               <dir>                      FOUND/N/A

Scripts:
  test command            package.json scripts       CONFIGURED/MISSING
  test:watch              package.json scripts       CONFIGURED/MISSING
  test:coverage           package.json scripts       CONFIGURED/MISSING

Overall: [X issues found]

Recommendations:
  - <recommendation>
```

## Vitest Configuration

### Install Dependencies

```bash
npm install --save-dev vitest @vitest/ui @vitest/coverage-v8
# or
bun add --dev vitest @vitest/ui @vitest/coverage-v8
```

### vitest.config.ts Template

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

### Package.json Scripts

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

## Jest Configuration

### jest.config.ts Template

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

## Python pytest Configuration

### pyproject.toml Template

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

### Install Dependencies

```bash
uv add --group dev pytest pytest-cov pytest-asyncio pytest-mock
```

## Rust cargo-nextest Configuration

### Install

```bash
cargo install cargo-nextest --locked
```

### .nextest.toml Template

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

### Optional cargo alias (.cargo/config.toml)

```toml
[alias]
test = "nextest run"
```

## Test Directory Structures

### JavaScript/TypeScript

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

### Python

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

### Rust

```
tests/
├── integration_test.rs   # Integration tests
└── common/               # Shared test utilities
    └── mod.rs
```

## CI/CD Integration Templates

### JavaScript/TypeScript (Vitest)

```yaml
- name: Run tests
  run: npm test -- --reporter=junit --reporter=default --coverage

- name: Upload coverage
  uses: codecov/codecov-action@v4
  with:
    files: ./coverage/lcov.info
```

### Python (pytest)

```yaml
- name: Run tests
  run: |
    uv run pytest --junitxml=junit.xml --cov-report=xml

- name: Upload coverage
  uses: codecov/codecov-action@v4
  with:
    files: ./coverage.xml
```

### Rust (cargo-nextest)

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

## Migration Guides

### Jest to Vitest

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

### unittest to pytest (Python)

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
   - `self.assertEqual(a, b)` -> `assert a == b`
   - `self.assertTrue(x)` -> `assert x`
   - `self.assertRaises(Error)` -> `with pytest.raises(Error):`
