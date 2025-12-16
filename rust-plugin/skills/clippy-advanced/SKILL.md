---
name: clippy-advanced
description: |
  Advanced Clippy configuration for comprehensive Rust linting with custom rules, categories, and IDE integration.
  Use when configuring linting rules, enforcing code standards, setting up CI linting, or customizing clippy behavior.
  Trigger terms: clippy, linting, code quality, clippy.toml, pedantic, nursery, restriction, lint configuration, code standards.
---

# clippy-advanced - Advanced Clippy Configuration

Advanced Clippy configuration for comprehensive Rust linting, including custom rules, lint categories, disallowed methods, and IDE integration.

## Installation

```bash
# Clippy is included with rustup
rustup component add clippy

# Verify installation
cargo clippy --version

# Update clippy with rust toolchain
rustup update
```

## Basic Usage

```bash
# Run clippy on current project
cargo clippy

# Run on all targets (lib, bins, tests, examples, benches)
cargo clippy --all-targets

# Run with all features enabled
cargo clippy --all-features

# Run on workspace
cargo clippy --workspace --all-targets --all-features

# Show detailed lint explanations
cargo clippy -- -W clippy::all -A clippy::pedantic

# Treat warnings as errors
cargo clippy -- -D warnings
```

## clippy.toml Configuration File

Create `clippy.toml` or `.clippy.toml` in project root:

```toml
# clippy.toml - Project-wide clippy configuration

# Enforce documentation for public items
# Warn if public items are missing documentation
missing-docs-in-crate-items = "warn"

# Cognitive complexity threshold
# Functions with complexity above this will trigger a warning
cognitive-complexity-threshold = 15

# Type complexity threshold
# Complex types will trigger a warning
type-complexity-threshold = 100

# Function length threshold
# Long functions will trigger a warning
too-many-lines-threshold = 100

# Too many arguments threshold
too-many-arguments-threshold = 5

# Vec box size threshold
# Large heap allocations in Vec will trigger a warning
vec-box-size-threshold = 4096

# Disallowed methods with custom messages
disallowed-methods = [
  { path = "std::env::var", reason = "Use std::env::var_os for better Unicode handling" },
  { path = "std::panic::catch_unwind", reason = "Prefer structured error handling" },
  { path = "std::process::exit", reason = "Use Result propagation instead" },
]

# Disallowed types
disallowed-types = [
  { path = "std::collections::HashMap", reason = "Use indexmap::IndexMap for deterministic iteration" },
  { path = "once_cell::sync::Lazy", reason = "Use std::sync::LazyLock (Rust 1.80+)" },
]

# Allowed identifiers (bypass naming lints)
allowed-idents-below-min-chars = ["i", "j", "x", "y", "id", "db"]

# Import granularity (prefer full paths)
# Options: "crate", "module", "item", "one"
imports-granularity = "module"

# Enforce module inception
# Warn about modules that only contain a single item
# which could be moved up to parent module
allow-module-inception = false

# Standard library imports style
# Options: "absolute", "module"
imports-prefer-module = true

# Single component path imports
# Warn about imports of single component paths
single-component-path-imports = "warn"

# Array size threshold for performance lints
# Large arrays passed by value will trigger a warning
array-size-threshold = 512

# String literal as bytes
# Prefer b"string" over "string".as_bytes()
# Options: "always", "never"
literal-representation = "always"

# Allowed scripts for confusable characters
# Prevent mixing similar-looking characters from different scripts
allowed-confusable-scripts = ["Latin", "Greek"]

# Semicolon consistency
# Options: "never", "always"
semicolon-if-nothing-returned = "always"

# Blacklist/whitelist naming
# Use inclusive terminology
disallowed-names = ["foo", "bar", "baz", "master", "slave", "whitelist", "blacklist"]

# Prefer module-level documentation
doc-markdown-inline-code = true
```

## Lint Categories

### All Available Categories

```bash
# Default lints (enabled by default)
cargo clippy -- -W clippy::all

# Pedantic lints (opinionated style)
cargo clippy -- -W clippy::pedantic

# Restriction lints (opt-in for specific constraints)
cargo clippy -- -W clippy::restriction

# Nursery lints (experimental, may have false positives)
cargo clippy -- -W clippy::nursery

# Cargo lints (Cargo.toml issues)
cargo clippy -- -W clippy::cargo

# Complexity lints (overly complex code)
cargo clippy -- -W clippy::complexity

# Correctness lints (likely bugs)
cargo clippy -- -W clippy::correctness

# Perf lints (performance issues)
cargo clippy -- -W clippy::perf

# Style lints (code style)
cargo clippy -- -W clippy::style

# Suspicious lints (code that looks wrong)
cargo clippy -- -W clippy::suspicious
```

### Recommended Category Combination

