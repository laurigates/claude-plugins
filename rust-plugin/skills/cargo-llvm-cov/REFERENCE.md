# cargo-llvm-cov - Reference

CI workflow examples for the `cargo-llvm-cov` skill.

## Coveralls Integration

```yaml
# .github/workflows/coverage.yml
name: Coverage

on: [push, pull_request]

jobs:
  coverage:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4.4.0

      - name: Install the pinned toolchain
        run: rustup toolchain install --no-self-update
      - name: Add llvm-tools to the pinned toolchain
        run: rustup component add llvm-tools-preview

      - name: Install cargo-llvm-cov
        uses: taiki-e/install-action@v2.90.3
        with:
          tool: cargo-llvm-cov

      - name: Generate coverage
        run: cargo llvm-cov --all-features --lcov --output-path lcov.info

      - name: Upload to Coveralls
        uses: coverallsapp/github-action@v2.3.8
        with:
          github-token: ${{ secrets.GITHUB_TOKEN }}
          path-to-lcov: lcov.info
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
      - uses: actions/checkout@v4.4.0

      - name: Install the pinned toolchain
        run: rustup toolchain install --no-self-update
      - name: Add llvm-tools to the pinned toolchain
        run: rustup component add llvm-tools-preview

      - uses: Swatinem/rust-cache@v2.9.3

      - name: Install cargo-llvm-cov
        uses: taiki-e/install-action@v2.90.3
        with:
          tool: cargo-llvm-cov

      - name: Install cargo-nextest
        uses: taiki-e/install-action@v2.90.3
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
        uses: codecov/codecov-action@v4.6.0
        with:
          files: lcov.info
          fail_ci_if_error: true
          token: ${{ secrets.CODECOV_TOKEN }}

      - name: Upload HTML report
        uses: actions/upload-artifact@v4.6.2
        if: always()
        with:
          name: coverage-report
          path: target/llvm-cov/html/
```
