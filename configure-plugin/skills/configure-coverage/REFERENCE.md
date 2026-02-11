# Coverage Configuration Reference

Detailed configuration templates for code coverage tools.

## Vitest Coverage Configuration

### Install Coverage Provider

```bash
npm install --save-dev @vitest/coverage-v8
# or for Istanbul
npm install --save-dev @vitest/coverage-istanbul
```

### `vitest.config.ts` Template

```typescript
import { defineConfig } from 'vitest/config';

export default defineConfig({
  test: {
    coverage: {
      provider: 'v8',

      reporter: [
        'text',           // Console output
        'json',           // JSON report for tools
        'html',           // HTML report for browsing
        'lcov',           // LCOV for CI/CD (codecov, coveralls)
      ],

      reportsDirectory: './coverage',

      thresholds: {
        lines: 80,
        functions: 80,
        branches: 80,
        statements: 80,
      },

      include: ['src/**/*.{js,ts,jsx,tsx}'],

      exclude: [
        'node_modules/',
        'dist/',
        'tests/',
        '**/*.config.*',
        '**/*.d.ts',
        '**/*.test.*',
        '**/*.spec.*',
        '**/types/',
        '**/__tests__/',
      ],

      clean: true,
      all: true,
      skipFull: false,
    },
  },
});
```

### Package.json Scripts

```json
{
  "scripts": {
    "test:coverage": "vitest run --coverage",
    "coverage:report": "open coverage/index.html",
    "coverage:check": "vitest run --coverage --reporter=json"
  }
}
```

## Jest Coverage Configuration

### `jest.config.ts` Template

```typescript
import type { Config } from 'jest';

const config: Config = {
  collectCoverage: true,
  coverageProvider: 'v8',

  collectCoverageFrom: [
    'src/**/*.{js,jsx,ts,tsx}',
    '!src/**/*.d.ts',
    '!src/**/*.stories.*',
    '!src/**/__tests__/**',
    '!src/**/types/**',
  ],

  coverageDirectory: 'coverage',

  coverageReporters: [
    'text',
    'text-summary',
    'json',
    'html',
    'lcov',
  ],

  coverageThresholds: {
    global: {
      lines: 80,
      functions: 80,
      branches: 80,
      statements: 80,
    },
    './src/critical/**/*.ts': {
      lines: 90,
      functions: 90,
      branches: 90,
      statements: 90,
    },
  },

  coveragePathIgnorePatterns: [
    '/node_modules/',
    '/dist/',
    '/tests/',
    '.config.js',
  ],
};

export default config;
```

## pytest Coverage Configuration

### Install pytest-cov

```bash
uv add --group dev pytest-cov
```

### `pyproject.toml` Template

```toml
[tool.pytest.ini_options]
addopts = [
    "-v",
    "--cov=src",
    "--cov-report=term-missing",
    "--cov-report=html",
    "--cov-report=xml",
    "--cov-report=json",
    "--cov-fail-under=80",
]

[tool.coverage.run]
source = ["src"]
branch = true
parallel = true
omit = [
    "*/tests/*",
    "*/migrations/*",
    "*/__init__.py",
    "*/config.py",
    "*/settings.py",
]

[tool.coverage.report]
precision = 2
show_missing = true
fail_under = 80

exclude_lines = [
    "pragma: no cover",
    "def __repr__",
    "def __str__",
    "if __name__ == .__main__.:",
    "raise AssertionError",
    "raise NotImplementedError",
    "if 0:",
    "if False:",
    "if TYPE_CHECKING:",
    "@abstractmethod",
    "@overload",
]

[tool.coverage.html]
directory = "coverage/html"

[tool.coverage.xml]
output = "coverage/coverage.xml"

[tool.coverage.json]
output = "coverage/coverage.json"
```

## Rust Coverage Configuration

### Install cargo-llvm-cov

```bash
cargo install cargo-llvm-cov --locked
```

### `.cargo/config.toml` Template

```toml
[alias]
coverage = "llvm-cov --html --open"
coverage-lcov = "llvm-cov --lcov --output-path lcov.info"
```

### `Cargo.toml` Coverage Metadata

```toml
[package.metadata.coverage]
exclude = [
    "tests/*",
    "benches/*",
    "examples/*",
]
```

### Run Coverage

```bash
# Generate HTML report
cargo coverage

# Generate LCOV for CI
cargo coverage-lcov
```

## CI/CD Integration

### GitHub Actions - Vitest/Jest

```yaml
- name: Run tests with coverage
  run: npm run test:coverage

- name: Upload coverage to Codecov
  uses: codecov/codecov-action@v4
  with:
    token: ${{ secrets.CODECOV_TOKEN }}
    files: ./coverage/lcov.info
    flags: unittests
    name: codecov-umbrella
    fail_ci_if_error: true

- name: Upload coverage artifacts
  uses: actions/upload-artifact@v4
  if: always()
  with:
    name: coverage-report
    path: coverage/
```

### GitHub Actions - pytest

```yaml
- name: Run tests with coverage
  run: uv run pytest --cov --cov-report=xml --cov-report=html

- name: Upload coverage to Codecov
  uses: codecov/codecov-action@v4
  with:
    token: ${{ secrets.CODECOV_TOKEN }}
    files: ./coverage/coverage.xml
    flags: unittests
    name: codecov-umbrella
    fail_ci_if_error: true

- name: Upload coverage artifacts
  uses: actions/upload-artifact@v4
  if: always()
  with:
    name: coverage-report
    path: coverage/
```

### GitHub Actions - Rust

```yaml
- name: Install cargo-llvm-cov
  uses: taiki-e/install-action@cargo-llvm-cov

- name: Generate coverage
  run: cargo llvm-cov --all-features --lcov --output-path lcov.info

- name: Upload coverage to Codecov
  uses: codecov/codecov-action@v4
  with:
    token: ${{ secrets.CODECOV_TOKEN }}
    files: ./lcov.info
    flags: unittests
    fail_ci_if_error: true
```

## Coverage Badges

**Codecov:**
```markdown
[![codecov](https://codecov.io/gh/USERNAME/REPO/branch/main/graph/badge.svg)](https://codecov.io/gh/USERNAME/REPO)
```

**Coveralls:**
```markdown
[![Coverage Status](https://coveralls.io/repos/github/USERNAME/REPO/badge.svg?branch=main)](https://coveralls.io/github/USERNAME/REPO?branch=main)
```

## Codecov Configuration

### `codecov.yml` Template

```yaml
coverage:
  status:
    project:
      default:
        target: 80%
        threshold: 1%
    patch:
      default:
        target: 80%

comment:
  layout: "reach,diff,flags,tree"
  behavior: default
  require_changes: false
```

### Codecov Setup Steps

1. Sign up at https://codecov.io
2. Add repository
3. Copy token from Codecov dashboard
4. Add secret: GitHub repo -> Settings -> Secrets -> `CODECOV_TOKEN`
5. Add upload step to workflow