```toml
# Cargo.toml
[workspace.lints.clippy]
# Deny correctness issues (likely bugs)
correctness = "deny"

# Warn on complexity
complexity = "warn"

# Warn on performance issues
perf = "warn"

# Warn on style issues
style = "warn"

# Warn on suspicious patterns
suspicious = "warn"

# Enable pedantic but allow some noisy lints
pedantic = "warn"
must_use_candidate = "allow"
missing_errors_doc = "allow"

# Enable some restriction lints selectively
clone_on_ref_ptr = "warn"
dbg_macro = "warn"
print_stdout = "warn"
todo = "warn"
unimplemented = "warn"

# Enable nursery lints (experimental)
use_self = "warn"
```

## Cargo.toml Lint Configuration (Recommended)

```toml
# Cargo.toml - Modern workspace lint configuration (Rust 1.74+)
[workspace.lints.clippy]
# Correctness - deny bugs
correctness = { level = "deny", priority = -1 }

# Complexity
complexity = "warn"
cognitive_complexity = "warn"
too_many_arguments = "warn"
too_many_lines = "warn"
type_complexity = "warn"

# Performance
perf = "warn"
large_enum_variant = "warn"
large_stack_arrays = "warn"

# Style
style = "warn"
missing_docs_in_private_items = "warn"

# Pedantic (selective)
pedantic = "warn"
must_use_candidate = "allow"
missing_errors_doc = "allow"
missing_panics_doc = "allow"
module_name_repetitions = "allow"

# Restriction (opt-in)
clone_on_ref_ptr = "warn"
dbg_macro = "warn"
empty_drop = "warn"
exit = "warn"
expect_used = "warn"
filetype_is_file = "warn"
get_unwrap = "warn"
panic = "warn"
print_stderr = "warn"
print_stdout = "warn"
todo = "warn"
unimplemented = "warn"
unreachable = "warn"
unwrap_used = "warn"

# Nursery (experimental, may have false positives)
use_self = "warn"
useless_let_if_seq = "warn"

# Cargo
cargo = "warn"
multiple_crate_versions = "warn"

[workspace.lints.rust]
# Rust lints
missing_docs = "warn"
unsafe_code = "warn"
```

## Allow and Deny Attributes

### Function-level Overrides

```rust
// Allow specific lint for entire function
#[allow(clippy::too_many_arguments)]
fn complex_function(a: i32, b: i32, c: i32, d: i32, e: i32, f: i32) {
    // ...
}

// Deny specific lint
#[deny(clippy::unwrap_used)]
fn critical_function() -> Result<(), Error> {
    // This will error if unwrap() is used
    Ok(())
}

// Warn for specific lint
#[warn(clippy::print_stdout)]
fn debug_function() {
    println!("This will warn");
}
```

### Module-level Configuration

```rust
// src/lib.rs or src/main.rs
#![warn(clippy::all)]
#![warn(clippy::pedantic)]
#![warn(clippy::nursery)]
#![deny(clippy::unwrap_used)]
#![deny(clippy::expect_used)]

// Allow specific lints
#![allow(clippy::module_name_repetitions)]
#![allow(clippy::must_use_candidate)]

// Individual module configuration
#[allow(clippy::pedantic)]
mod legacy_code {
    // Disable pedantic for this module
}
```

### Inline Suppression

```rust
// Suppress for specific line
#[allow(clippy::cast_possible_truncation)]
let x = value as u8;

// Suppress for expression
let y = {
    #[allow(clippy::cast_sign_loss)]
    negative_value as u32
};

// Suppress for block
{
    #![allow(clippy::indexing_slicing)]
    let element = slice[index];
}
```

## CI Integration

### GitHub Actions - Strict Linting

```yaml
name: Clippy

on: [push, pull_request]

env:
  CARGO_TERM_COLOR: always

jobs:
  clippy:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - uses: dtolnay/rust-toolchain@stable
        with:
          components: clippy

      - uses: Swatinem/rust-cache@v2

      - name: Run clippy
        run: |
          cargo clippy --workspace --all-targets --all-features -- -D warnings

      - name: Run clippy pedantic
        run: |
          cargo clippy --workspace --all-targets --all-features -- \
            -W clippy::pedantic \
            -W clippy::nursery \
            -D clippy::correctness
```

### GitHub Actions - Reviewdog Integration

```yaml
name: Clippy Review

on: [pull_request]

jobs:
  clippy-review:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - uses: dtolnay/rust-toolchain@stable
        with:
          components: clippy

      - uses: Swatinem/rust-cache@v2

      - uses: giraffate/clippy-action@v1
        with:
          reporter: 'github-pr-review'
          github_token: ${{ secrets.GITHUB_TOKEN }}
          clippy_flags: --all-targets --all-features
```

### Pre-commit Hook

```yaml
# .pre-commit-config.yaml
repos:
  - repo: local
    hooks:
      - id: cargo-clippy
        name: cargo clippy
        entry: cargo clippy
        args: ['--all-targets', '--all-features', '--', '-D', 'warnings']
        language: system
        pass_filenames: false
        files: \.rs$
```

## rust-analyzer Integration

Configure in VS Code settings or rust-analyzer config:

