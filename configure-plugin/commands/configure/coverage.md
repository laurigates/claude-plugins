---
description: Check and configure code coverage thresholds and reporting
allowed-tools: Glob, Grep, Read, Write, Edit, Bash, AskUserQuestion, TodoWrite, WebSearch, WebFetch
argument-hint: "[--check-only] [--fix] [--threshold <percentage>]"
---

# /configure:coverage

Check and configure code coverage thresholds and reporting for test frameworks.

## Context

This command validates coverage configuration and sets up reporting for CI/CD integration.

**Default threshold**: 80% (lines, branches, functions, statements)

**Supported frameworks:**
- **Vitest**: `@vitest/coverage-v8` or `@vitest/coverage-istanbul`
- **Jest**: Built-in coverage with `--coverage`
- **pytest**: `pytest-cov` plugin
- **Rust**: `cargo-llvm-cov` or `cargo-tarpaulin`

## Version Checking

**CRITICAL**: Before configuring coverage tools, verify latest versions:

1. **@vitest/coverage-v8**: Check [npm](https://www.npmjs.com/package/@vitest/coverage-v8)
2. **pytest-cov**: Check [PyPI](https://pypi.org/project/pytest-cov/)
3. **cargo-llvm-cov**: Check [crates.io](https://crates.io/crates/cargo-llvm-cov)
4. **codecov**: Check [GitHub releases](https://github.com/codecov/codecov-action/releases)

Use WebSearch or WebFetch to verify current versions before configuring coverage tools.

## Workflow

### Phase 1: Framework Detection

Detect test framework and coverage configuration:

| Indicator | Framework | Coverage Tool |
|-----------|-----------|---------------|
| `vitest.config.*` with coverage | Vitest | @vitest/coverage-v8 |
| `jest.config.*` with coverage | Jest | Built-in |
| `pyproject.toml` [tool.coverage] | pytest | pytest-cov |
| `.cargo/config.toml` with coverage | Rust | cargo-llvm-cov |

### Phase 2: Current State Analysis

For each detected framework, check coverage configuration:

**Vitest:**
- [ ] Coverage provider configured (`v8` or `istanbul`)
- [ ] Coverage reporters configured (`text`, `json`, `html`, `lcov`)
- [ ] Thresholds set for lines, functions, branches, statements
- [ ] Exclusions configured (node_modules, dist, tests, config files)
- [ ] Output directory specified

**Jest:**
- [ ] `collectCoverage` enabled
- [ ] `coverageProvider` set (`v8` or `babel`)
- [ ] `collectCoverageFrom` patterns configured
- [ ] `coverageThresholds` configured
- [ ] `coverageDirectory` specified
- [ ] `coverageReporters` configured

**pytest:**
- [ ] `pytest-cov` installed
- [ ] `[tool.coverage.run]` section exists
- [ ] `[tool.coverage.report]` section exists
- [ ] Coverage threshold configured (`--cov-fail-under`)
- [ ] Source directories specified
- [ ] Exclusions configured

**Rust (cargo-llvm-cov):**
- [ ] `cargo-llvm-cov` installed
- [ ] Coverage configuration in workspace
- [ ] HTML/LCOV output configured
- [ ] Exclusions configured

### Phase 3: Compliance Report

Generate formatted compliance report:

```
Code Coverage Compliance Report
================================
Project: [name]
Framework: [Vitest 2.x | pytest 8.x | cargo-llvm-cov 0.6.x]

Coverage Configuration:
  Provider                @vitest/coverage-v8        [✅ CONFIGURED | ❌ MISSING]
  Reporters               text, json, html, lcov     [✅ ALL | ⚠️ PARTIAL]
  Output directory        coverage/                  [✅ CONFIGURED | ⚠️ DEFAULT]
  Exclusions              node_modules, dist, tests  [✅ CONFIGURED | ⚠️ INCOMPLETE]

Thresholds:
  Lines                   80%                        [✅ PASS | ⚠️ LOW | ❌ NOT SET]
  Branches                80%                        [✅ PASS | ⚠️ LOW | ❌ NOT SET]
  Functions               80%                        [✅ PASS | ⚠️ LOW | ❌ NOT SET]
  Statements              80%                        [✅ PASS | ⚠️ LOW | ❌ NOT SET]

Current Coverage (if available):
  Lines                   85%                        [✅ ABOVE THRESHOLD]
  Branches                78%                        [⚠️ BELOW THRESHOLD]
  Functions               92%                        [✅ ABOVE THRESHOLD]
  Statements              85%                        [✅ ABOVE THRESHOLD]

CI/CD Integration:
  Coverage upload         codecov/coveralls          [✅ CONFIGURED | ❌ MISSING]
  Artifact upload         coverage reports           [✅ CONFIGURED | ⚠️ MISSING]

Overall: [X issues found]

Recommendations:
  - Increase branch coverage to meet 80% threshold
  - Add lcov reporter for better CI integration
  - Configure coverage upload to codecov
```

### Phase 4: Configuration (if --fix or user confirms)

#### Vitest Coverage Configuration

**Install coverage provider:**
```bash
npm install --save-dev @vitest/coverage-v8
# or for Istanbul
npm install --save-dev @vitest/coverage-istanbul
```

**Update `vitest.config.ts`:**
```typescript
import { defineConfig } from 'vitest/config';

export default defineConfig({
  test: {
    coverage: {
      // Provider: v8 (faster) or istanbul (more accurate)
      provider: 'v8',

      // Reporters
      reporter: [
        'text',           // Console output
        'json',           // JSON report for tools
        'html',           // HTML report for browsing
        'lcov',           // LCOV for CI/CD (codecov, coveralls)
      ],

      // Output directory
      reportsDirectory: './coverage',

      // Thresholds (fail tests if below)
      thresholds: {
        lines: 80,
        functions: 80,
        branches: 80,
        statements: 80,
      },

      // Files to include in coverage
      include: ['src/**/*.{js,ts,jsx,tsx}'],

      // Files to exclude
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

      // Clean coverage directory before running
      clean: true,

      // All files should be shown, even if not tested
      all: true,

      // Skip full coverage check (use thresholds instead)
      skipFull: false,
    },
  },
});
```

**Add coverage scripts to `package.json`:**
```json
{
  "scripts": {
    "test:coverage": "vitest run --coverage",
    "coverage:report": "open coverage/index.html",
    "coverage:check": "vitest run --coverage --reporter=json"
  }
}
```

#### Jest Coverage Configuration

**Update `jest.config.ts`:**
```typescript
import type { Config } from 'jest';

const config: Config = {
  // Enable coverage collection
  collectCoverage: true,

  // Coverage provider (v8 is faster, babel is more compatible)
  coverageProvider: 'v8',

  // Files to collect coverage from
  collectCoverageFrom: [
    'src/**/*.{js,jsx,ts,tsx}',
    '!src/**/*.d.ts',
    '!src/**/*.stories.*',
    '!src/**/__tests__/**',
    '!src/**/types/**',
  ],

  // Coverage directory
  coverageDirectory: 'coverage',

  // Coverage reporters
  coverageReporters: [
    'text',
    'text-summary',
    'json',
    'html',
    'lcov',
  ],

  // Coverage thresholds
  coverageThresholds: {
    global: {
      lines: 80,
      functions: 80,
      branches: 80,
      statements: 80,
    },
    // Per-file thresholds
    './src/critical/**/*.ts': {
      lines: 90,
      functions: 90,
      branches: 90,
      statements: 90,
    },
  },

  // Path patterns to skip for coverage
  coveragePathIgnorePatterns: [
    '/node_modules/',
    '/dist/',
    '/tests/',
    '.config.js',
  ],
};

export default config;
```

#### pytest Coverage Configuration

**Install pytest-cov:**
```bash
uv add --group dev pytest-cov
```

**Update `pyproject.toml`:**
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
# Precision for coverage percentage
precision = 2

# Show missing line numbers
show_missing = true

# Fail if below threshold
fail_under = 80

# Lines to exclude from coverage
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

#### Rust Coverage Configuration

**Install cargo-llvm-cov:**
```bash
cargo install cargo-llvm-cov --locked
```

**Create `.cargo/config.toml`:**
```toml
[alias]
coverage = "llvm-cov --html --open"
coverage-lcov = "llvm-cov --lcov --output-path lcov.info"
```

**Add to `Cargo.toml`:**
```toml
[package.metadata.coverage]
# Exclude files from coverage
exclude = [
    "tests/*",
    "benches/*",
    "examples/*",
]
```

**Run coverage:**
```bash
# Generate HTML report
cargo coverage

# Generate LCOV for CI
cargo coverage-lcov
```

### Phase 5: CI/CD Integration

#### GitHub Actions - Vitest/Jest

**Add to workflow:**
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

#### GitHub Actions - pytest

**Add to workflow:**
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

#### GitHub Actions - Rust

**Add to workflow:**
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

### Phase 6: Coverage Badges

**Add to README.md:**

**Codecov:**
```markdown
[![codecov](https://codecov.io/gh/USERNAME/REPO/branch/main/graph/badge.svg)](https://codecov.io/gh/USERNAME/REPO)
```

**Coveralls:**
```markdown
[![Coverage Status](https://coveralls.io/repos/github/USERNAME/REPO/badge.svg?branch=main)](https://coveralls.io/github/USERNAME/REPO?branch=main)
```

### Phase 7: Coverage Reporting Tools

**Set up Codecov:**

1. **Sign up**: https://codecov.io
2. **Add repository**
3. **Get token**: Copy from Codecov dashboard
4. **Add secret**: GitHub repo → Settings → Secrets → `CODECOV_TOKEN`
5. **Configure**: Add upload step to workflow (see Phase 5)

**codecov.yml configuration:**
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

### Phase 8: Standards Tracking

Update `.fvh-standards.yaml`:

```yaml
standards_version: "2025.1"
last_configured: "[timestamp]"
components:
  coverage: "2025.1"
  coverage_threshold: 80
  coverage_provider: "[v8|istanbul|pytest-cov|llvm-cov]"
  coverage_reporters: ["text", "json", "html", "lcov"]
  coverage_ci: "codecov"
```

### Phase 9: Updated Compliance Report

```
Code Coverage Configuration Complete
=====================================

Framework: Vitest with @vitest/coverage-v8
Threshold: 80% (lines, branches, functions, statements)

Configuration Applied:
  ✅ Coverage provider installed
  ✅ Reporters configured (text, json, html, lcov)
  ✅ Thresholds set to 80%
  ✅ Exclusions configured
  ✅ CI/CD integration added

Scripts Added:
  ✅ npm run test:coverage (generate coverage)
  ✅ npm run coverage:report (open HTML report)

CI Integration:
  ✅ Codecov upload configured
  ✅ Coverage artifacts uploaded
  ✅ Badge added to README

Next Steps:
  1. Run coverage locally:
     npm run test:coverage

  2. View coverage report:
     npm run coverage:report

  3. Check coverage in CI:
     Push changes and check workflow

  4. Monitor coverage trends:
     Visit https://codecov.io/gh/USERNAME/REPO

Coverage Reports: coverage/index.html
```

## Flags

| Flag | Description |
|------|-------------|
| `--check-only` | Report status without offering fixes |
| `--fix` | Apply all fixes automatically without prompting |
| `--threshold <percentage>` | Set coverage threshold (default: 80) |

## Examples

```bash
# Check compliance and offer fixes
/configure:coverage

# Check only, no modifications
/configure:coverage --check-only

# Auto-fix with custom threshold
/configure:coverage --fix --threshold 90
```

## Error Handling

- **No test framework detected**: Suggest running `/configure:tests` first
- **Coverage provider missing**: Offer to install
- **Invalid threshold**: Reject values <0 or >100
- **CI token missing**: Warn about Codecov/Coveralls setup

## See Also

- `/configure:tests` - Configure testing frameworks
- `/test:coverage` - Run tests with coverage
- `/configure:all` - Run all FVH compliance checks
- **Codecov documentation**: https://docs.codecov.com
- **pytest-cov documentation**: https://pytest-cov.readthedocs.io
