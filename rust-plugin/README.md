# Rust Plugin

Comprehensive Rust development support including modern language features, cargo tooling, testing, coverage, and code quality.

## Overview

This plugin provides expert knowledge for Rust development with a focus on:
- Modern Rust 2024+ features and ownership patterns
- Async programming with Tokio
- Memory safety and fearless concurrency
- Advanced cargo tooling for testing and coverage
- Code quality with clippy
- Dependency management and cleanup

## Contents

### Agent

**rust-development** - Expert Rust development agent
- Modern Rust language features (2024 edition, const generics, GATs)
- Ownership, borrowing, and lifetime management
- Async programming patterns with Tokio
- Error handling with thiserror and anyhow
- Performance optimization and profiling
- FFI, WebAssembly, and embedded systems
- Unsafe code guidelines with safety documentation

### Skills

**rust-development** - Core Rust development
- Cargo build system and package management
- Rustc compiler optimization and cross-compilation
- Clippy linting and rustfmt formatting
- Ownership patterns and memory safety
- Async programming with Tokio and async-std
- Error handling and type safety
- Testing and benchmarking

**clippy-advanced** - Advanced Clippy configuration
- Comprehensive lint categories and rules
- Custom clippy.toml configuration
- Disallowed methods and types
- CI integration and GitHub Actions
- rust-analyzer IDE integration
- Workspace-wide lint configuration

**cargo-nextest** - Next-generation test runner
- Parallel test execution with process isolation
- Advanced test filtering with expression language
- Flaky test detection and retries
- JUnit XML output for CI
- GitHub Actions integration
- Test groups and timeouts

**cargo-llvm-cov** - Code coverage with LLVM
- LLVM-based coverage instrumentation
- Multiple output formats (HTML, LCOV, JSON, Cobertura)
- Coverage thresholds for CI
- Branch coverage (nightly)
- Codecov and Coveralls integration
- Integration with cargo-nextest

**cargo-machete** - Unused dependency detection
- Fast unused dependency analysis
- Comparison with cargo-udeps
- False positive handling
- CI integration
- Workspace support
- Dependency audit workflows

## Quick Start

### Using the Agent

```bash
# Invoke the rust-development agent for Rust projects
claude agent rust-development
```

The agent will automatically assist with:
- Rust 2024 language features
- Ownership and borrowing patterns
- Async programming
- Error handling
- Performance optimization
- Testing and documentation

### Using the Skills

Skills are automatically loaded when working with Rust projects. They provide expert knowledge for:

```bash
# Comprehensive linting
cargo clippy --workspace --all-targets --all-features -- -D warnings

# Fast, parallel testing
cargo nextest run --profile ci --all-features

# Code coverage with thresholds
cargo llvm-cov nextest --all-features --fail-under-lines 80 --html

# Detect unused dependencies
cargo machete --with-metadata
```

## Development Workflow

### Project Setup
```bash
cargo new my-project
cd my-project
cargo add tokio --features full
cargo add serde --features derive
cargo add thiserror anyhow
```

### Development Cycle
```bash
cargo check            # Fast type checking
cargo clippy          # Linting
cargo nextest run     # Fast parallel tests
cargo llvm-cov --html # Coverage report
cargo machete         # Check unused deps
```

### CI Pipeline
```bash
# Quality checks
cargo clippy --workspace --all-targets --all-features -- -D warnings
cargo fmt --check

# Testing with coverage
cargo llvm-cov nextest \
  --all-features \
  --fail-under-lines 80 \
  --lcov --output-path lcov.info

# Dependency audit
cargo machete --with-metadata
cargo audit
```

## Key Features

### Modern Rust Development
- Rust 2024 edition features (RPITIT, async fn in traits)
- Const generics and compile-time computation
- Generic associated types (GATs)
- Advanced lifetime management

### Memory Safety
- Ownership patterns and borrowing
- Smart pointers (Box, Rc, Arc, Cell, RefCell, Mutex, RwLock)
- Interior mutability patterns
- Zero-copy abstractions

