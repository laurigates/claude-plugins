---
name: cargo-llvm-cov
description: |
  Code coverage for Rust using LLVM instrumentation with support for multiple output formats and CI integration.
  Use when measuring test coverage, generating coverage reports, enforcing coverage thresholds, or integrating with codecov/coveralls.
  Trigger terms: coverage, llvm-cov, code coverage, test coverage, coverage report, codecov, coveralls, branch coverage.
---

# cargo-llvm-cov - Code Coverage with LLVM

cargo-llvm-cov provides accurate code coverage for Rust using LLVM's instrumentation-based coverage. It supports multiple output formats and integrates seamlessly with CI platforms.

## Installation

```bash
# Install cargo-llvm-cov
cargo install cargo-llvm-cov

# Verify installation
cargo llvm-cov --version

# Install llvm-tools-preview component (required)
rustup component add llvm-tools-preview
```

## Basic Usage

```bash
# Run tests and generate coverage
cargo llvm-cov

# Generate HTML report
cargo llvm-cov --html
open target/llvm-cov/html/index.html

# Generate LCOV report
cargo llvm-cov --lcov --output-path target/llvm-cov/lcov.info

# Generate JSON report
cargo llvm-cov --json --output-path target/llvm-cov/coverage.json

# Show coverage as text summary
cargo llvm-cov --text

# Show coverage for specific files
cargo llvm-cov --text -- --show-instantiations
```

## Output Formats

```bash
# HTML report (interactive, line-by-line)
cargo llvm-cov --html --open

# LCOV format (compatible with many tools)
cargo llvm-cov --lcov --output-path lcov.info

# JSON format (programmatic analysis)
cargo llvm-cov --json --output-path coverage.json

# Cobertura XML (for Jenkins, GitLab)
cargo llvm-cov --cobertura --output-path cobertura.xml

# Text summary (terminal output)
cargo llvm-cov --text

# Multiple formats simultaneously
cargo llvm-cov --html --lcov --output-path lcov.info
```

## Coverage Thresholds for CI

```bash
# Fail if coverage is below threshold
cargo llvm-cov --fail-under-lines 80

# Multiple threshold types
cargo llvm-cov --fail-under-lines 80 --fail-under-functions 75

# Available threshold types
cargo llvm-cov --fail-under-lines 80      # Line coverage
cargo llvm-cov --fail-under-regions 80    # Region coverage
cargo llvm-cov --fail-under-functions 75  # Function coverage
```

### Threshold Configuration

Create a script or Makefile for consistent thresholds:

```makefile
# Makefile
.PHONY: coverage coverage-ci

coverage:
	cargo llvm-cov --html --open

coverage-ci:
	cargo llvm-cov \
		--fail-under-lines 80 \
		--fail-under-functions 75 \
		--lcov --output-path lcov.info
```

Or use a shell script:

```bash
#!/usr/bin/env bash
# scripts/coverage.sh
set -euo pipefail

COVERAGE_THRESHOLD="${COVERAGE_THRESHOLD:-80}"

cargo llvm-cov \
  --fail-under-lines "$COVERAGE_THRESHOLD" \
  --lcov --output-path target/llvm-cov/lcov.info \
  --html

echo "Coverage threshold: $COVERAGE_THRESHOLD% (lines)"
```

## Branch Coverage (Nightly)

Branch coverage requires Rust nightly:

```bash
# Install nightly toolchain
rustup toolchain install nightly
rustup component add llvm-tools-preview --toolchain nightly

# Run with branch coverage
cargo +nightly llvm-cov --branch --html

# Branch coverage with thresholds
cargo +nightly llvm-cov \
  --branch \
  --fail-under-lines 80 \
  --fail-under-branches 70
```

### Branch Coverage Configuration

```toml
# rust-toolchain.toml
[toolchain]
channel = "nightly"
components = ["llvm-tools-preview"]

# Allows using `cargo llvm-cov --branch` without +nightly
```

## Integration with cargo-nextest

```bash
# Use nextest as test runner
cargo llvm-cov nextest --html

# With nextest profile
cargo llvm-cov nextest --profile ci --lcov --output-path lcov.info

# All nextest options work
cargo llvm-cov nextest -E 'not test(slow_)' --html
```

## Codecov Integration

```yaml
# .github/workflows/coverage.yml
name: Coverage

on: [push, pull_request]

jobs:
  coverage:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - uses: dtolnay/rust-toolchain@stable
        with:
          components: llvm-tools-preview

      - name: Install cargo-llvm-cov
        uses: taiki-e/install-action@v2
        with:
          tool: cargo-llvm-cov

      - name: Generate coverage
        run: cargo llvm-cov --all-features --lcov --output-path lcov.info

      - name: Upload to codecov
        uses: codecov/codecov-action@v4
        with:
          files: lcov.info
          fail_ci_if_error: true
          token: ${{ secrets.CODECOV_TOKEN }}
```

## Coveralls Integration

```yaml
# .github/workflows/coverage.yml
name: Coverage

on: [push, pull_request]

jobs:
  coverage:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - uses: dtolnay/rust-toolchain@stable
        with:
          components: llvm-tools-preview

      - name: Install cargo-llvm-cov
        uses: taiki-e/install-action@v2
        with:
          tool: cargo-llvm-cov

      - name: Generate coverage
        run: cargo llvm-cov --all-features --lcov --output-path lcov.info

      - name: Upload to Coveralls
        uses: coverallsapp/github-action@v2
        with:
          github-token: ${{ secrets.GITHUB_TOKEN }}
          path-to-lcov: lcov.info
```

