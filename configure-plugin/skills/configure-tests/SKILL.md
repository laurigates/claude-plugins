---
model: haiku
created: 2025-12-16
modified: 2026-02-10
reviewed: 2025-12-16
description: Check and configure testing frameworks and infrastructure
allowed-tools: Glob, Grep, Read, Write, Edit, Bash, AskUserQuestion, TodoWrite, WebSearch, WebFetch
argument-hint: "[--check-only] [--fix] [--framework <vitest|jest|pytest|nextest>]"
name: configure-tests
---

# /configure:tests

Check and configure testing frameworks against best practices (Vitest, Jest, pytest, cargo-nextest).

## When to Use This Skill

| Use this skill when... | Use another approach when... |
|------------------------|------------------------------|
| Setting up testing infrastructure | Just running tests (use `/test:run` skill) |
| Checking test framework configuration | Tests already properly configured |
| Migrating to modern test frameworks (Vitest, pytest, nextest) | Writing individual tests (write tests directly) |
| Validating coverage configuration | Debugging failing tests (check test output) |
| Ensuring test best practices | Simple project with no testing needed |

## Context

- Package.json: !`test -f package.json && echo "EXISTS" || echo "MISSING"`
- Pyproject.toml: !`test -f pyproject.toml && echo "EXISTS" || echo "MISSING"`
- Cargo.toml: !`test -f Cargo.toml && echo "EXISTS" || echo "MISSING"`
- Test config files: !`find . -maxdepth 1 \( -name 'vitest.config.*' -o -name 'jest.config.*' -o -name 'pytest.ini' -o -name '.nextest.toml' \) 2>/dev/null`
- Pytest in pyproject: !`grep -c 'tool.pytest' pyproject.toml 2>/dev/null`
- Test directories: !`find . -maxdepth 2 -type d \( -name 'tests' -o -name '__tests__' -o -name 'test' \) 2>/dev/null`
- Test scripts in package.json: !`grep -m5 -o '"test[^"]*"' package.json 2>/dev/null`
- Coverage config: !`grep -l 'coverage' vitest.config.* jest.config.* 2>/dev/null`
- Project standards: !`head -20 .project-standards.yaml 2>/dev/null`

**Modern testing stack preferences:**
- **JavaScript/TypeScript**: Vitest (preferred) or Jest
- **Python**: pytest with pytest-cov
- **Rust**: cargo-nextest for improved performance

## Parameters

Parse these from `$ARGUMENTS`:

| Flag | Description |
|------|-------------|
| `--check-only` | Report status without offering fixes |
| `--fix` | Apply all fixes automatically without prompting |
| `--framework <framework>` | Override framework detection (`vitest`, `jest`, `pytest`, `nextest`) |

## Version Checking

**CRITICAL**: Before flagging outdated versions, verify latest releases:

