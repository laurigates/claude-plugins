---
model: haiku
created: 2025-12-16
modified: 2026-02-14
reviewed: 2025-12-16
name: clippy-advanced
description: |
  Advanced Clippy configuration for comprehensive Rust linting with custom rules, categories, and IDE integration.
  Use when configuring linting rules, enforcing code standards, setting up CI linting, or customizing clippy behavior.
  Trigger terms: clippy, linting, code quality, clippy.toml, pedantic, nursery, restriction, lint configuration, code standards.
allowed-tools: Bash, Read, Grep, Glob
---

# clippy-advanced - Advanced Clippy Configuration

Advanced Clippy configuration for comprehensive Rust linting, including custom rules, lint categories, disallowed methods, and IDE integration.

## When to Use This Skill

| Use this skill when... | Use another tool instead when... |
|------------------------|----------------------------------|
| Configuring Clippy lint rules | Formatting code (use rustfmt) |
| Setting up CI linting for Rust | Building/compiling (use cargo build) |
| Customizing clippy.toml | Running tests (use cargo test) |
| Enforcing code standards | Managing dependencies (use cargo add) |

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

## Lint Categories

| Category | Purpose | Default |
|----------|---------|---------|
| `clippy::correctness` | Likely bugs | Deny |
| `clippy::complexity` | Overly complex code | Warn |
| `clippy::perf` | Performance issues | Warn |
| `clippy::style` | Code style | Warn |
| `clippy::suspicious` | Code that looks wrong | Warn |
| `clippy::pedantic` | Opinionated style | Off |
| `clippy::restriction` | Opt-in constraints | Off |
| `clippy::nursery` | Experimental | Off |
| `clippy::cargo` | Cargo.toml issues | Off |

### Recommended Cargo.toml Configuration

```toml
[workspace.lints.clippy]
# Deny correctness issues (likely bugs)
correctness = "deny"
complexity = "warn"
perf = "warn"
style = "warn"
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
unwrap_used = "warn"

# Enable nursery lints (experimental)
use_self = "warn"
```

## clippy.toml Essential Settings

Create `clippy.toml` in project root for thresholds and disallowed items:

```toml
cognitive-complexity-threshold = 15
too-many-lines-threshold = 100
too-many-arguments-threshold = 5

disallowed-methods = [
  { path = "std::env::var", reason = "Use std::env::var_os for better Unicode handling" },
  { path = "std::process::exit", reason = "Use Result propagation instead" },
]

disallowed-names = ["foo", "bar", "baz"]
```

## Lint Suppression

```rust
// Function-level
#[allow(clippy::too_many_arguments)]
fn complex_function(a: i32, b: i32, c: i32, d: i32, e: i32, f: i32) {}

// Module-level (src/lib.rs)
#![warn(clippy::all)]
#![warn(clippy::pedantic)]
#![deny(clippy::unwrap_used)]
#![allow(clippy::module_name_repetitions)]

// Inline
#[allow(clippy::cast_possible_truncation)]
let x = value as u8;
```

## Agentic Optimizations

| Context | Command |
|---------|---------|
| CI strict | `cargo clippy --workspace --all-targets -- -D warnings` |
| JSON output | `cargo clippy --message-format=json` |
| Compact errors | `cargo clippy --message-format=short` |
| Quick check | `cargo clippy --message-format=short -- -D warnings` |
| Pedantic check | `cargo clippy -- -W clippy::pedantic -D clippy::correctness` |

## Quick Reference

### Command-Line Flags

| Flag | Description |
|------|-------------|
| `--all-targets` | Check lib, bins, tests, examples, benches |
| `--all-features` | Enable all features |
| `--workspace` | Check entire workspace |
| `--message-format=json` | JSON output for tooling |
| `--message-format=short` | Compact error format |
| `-- -D warnings` | Treat warnings as errors |
| `-- -W clippy::pedantic` | Enable pedantic lints |
| `-- -A clippy::lint_name` | Allow specific lint |

### Lint Levels

| Level | Attribute | Effect |
|-------|-----------|--------|
| Allow | `#[allow(...)]` | Suppress lint |
| Warn | `#[warn(...)]` | Show warning |
| Deny | `#[deny(...)]` | Compile error |

## References

- [Clippy documentation](https://doc.rust-lang.org/clippy/)
- [Lint list](https://rust-lang.github.io/rust-clippy/master/)
- [Configuration options](https://doc.rust-lang.org/clippy/configuration.html)
- [rust-analyzer integration](https://rust-analyzer.github.io/manual.html)

For detailed configuration examples, CI integration, IDE setup, and best practices, see [REFERENCE.md](REFERENCE.md).