### Async Programming
- Tokio runtime configuration
- Concurrent execution patterns (join!, select!, spawn)
- Stream processing
- Graceful shutdown and cancellation

### Testing & Coverage
- cargo-nextest for parallel test execution
- cargo-llvm-cov for LLVM-based coverage
- Property-based testing with quickcheck
- Fuzzing with cargo-fuzz

### Code Quality
- Advanced clippy configuration
- Disallowed methods and types
- Workspace-wide lint configuration
- CI integration with strict linting

### Dependency Management
- Fast unused dependency detection with cargo-machete
- Accurate analysis with cargo-udeps
- Security audits with cargo-audit
- License checking with cargo-deny

## CI Integration

### GitHub Actions Example

```yaml
name: Rust CI

on: [push, pull_request]

env:
  CARGO_TERM_COLOR: always

jobs:
  quality:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: dtolnay/rust-toolchain@stable
        with:
          components: clippy, rustfmt
      - uses: Swatinem/rust-cache@v2

      - name: Clippy
        run: cargo clippy --workspace --all-targets --all-features -- -D warnings

      - name: Format check
        run: cargo fmt --check

  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: dtolnay/rust-toolchain@stable
        with:
          components: llvm-tools-preview
      - uses: Swatinem/rust-cache@v2

      - name: Install tools
        uses: taiki-e/install-action@v2
        with:
          tool: nextest,cargo-llvm-cov,cargo-machete

      - name: Test with coverage
        run: |
          cargo llvm-cov nextest \
            --all-features \
            --fail-under-lines 80 \
            --lcov --output-path lcov.info

      - name: Upload coverage
        uses: codecov/codecov-action@v4
        with:
          files: lcov.info

      - name: Check unused dependencies
        run: cargo machete --with-metadata
```

## Best Practices

### Ownership Patterns
```rust
// Prefer borrowing over ownership
fn process(data: &[u8]) -> Result<(), Error> { }

// Use Cow for flexible ownership
use std::borrow::Cow;
fn maybe_modify(input: Cow<'_, str>) -> Cow<'_, str> { }
```

### Error Handling
```rust
use thiserror::Error;

#[derive(Error, Debug)]
pub enum ServiceError {
    #[error("connection failed: {0}")]
    Connection(#[from] std::io::Error),

    #[error("invalid input: {message}")]
    InvalidInput { message: String },
}
```

### Async Programming
```rust
use tokio::sync::mpsc;

async fn run_service(mut shutdown: mpsc::Receiver<()>) {
    loop {
        tokio::select! {
            _ = shutdown.recv() => break,
            result = process_request() => handle(result),
        }
    }
}
```

## Common Patterns

### Testing
```rust
#[cfg(test)]
mod tests {
    #[test]
    fn test_parser() -> Result<()> {
        let result = parse("input")?;
        assert_eq!(result, expected);
        Ok(())
    }

    #[tokio::test]
    async fn test_async() {
        let result = fetch_data().await.unwrap();
        assert_eq!(result.status, Status::Success);
    }
}
```

### Clippy Configuration
```toml
# Cargo.toml
[workspace.lints.clippy]
correctness = "deny"
complexity = "warn"
perf = "warn"
pedantic = "warn"
unwrap_used = "warn"
```

## Resources

- [The Rust Programming Language](https://doc.rust-lang.org/book/)
- [Rust by Example](https://doc.rust-lang.org/rust-by-example/)
- [The Rustonomicon](https://doc.rust-lang.org/nomicon/)
- [Async Book](https://rust-lang.github.io/async-book/)
- [docs.rs](https://docs.rs/) - Crate documentation
- [Clippy Lint List](https://rust-lang.github.io/rust-clippy/master/)
- [cargo-nextest](https://nexte.st/)
- [cargo-llvm-cov](https://github.com/taiki-e/cargo-llvm-cov)

## Installation

This plugin is part of the claude-plugins repository. Install by copying the rust-plugin directory to your Claude plugins location.

## License

Same as parent repository.