1. **Vitest**: Check [vitest.dev](https://vitest.dev/) or [GitHub releases](https://github.com/vitest-dev/vitest/releases)
2. **Jest**: Check [jestjs.io](https://jestjs.io/) or [npm](https://www.npmjs.com/package/jest)
3. **pytest**: Check [pytest.org](https://pytest.org/) or [PyPI](https://pypi.org/project/pytest/)
4. **cargo-nextest**: Check [nexte.st](https://nexte.st/) or [GitHub releases](https://github.com/nextest-rs/nextest/releases)

Use WebSearch or WebFetch to verify current versions before reporting outdated frameworks.

## Execution

Execute this testing framework compliance check:

### Step 1: Detect framework

Identify the project language and existing test framework:

| Indicator | Language | Detected Framework |
|-----------|----------|-------------------|
| `vitest.config.*` | JavaScript/TypeScript | Vitest |
| `jest.config.*` | JavaScript/TypeScript | Jest |
| `pyproject.toml` [tool.pytest] | Python | pytest |
| `pytest.ini` | Python | pytest |
| `Cargo.toml` | Rust | cargo test |
| `.nextest.toml` | Rust | cargo-nextest |

If `--framework` flag is provided, use that value instead.

### Step 2: Analyze current state

Read the detected framework's configuration and check completeness. For each framework, verify:

**Vitest:**
- Config file exists (`vitest.config.ts` or `.js`)
- `globals: true` configured for compatibility
- `environment` set appropriately (jsdom, happy-dom, node)
- Coverage configured with `@vitest/coverage-v8` or `@vitest/coverage-istanbul`
- Watch mode exclusions configured

**Jest:**
- Config file exists (`jest.config.js` or `.ts`)
- `testEnvironment` configured
- Coverage configuration present
- Transform configured for TypeScript/JSX
- Module path aliases configured

**pytest:**
- `pyproject.toml` has `[tool.pytest.ini_options]` section
- `testpaths` configured
- `addopts` includes useful flags (`-v`, `--strict-markers`)
- `markers` defined for test categorization
- `pytest-cov` installed

**cargo-nextest:**
- `.nextest.toml` exists
- Profile configurations (default, ci)
- Retry policy configured
- Test groups defined if needed

### Step 3: Report results

Print a compliance report with:
- Detected framework and version
- Configuration check results for each item
- Test organization (unit/integration/e2e directories)
- Package scripts status (test, test:watch, test:coverage)
- Overall issue count and recommendations

If `--check-only`, stop here.

### Step 4: Apply fixes (if --fix or user confirms)

Install dependencies and create configuration using templates from [REFERENCE.md](REFERENCE.md):

1. **Missing config**: Create framework config file from template
2. **Missing dependencies**: Install required packages
3. **Missing coverage**: Add coverage configuration with 80% threshold
4. **Missing scripts**: Add test scripts to package.json
5. **Missing test directories**: Create standard test directory structure

### Step 5: Set up test organization

Create standard test directory structure for the detected language. See directory structure patterns in [REFERENCE.md](REFERENCE.md).

### Step 6: Configure CI/CD integration

Check for test commands in GitHub Actions workflows. If missing, add CI test commands using the CI templates from [REFERENCE.md](REFERENCE.md).

### Step 7: Handle migration (if upgrading)

If migrating between frameworks (e.g., Jest to Vitest, unittest to pytest), follow the migration guide in [REFERENCE.md](REFERENCE.md).

### Step 8: Update standards tracking

Update `.project-standards.yaml`:

```yaml
standards_version: "2025.1"
last_configured: "<timestamp>"
components:
  tests: "2025.1"
  tests_framework: "<vitest|jest|pytest|nextest>"
  tests_coverage_threshold: 80
  tests_ci_integrated: true
```

For detailed configuration templates, migration guides, CI/CD integration examples, and directory structure patterns, see [REFERENCE.md](REFERENCE.md).

## Agentic Optimizations

| Context | Command |
|---------|---------|
| Detect test framework | `find . -maxdepth 1 \( -name 'vitest.config.*' -o -name 'jest.config.*' -o -name 'pytest.ini' \) 2>/dev/null` |
| Check coverage config | `grep -l 'coverage' package.json pyproject.toml 2>/dev/null` |
| List test files | `find . \( -path '*/tests/*' -o -path '*/test/*' -o -name '*.test.*' -o -name '*.spec.*' \) 2>/dev/null \| head -n 10` |
| Quick compliance check | `/configure:tests --check-only` |
| Auto-fix configuration | `/configure:tests --fix` |

## Error Handling

- **No package.json found**: Cannot configure JS/TS tests, skip or error
- **Conflicting frameworks**: Warn about multiple test configs, require manual resolution
- **Missing dependencies**: Offer to install required packages
- **Invalid config syntax**: Report parse error, offer to replace with template

## See Also

- `/configure:coverage` - Configure coverage thresholds and reporting
- `/configure:all` - Run all compliance checks
- `/test:run` - Universal test runner
- `/test:setup` - Comprehensive testing infrastructure setup
- **Vitest documentation**: https://vitest.dev
- **pytest documentation**: https://docs.pytest.org
- **cargo-nextest documentation**: https://nexte.st