## Advanced Configuration

### Exclude Files from Coverage

```bash
# Exclude generated code
cargo llvm-cov --ignore-filename-regex '.*generated.*'

# Exclude test files
cargo llvm-cov --ignore-filename-regex '.*test.*'

# Multiple patterns
cargo llvm-cov \
  --ignore-filename-regex '.*generated.*' \
  --ignore-filename-regex '.*mock.*'
```

### Workspace Coverage

```bash
# Coverage for all workspace members
cargo llvm-cov --workspace --html

# Coverage for specific packages
cargo llvm-cov -p my_lib -p my_app --html

# Exclude specific packages
cargo llvm-cov --workspace --exclude integration_tests --html
```

### Coverage with Feature Flags

```bash
# Coverage with all features
cargo llvm-cov --all-features --html

# Coverage with specific features
cargo llvm-cov --features async,tls --html

# Coverage without default features
cargo llvm-cov --no-default-features --html
```

## GitHub Actions: Complete Example

```yaml
# .github/workflows/coverage.yml
name: Coverage

on:
  push:
    branches: [main]
  pull_request:

env:
  CARGO_TERM_COLOR: always
  COVERAGE_THRESHOLD: 80

jobs:
  coverage:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - uses: dtolnay/rust-toolchain@stable
        with:
          components: llvm-tools-preview

      - uses: Swatinem/rust-cache@v2

      - name: Install cargo-llvm-cov
        uses: taiki-e/install-action@v2
        with:
          tool: cargo-llvm-cov

      - name: Install cargo-nextest
        uses: taiki-e/install-action@v2
        with:
          tool: nextest

      - name: Generate coverage
        run: |
          cargo llvm-cov nextest \
            --all-features \
            --fail-under-lines $COVERAGE_THRESHOLD \
            --lcov --output-path lcov.info \
            --html

      - name: Upload coverage to Codecov
        uses: codecov/codecov-action@v4
        with:
          files: lcov.info
          fail_ci_if_error: true
          token: ${{ secrets.CODECOV_TOKEN }}

      - name: Upload HTML report
        uses: actions/upload-artifact@v4
        if: always()
        with:
          name: coverage-report
          path: target/llvm-cov/html/
```

## Clean Coverage Data

```bash
# Clean previous coverage data
cargo llvm-cov clean

# Clean and run fresh coverage
cargo llvm-cov clean && cargo llvm-cov --html
```

## Doctests Coverage

```bash
# Include doctests in coverage
cargo llvm-cov --doc --html

# Doctests with workspace
cargo llvm-cov --workspace --doc --html

# Note: doctests run in separate context, may not integrate perfectly
```

## Comparison with tarpaulin

| Feature | cargo-llvm-cov | cargo-tarpaulin |
|---------|----------------|-----------------|
| Backend | LLVM (compiler) | ptrace (runtime) |
| Accuracy | Excellent | Good |
| Performance | Fast | Slower |
| Branch coverage | Yes (nightly) | Yes |
| Stability | Stable | Sometimes unstable |
| Platform support | All Rust targets | Linux, limited macOS |
| Setup complexity | Simple | Simple |

## Best Practices

1. **Use with nextest for faster execution**:
   ```bash
   cargo llvm-cov nextest --all-features --html
   ```

2. **Enforce coverage thresholds in CI**:
   ```bash
   cargo llvm-cov --fail-under-lines 80
   ```

3. **Generate multiple formats for different tools**:
   ```bash
   cargo llvm-cov --html --lcov --output-path lcov.info
   ```

4. **Exclude generated code from coverage**:
   ```bash
   cargo llvm-cov --ignore-filename-regex '.*generated.*'
   ```

5. **Cache coverage dependencies in CI**:
   ```yaml
   - uses: Swatinem/rust-cache@v2
   ```

6. **Use branch coverage on nightly for critical code**:
   ```bash
   cargo +nightly llvm-cov --branch --fail-under-branches 70
   ```

7. **Clean coverage data between runs**:
   ```bash
   cargo llvm-cov clean
   ```

## Troubleshooting

**Missing llvm-tools-preview:**
```bash
rustup component add llvm-tools-preview
```

**Coverage seems inaccurate:**
```bash
# Clean and regenerate
cargo llvm-cov clean
cargo clean
cargo llvm-cov --html
```

**Nightly features not working:**
```bash
rustup toolchain install nightly
rustup component add llvm-tools-preview --toolchain nightly
cargo +nightly llvm-cov --branch --html
```

**Slow coverage generation:**
```bash
# Use nextest for parallel execution
cargo llvm-cov nextest --html
```

**Doctests not included:**
```bash
# Run with --doc flag
cargo llvm-cov --doc --html
```

## References

- [cargo-llvm-cov documentation](https://github.com/taiki-e/cargo-llvm-cov)
- [LLVM coverage mapping](https://llvm.org/docs/CoverageMappingFormat.html)
- [Codecov Rust](https://about.codecov.io/language/rust/)
- [coveralls-api crate](https://docs.rs/coveralls-api)
