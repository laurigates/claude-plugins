---
name: cargo-machete
description: |
  Detect unused dependencies in Rust projects for cleaner Cargo.toml files and faster builds.
  Use when auditing dependencies, optimizing build times, cleaning up Cargo.toml, or detecting bloat.
  Trigger terms: unused dependencies, cargo-machete, dependency audit, dependency cleanup, bloat detection, cargo-udeps.
---

# cargo-machete - Unused Dependency Detection

cargo-machete is a fast tool for detecting unused dependencies in Rust projects. It analyzes your codebase to find dependencies listed in Cargo.toml but not actually used in your code.

## Installation

```bash
# Install cargo-machete
cargo install cargo-machete

# Verify installation
cargo machete --version
```

## Basic Usage

```bash
# Check for unused dependencies in current directory
cargo machete

# Check specific directory
cargo machete /path/to/project

# Check with detailed output
cargo machete --with-metadata

# Fix unused dependencies automatically (removes from Cargo.toml)
cargo machete --fix

# Check workspace
cargo machete --workspace
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

## False Positive Handling

### Common False Positives

1. **Dependencies used only in build.rs**:
   ```toml
   [build-dependencies]
   bindgen = "0.69"  # Correctly placed, machete won't flag
   ```

2. **Dependencies used only in examples**:
   ```toml
   [dev-dependencies]
   criterion = "0.5"  # For examples/benchmarks
   ```

3. **Dependencies used via re-exports**:
   ```rust
   // lib.rs
   pub use external_crate::SomeType;  # Machete may not detect
   ```

4. **Proc-macro dependencies**:
   ```toml
   [dependencies]
   serde = { version = "1.0", features = ["derive"] }
   # Machete may flag serde as unused if only using derive macro
   ```

### Ignoring False Positives

Create `.cargo-machete.toml` or add to `Cargo.toml`:

```toml
# .cargo-machete.toml
[ignore]
# Ignore specific dependencies
dependencies = ["serde", "log"]

# Ignore dependencies in specific crates
[ignore.my_crate]
dependencies = ["tokio"]
```

Or use inline comments in `Cargo.toml`:

```toml
[dependencies]
serde = "1.0"  # machete:ignore - used via re-export
log = "0.4"    # machete:ignore - used in macro expansion
```

## Comparison with cargo-udeps

| Feature | cargo-machete | cargo-udeps |
|---------|---------------|-------------|
| Accuracy | Good | Excellent |
| Speed | Very fast | Slower |
| Rust version | Stable | Requires nightly |
| False positives | Some | Fewer |
| Installation | Simple | Requires nightly setup |
| Maintenance | Active | Active |

### When to Use Each

**Use cargo-machete when:**
- Working with stable Rust
- Need fast feedback in CI
- Willing to verify results manually
- Want simple installation

**Use cargo-udeps when:**
- Accuracy is critical
- Can use nightly toolchain
- Need to catch all unused dependencies
- Have time for slower analysis

### Using Both Together

```bash
# Fast check with machete
cargo machete

# Verify with udeps (more accurate)
cargo +nightly udeps
```

## cargo-udeps Installation and Usage

For comparison, here's how to use the more accurate cargo-udeps:

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

### GitHub Action (Official cargo-machete Action)

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

## Advanced Usage

### Workspace Configuration

```bash
# Check all workspace members
cargo machete --workspace

# Check specific workspace members
cargo machete -p crate1 -p crate2

# Exclude specific members
cargo machete --workspace --exclude integration_tests
```

### Custom Configuration File

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

### Integration with Pre-commit

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

## Workflow Integration

### Combined with Other Tools

```bash
# Full dependency audit
cargo machete                 # Check unused
cargo outdated                # Check outdated
cargo audit                   # Check security
cargo deny check licenses     # Check licenses
```

### Makefile Integration

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

### Script for CI

```bash
#!/usr/bin/env bash
# scripts/check-deps.sh
set -euo pipefail

echo "Running cargo-machete..."
if ! cargo machete --with-metadata; then
  echo "❌ Unused dependencies detected!"
  echo "Run 'cargo machete --fix' to remove them."
  exit 1
fi

echo "✅ No unused dependencies found."
```

## Best Practices

1. **Run regularly in CI**:
   ```yaml
   - run: cargo machete --with-metadata
   ```

2. **Document false positives**:
   ```toml
   [dependencies]
   serde = "1.0"  # machete:ignore - used via proc macro
   ```

3. **Use with workspace**:
   ```bash
   cargo machete --workspace --with-metadata
   ```

4. **Verify before using --fix**:
   ```bash
   # Check first
   cargo machete --with-metadata
   # Review output, then fix
   cargo machete --fix
   # Verify everything still builds
   cargo check --all-targets
   ```

5. **Combine with cargo-udeps for accuracy**:
   ```bash
   # Fast check
   cargo machete
   # Verify critical projects
   cargo +nightly udeps -p critical_lib
   ```

6. **Add to pre-commit hooks** for early detection:
   ```yaml
   - id: cargo-machete
     entry: cargo machete
     language: system
   ```

7. **Keep configuration file** for complex projects:
   ```toml
   # .cargo-machete.toml
   [ignore]
   dependencies = ["known-false-positives"]
   ```

## Troubleshooting

**False positives for proc macros:**
```toml
# Add to .cargo-machete.toml
[ignore]
dependencies = ["serde", "tokio-macros"]
```

**Build.rs dependencies flagged:**
```toml
# Should be in [build-dependencies]
[build-dependencies]
cc = "1.0"
```

**Re-exported dependencies flagged:**
```toml
# Document with comment
[dependencies]
external = "1.0"  # machete:ignore - re-exported in lib.rs
```

**Workspace member issues:**
```bash
# Check specific member
cargo machete -p problematic_crate --with-metadata
```

**Need more accuracy:**
```bash
# Use cargo-udeps instead
cargo +nightly udeps --workspace
```

## References

- [cargo-machete repository](https://github.com/bnjbvr/cargo-machete)
- [cargo-udeps repository](https://github.com/est31/cargo-udeps)
- [Official GitHub Action](https://github.com/bnjbvr/cargo-machete)
- [Rust dependency management best practices](https://doc.rust-lang.org/cargo/guide/dependencies.html)
