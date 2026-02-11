# cargo-machete Reference

Detailed configuration, CI integration, and workflow patterns for cargo-machete.

## Installation

```bash
# Install cargo-machete
cargo install cargo-machete

# Verify installation
cargo machete --version
```

## Output Examples

### Basic Output

```bash
$ cargo machete
Found unused dependencies in Cargo.toml:
  serde_json (unused)
  log (unused in lib, used in build.rs)
  tokio (unused features: macros)
```

### With Metadata

```bash
$ cargo machete --with-metadata
Project: my_app (bin)
  Unused dependencies:
    - serde_json (0.1.0)
      Declared in: Cargo.toml [dependencies]
      Not used in: src/main.rs

  Partially used:
    - tokio (1.35.0)
      Unused features: macros, fs
      Used features: runtime, net
```

## Configuration File

Create `.cargo-machete.toml` in project root:

```toml
# .cargo-machete.toml

# Global ignores
[ignore]
dependencies = [
  "serde",      # Used via derive macro
  "log",        # Used in macro expansion
]

# Per-crate ignores
[ignore.my_lib]
dependencies = ["lazy_static"]

[ignore.my_bin]
dependencies = ["clap"]

# Workspace-wide settings
[workspace]
# Don't analyze these crates
exclude = ["internal_tools", "examples"]
```

### Inline Cargo.toml Ignores

```toml
[dependencies]
serde = "1.0"  # machete:ignore - used via re-export
log = "0.4"    # machete:ignore - used in macro expansion
```

## Workspace Configuration

```bash
# Check all workspace members
cargo machete --workspace

# Check specific workspace members
cargo machete -p crate1 -p crate2

# Exclude specific members
cargo machete --workspace --exclude integration_tests
```

## CI Integration

### GitHub Actions with cargo-machete

```yaml
name: Dependency Check

on: [push, pull_request]

jobs:
  unused-deps:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - uses: dtolnay/rust-toolchain@stable

      - name: Install cargo-machete
        uses: taiki-e/install-action@v2
        with:
          tool: cargo-machete

      - name: Check for unused dependencies
        run: cargo machete --with-metadata
```

### Official GitHub Action

```yaml
name: Dependency Check

on: [push, pull_request]

jobs:
  unused-deps:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Check unused dependencies
        uses: bnjbvr/cargo-machete@main
```

### GitHub Actions with cargo-udeps (Nightly)

```yaml
name: Dependency Check

on: [push, pull_request]

jobs:
  unused-deps:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - uses: dtolnay/rust-toolchain@nightly

      - uses: Swatinem/rust-cache@v2

      - name: Install cargo-udeps
        uses: taiki-e/install-action@v2
        with:
          tool: cargo-udeps

      - name: Check for unused dependencies
        run: cargo +nightly udeps --workspace --all-features
```

## cargo-udeps Installation and Usage

```bash
# Install nightly and cargo-udeps
rustup toolchain install nightly
cargo +nightly install cargo-udeps

# Run analysis (requires nightly)
cargo +nightly udeps

# With specific features
cargo +nightly udeps --all-features

# For workspace
cargo +nightly udeps --workspace
```

## Pre-commit Integration

```yaml
# .pre-commit-config.yaml
repos:
  - repo: local
    hooks:
      - id: cargo-machete
        name: Check for unused dependencies
        entry: cargo machete
        language: system
        pass_filenames: false
        files: Cargo.toml$
```

## Makefile Integration

```makefile
# Makefile
.PHONY: deps-check deps-clean

deps-check:
	@echo "Checking for unused dependencies..."
	@cargo machete --with-metadata

deps-clean:
	@echo "Removing unused dependencies..."
	@cargo machete --fix
	@echo "Running cargo check..."
	@cargo check --all-targets
```

## CI Script

```bash
#!/usr/bin/env bash
# scripts/check-deps.sh
set -euo pipefail

echo "Running cargo-machete..."
if ! cargo machete --with-metadata; then
  echo "Unused dependencies detected!"
  echo "Run 'cargo machete --fix' to remove them."
  exit 1
fi

echo "No unused dependencies found."
```

## Combined Dependency Audit

```bash
# Full dependency audit
cargo machete                 # Check unused
cargo outdated                # Check outdated
cargo audit                   # Check security
cargo deny check licenses     # Check licenses
```

## References

- [cargo-machete repository](https://github.com/bnjbvr/cargo-machete)
- [cargo-udeps repository](https://github.com/est31/cargo-udeps)
- [Official GitHub Action](https://github.com/bnjbvr/cargo-machete)
- [Rust dependency management best practices](https://doc.rust-lang.org/cargo/guide/dependencies.html)