```json
// .vscode/settings.json
{
  "rust-analyzer.check.command": "clippy",
  "rust-analyzer.check.extraArgs": [
    "--all-targets",
    "--all-features",
    "--",
    "-W",
    "clippy::pedantic",
    "-W",
    "clippy::nursery"
  ],
  "rust-analyzer.checkOnSave": true
}
```

Or in `rust-analyzer.toml`:

```toml
# rust-analyzer.toml
[checkOnSave]
command = "clippy"
extraArgs = [
  "--all-targets",
  "--all-features",
  "--",
  "-W", "clippy::pedantic",
  "-W", "clippy::nursery",
  "-A", "clippy::module_name_repetitions"
]
```

## Disallowed Methods Configuration

```toml
# clippy.toml
disallowed-methods = [
  # Prevent unwrap/expect in production code
  { path = "std::option::Option::unwrap", reason = "Use unwrap_or, unwrap_or_else, or proper error handling" },
  { path = "std::result::Result::unwrap", reason = "Use unwrap_or, unwrap_or_else, or the ? operator" },
  { path = "std::option::Option::expect", reason = "Use unwrap_or, unwrap_or_else, or proper error handling" },
  { path = "std::result::Result::expect", reason = "Use unwrap_or, unwrap_or_else, or the ? operator" },

  # Prevent panic
  { path = "std::panic", reason = "Use Result and proper error handling" },

  # Prevent process::exit
  { path = "std::process::exit", reason = "Return from main or propagate errors" },

  # Environment variable handling
  { path = "std::env::var", reason = "Use std::env::var_os for better Unicode handling" },

  # Prevent direct println! in libraries
  { path = "std::println", reason = "Use logging (log, tracing) instead of println" },
  { path = "std::eprintln", reason = "Use logging (log, tracing) instead of eprintln" },
]

disallowed-types = [
  # Prefer newer stdlib types
  { path = "std::sync::mpsc::channel", reason = "Use crossbeam-channel for better performance" },
  { path = "std::collections::HashMap", reason = "Consider indexmap for deterministic ordering" },

  # Deprecated types
  { path = "std::mem::uninitialized", reason = "Use MaybeUninit instead" },
]
```

## Advanced Patterns

### Conditional Linting for Tests

```rust
// src/lib.rs
#![deny(clippy::unwrap_used)]

// tests/integration.rs
#![allow(clippy::unwrap_used)]  // Ok in tests

#[cfg(test)]
mod tests {
    // Tests can use unwrap
    #[test]
    fn test_something() {
        let value = Some(42);
        assert_eq!(value.unwrap(), 42);
    }
}
```

### Feature-gated Lints

```rust
#[cfg(not(feature = "unsafe_optimizations"))]
#![deny(unsafe_code)]

#[cfg(feature = "unsafe_optimizations")]
#![warn(unsafe_code)]
```

### Documentation Lints

```rust
// Enforce documentation
#![warn(missing_docs)]
#![warn(clippy::missing_docs_in_private_items)]

/// Public function documentation
pub fn public_function() {
    // ...
}

/// Private function documentation (if pedantic enabled)
fn private_function() {
    // ...
}
```

## Best Practices

1. **Start with defaults, gradually enable stricter lints**:
   ```toml
   [workspace.lints.clippy]
   all = "warn"
   correctness = "deny"
   ```

2. **Use Cargo.toml for workspace-wide configuration**:
   ```toml
   [workspace.lints.clippy]
   # All crates inherit these
   ```

3. **Document why lints are suppressed**:
   ```rust
   #[allow(clippy::cast_possible_truncation)]  // Value range validated above
   let x = value as u8;
   ```

4. **Treat warnings as errors in CI**:
   ```yaml
   - run: cargo clippy -- -D warnings
   ```

5. **Enable pedantic selectively**:
   ```toml
   pedantic = "warn"
   must_use_candidate = "allow"  # Too noisy
   ```

6. **Use disallowed-methods for project-specific rules**:
   ```toml
   disallowed-methods = [
     { path = "std::println", reason = "Use tracing instead" }
   ]
   ```

7. **Integrate with rust-analyzer** for real-time feedback

8. **Review and update configuration** as project matures

## Troubleshooting

**Too many warnings:**
```bash
# Start with just correctness
cargo clippy -- -W clippy::correctness
# Gradually enable more
```

**False positives:**
```rust
#[allow(clippy::specific_lint)]  // Document why
fn special_case() { }
```

**Lint not applying:**
```bash
# Check clippy version
cargo clippy --version
# Update toolchain
rustup update
```

**CI failures due to new lints:**
```toml
# Pin clippy version in rust-toolchain.toml
[toolchain]
channel = "1.75.0"
components = ["clippy"]
```

## References

- [Clippy documentation](https://doc.rust-lang.org/clippy/)
- [Lint list](https://rust-lang.github.io/rust-clippy/master/)
- [Configuration options](https://doc.rust-lang.org/clippy/configuration.html)
- [rust-analyzer integration](https://rust-analyzer.github.io/manual.html)
