---
name: cargo-nextest
description: |
  Next-generation test runner for Rust with parallel execution, advanced filtering, and CI integration.
  Use when running tests, configuring test execution, setting up CI pipelines, or optimizing test performance.
  Trigger terms: nextest, test runner, parallel tests, test filtering, test performance, flaky tests, CI testing.
---

# cargo-nextest - Next-Generation Test Runner

cargo-nextest is a faster, more reliable test runner for Rust that executes each test in its own process for better isolation and parallel performance.

## Installation

```bash
# Install cargo-nextest
cargo install cargo-nextest --locked

# Verify installation
cargo nextest --version
```

## Basic Usage

```bash
# Run all tests with nextest
cargo nextest run

# Run specific test
cargo nextest run test_name

# Run tests in specific package
cargo nextest run -p package_name

# Run with verbose output
cargo nextest run --verbose

# Run ignored tests
cargo nextest run -- --ignored

# Run all tests including ignored
cargo nextest run -- --include-ignored
```

## Configuration File

Create `.config/nextest.toml` in your project root:

```toml
[profile.default]
# Number of retries for flaky tests
retries = 0

# Test threads (default: number of logical CPUs)
test-threads = 8

# Fail fast - stop on first failure
fail-fast = false

# Show output for passing tests
success-output = "never"  # never, immediate, final, immediate-final

# Show output for failing tests
failure-output = "immediate"  # never, immediate, final, immediate-final

[profile.ci]
# CI-specific configuration
retries = 2
fail-fast = true
success-output = "never"
failure-output = "immediate-final"

# Slow test timeout
slow-timeout = { period = "60s", terminate-after = 2 }

[profile.ci.junit]
# JUnit XML output for CI
path = "target/nextest/ci/junit.xml"
```

## Test Filtering with Expression Language

```bash
# Run tests matching pattern
cargo nextest run -E 'test(auth)'

# Run tests in specific binary
cargo nextest run -E 'binary(my_app)'

# Run tests in specific package
cargo nextest run -E 'package(my_crate)'

# Complex expressions with operators
cargo nextest run -E 'test(auth) and not test(slow)'

# Run all integration tests
cargo nextest run -E 'kind(test)'

# Run only unit tests in library
cargo nextest run -E 'kind(lib) and test(/)'
```

### Expression Operators

- `test(pattern)` - Match test name (regex)
- `binary(pattern)` - Match binary name
- `package(pattern)` - Match package name
- `kind(type)` - Match test kind (lib, bin, test, bench, example)
- `platform(os)` - Match target platform
- `not expr` - Logical NOT
- `expr and expr` - Logical AND
- `expr or expr` - Logical OR

## Parallel Execution

Nextest runs each test in its own process by default, providing:

- **Better isolation** - Tests cannot interfere with each other
- **True parallelism** - No global state conflicts
- **Fault isolation** - One test crash doesn't affect others
- **Better resource management** - Each test has clean environment

```bash
# Control parallelism
cargo nextest run --test-threads 4

# Single-threaded execution
cargo nextest run --test-threads 1

# Use all available cores
cargo nextest run --test-threads 0
```

## Output Formats

```bash
# Human-readable output (default)
cargo nextest run

# JSON output for programmatic parsing
cargo nextest run --message-format json

# JSON with test output
cargo nextest run --message-format json-pretty

# Generate JUnit XML for CI
cargo nextest run --profile ci

# Combine with cargo-llvm-cov for coverage
cargo llvm-cov nextest --html
```

## Flaky Test Management

```toml
# In .config/nextest.toml
[profile.default]
# Retry flaky tests automatically
retries = 3

# Detect tests that pass on retry
[profile.default.overrides]
filter = 'test(flaky_)'
retries = 5
```

```bash
# Run with retries
cargo nextest run --retries 3

# Show retry statistics
cargo nextest run --retries 3 --failure-output immediate-final
```

## GitHub Actions Integration

```yaml
name: Test

on: [push, pull_request]

jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - uses: dtolnay/rust-toolchain@stable

      - name: Install nextest
        uses: taiki-e/install-action@v2
        with:
          tool: nextest

      - name: Run tests
        run: cargo nextest run --profile ci --all-features

      - name: Upload test results
        if: always()
        uses: actions/upload-artifact@v4
        with:
          name: test-results
          path: target/nextest/ci/junit.xml

      - name: Publish test results
        uses: EnricoMi/publish-unit-test-result-action@v2
        if: always()
        with:
          files: target/nextest/ci/junit.xml
```

## Advanced Configuration

```toml
# .config/nextest.toml
[profile.default]
# Timeout for slow tests
slow-timeout = { period = "30s", terminate-after = 3 }

# Test groups for resource management
[test-groups.database]
max-threads = 1  # Serialize database tests

[profile.default.overrides]
filter = 'test(db_)'
test-group = 'database'

# Platform-specific overrides
[[profile.default.overrides]]
platform = 'x86_64-pc-windows-msvc'
slow-timeout = { period = "60s" }
```

## Doctests Limitation

**Important**: nextest does not support doctests. Use cargo test for doctests:

```bash
# Run doctests separately
cargo test --doc

# Run both nextest and doctests in CI
cargo nextest run && cargo test --doc
```

## Workspace Configuration

```toml
# In workspace root .config/nextest.toml
[profile.default]
default-filter = 'all()'

# Per-package overrides
[[profile.default.overrides]]
filter = 'package(slow_tests)'
test-threads = 1
slow-timeout = { period = "120s" }
```

## Comparison with cargo test

| Feature | cargo test | cargo nextest |
|---------|------------|---------------|
| Execution model | In-process | Per-test process |
| Parallelism | Thread-based | Process-based |
| Test isolation | Shared state | Complete isolation |
| Output format | Limited | Rich (JSON, JUnit) |
| Flaky test handling | Manual | Built-in retries |
| Doctests | Supported | Not supported |
| Performance | Good | Excellent |

## Best Practices

1. **Use profiles for different environments**:
   - `default` for local development
   - `ci` for continuous integration
   - `coverage` for coverage analysis

2. **Configure flaky test detection**:
   ```toml
   [profile.default]
   retries = 2
   ```

3. **Group resource-intensive tests**:
   ```toml
   [test-groups.expensive]
   max-threads = 2
   ```

4. **Set appropriate timeouts**:
   ```toml
   [profile.default]
   slow-timeout = { period = "60s", terminate-after = 2 }
   ```

5. **Use expression filters effectively**:
   ```bash
   # Run fast tests during development
   cargo nextest run -E 'not test(slow_)'
   ```

6. **Always run doctests separately in CI**:
   ```yaml
   - run: cargo nextest run --all-features
   - run: cargo test --doc --all-features
   ```

## Troubleshooting

**Tests timeout too quickly:**
```toml
[profile.default]
slow-timeout = { period = "120s", terminate-after = 3 }
```

**Too much parallel execution:**
```bash
cargo nextest run --test-threads 4
```

**Need test output for debugging:**
```bash
cargo nextest run --success-output immediate --failure-output immediate
```

**Flaky tests in CI:**
```toml
[profile.ci]
retries = 3
failure-output = "immediate-final"
```

## References

- [nextest documentation](https://nexte.st/)
- [Configuration reference](https://nexte.st/docs/configuration/)
- [Expression language](https://nexte.st/docs/running/)
- [CI Features](https://nexte.st/docs/ci-features/archiving/)
