---
model: haiku
created: 2025-12-16
modified: 2026-02-11
reviewed: 2025-12-16
description: Check and configure code coverage thresholds and reporting
allowed-tools: Glob, Grep, Read, Write, Edit, Bash, AskUserQuestion, TodoWrite, WebSearch, WebFetch
argument-hint: "[--check-only] [--fix] [--threshold <percentage>]"
name: configure-coverage
---

# /configure:coverage

Check and configure code coverage thresholds and reporting for test frameworks.

## When to Use This Skill

| Use this skill when... | Use another approach when... |
|------------------------|------------------------------|
| Setting up coverage thresholds for Vitest, Jest, pytest, or Rust | Running tests with coverage (`/test:coverage`) |
| Configuring coverage reporters (text, JSON, HTML, lcov) | Configuring the test framework itself (`/configure:tests`) |
| Adding Codecov or Coveralls integration to CI/CD | Analyzing test failures (test-runner agent) |
| Auditing coverage configuration compliance across a project | Writing individual test cases |
| Adjusting coverage threshold percentages | Configuring general CI/CD workflows (`/configure:workflows`) |

## Context

- Project root: !`pwd`
- Package files: !`find . -maxdepth 1 \( -name 'package.json' -o -name 'pyproject.toml' -o -name 'Cargo.toml' \) 2>/dev/null`
- Vitest config: !`find . -maxdepth 1 -name 'vitest.config.*' 2>/dev/null`
- Jest config: !`find . -maxdepth 1 -name 'jest.config.*' 2>/dev/null`
- Coverage dir: !`find . -maxdepth 1 -type d -name 'coverage' 2>/dev/null`
- Codecov config: !`find . -maxdepth 1 \( -name 'codecov.yml' -o -name '.codecov.yml' \) 2>/dev/null`
- Project standards: !`find . -maxdepth 1 -name '.project-standards.yaml' 2>/dev/null`

## Parameters

Parse from command arguments:

- `--check-only`: Report compliance status without modifications (CI/CD mode)
- `--fix`: Apply fixes automatically without prompting
- `--threshold <percentage>`: Set coverage threshold (default: 80)

**Default threshold**: 80% (lines, branches, functions, statements)

**Supported frameworks:**
- **Vitest**: `@vitest/coverage-v8` or `@vitest/coverage-istanbul`
- **Jest**: Built-in coverage with `--coverage`
- **pytest**: `pytest-cov` plugin
- **Rust**: `cargo-llvm-cov` or `cargo-tarpaulin`

## Execution

Execute this code coverage compliance check:

### Step 1: Detect test framework and coverage configuration

Check for framework indicators:

| Indicator | Framework | Coverage Tool |
|-----------|-----------|---------------|
| `vitest.config.*` with coverage | Vitest | @vitest/coverage-v8 |
| `jest.config.*` with coverage | Jest | Built-in |
| `pyproject.toml` [tool.coverage] | pytest | pytest-cov |
| `.cargo/config.toml` with coverage | Rust | cargo-llvm-cov |

Use WebSearch or WebFetch to verify latest versions of coverage tools before configuring.

### Step 2: Analyze current coverage state

For the detected framework, check configuration completeness:

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
- [ ] `coverageReporters` configured

**pytest:**
- [ ] `pytest-cov` installed
- [ ] `[tool.coverage.run]` section exists
- [ ] `[tool.coverage.report]` section exists
- [ ] Coverage threshold configured (`--cov-fail-under`)

**Rust (cargo-llvm-cov):**
- [ ] `cargo-llvm-cov` installed
- [ ] Coverage configuration in workspace
- [ ] HTML/LCOV output configured

### Step 3: Generate compliance report

Print a formatted compliance report:

```
Code Coverage Compliance Report
================================
Project: [name]
Framework: [Vitest 2.x | pytest 8.x | cargo-llvm-cov 0.6.x]

Coverage Configuration:
  Provider                @vitest/coverage-v8        [CONFIGURED | MISSING]
  Reporters               text, json, html, lcov     [ALL | PARTIAL]
  Output directory        coverage/                  [CONFIGURED | DEFAULT]
  Exclusions              node_modules, dist, tests  [CONFIGURED | INCOMPLETE]

Thresholds:
  Lines                   80%                        [PASS | LOW | NOT SET]
  Branches                80%                        [PASS | LOW | NOT SET]
  Functions               80%                        [PASS | LOW | NOT SET]
  Statements              80%                        [PASS | LOW | NOT SET]

CI/CD Integration:
  Coverage upload         codecov/coveralls          [CONFIGURED | MISSING]
  Artifact upload         coverage reports           [CONFIGURED | MISSING]

Overall: [X issues found]
```

If `--check-only`, stop here.

### Step 4: Configure coverage (if --fix or user confirms)

Apply coverage configuration based on detected framework. Use templates from [REFERENCE.md](REFERENCE.md):

1. **Install coverage provider** (e.g., `@vitest/coverage-v8`, `pytest-cov`)
2. **Update config file** with thresholds, reporters, exclusions
3. **Add scripts** to package.json or pyproject.toml
4. **Configure CI/CD** with Codecov upload and artifact storage

### Step 5: Update standards tracking

Update `.project-standards.yaml`:

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

### Step 6: Print final report

Print a summary of changes applied, scripts added, and next steps for verifying coverage.

For detailed configuration templates, see [REFERENCE.md](REFERENCE.md).

## Agentic Optimizations

| Context | Command |
|---------|---------|
| Quick compliance check | `/configure:coverage --check-only` |
| Auto-fix all issues | `/configure:coverage --fix` |
| Custom threshold | `/configure:coverage --fix --threshold 90` |
| Check coverage config exists | `find . -maxdepth 1 -name 'vitest.config.*' -o -name 'jest.config.*' 2>/dev/null` |
| Verify coverage directory | `test -d coverage && echo "EXISTS"` |

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
- `/configure:all` - Run all compliance checks
- **Codecov documentation**: https://docs.codecov.com
- **pytest-cov documentation**: https://pytest-cov.readthedocs.io
