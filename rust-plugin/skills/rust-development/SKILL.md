---
name: rust-development
description: |
  Modern Rust development with cargo, rustc, clippy, rustfmt, async programming, and
  memory-safe systems programming. Covers ownership patterns, fearless concurrency,
  and the modern Rust ecosystem including Tokio, Serde, and popular crates.
  Use when user mentions Rust, cargo, rustc, clippy, rustfmt, ownership, borrowing,
  lifetimes, async Rust, or Rust crates.
allowed-tools: Glob, Grep, Read, Bash, Edit, Write, TodoWrite, WebFetch, WebSearch, BashOutput, KillShell
---

# Rust Development

Expert knowledge for modern systems programming with Rust, focusing on memory safety, fearless concurrency, and zero-cost abstractions.

## Core Expertise

**Modern Rust Ecosystem**
- **Cargo**: Build system, package manager, and workspace management
- **Rustc**: Compiler optimization, target management, and cross-compilation
- **Clippy**: Linting for idiomatic code and performance improvements
- **Rustfmt**: Consistent code formatting following Rust style guidelines
- **Rust-analyzer**: Advanced IDE support with LSP integration

**Language Features**
- Rust 2024 edition: RPITIT, async fn in traits, impl Trait improvements
- Const generics and compile-time computation
- Generic associated types (GATs)
- Let-else patterns and if-let chains

## Key Capabilities

**Ownership & Memory Safety**
- Implement ownership patterns with borrowing and lifetimes
- Design zero-copy abstractions and efficient memory layouts
- Apply RAII patterns through Drop trait and smart pointers (Box, Rc, Arc)
- Leverage interior mutability patterns (Cell, RefCell, Mutex, RwLock)
- Use Pin/Unpin for self-referential structures

**Async Programming & Concurrency**
- **Tokio**: Async runtime for high-performance network applications
- **async-std**: Alternative async runtime with familiar API design
- **Futures**: Composable async abstractions and stream processing
- **Rayon**: Data parallelism with work-stealing thread pools
- Design lock-free data structures with atomics and memory ordering

**Error Handling & Type Safety**
- Design comprehensive error types with thiserror and anyhow
- Implement Result<T, E> and Option<T> patterns effectively
- Use pattern matching for exhaustive error handling
- Apply type-state patterns for compile-time guarantees

**Performance Optimization**
- Profile with cargo-flamegraph, perf, and criterion benchmarks
- Optimize with SIMD intrinsics and auto-vectorization
- Implement zero-cost abstractions and inline optimizations
- Use unsafe code judiciously with proper safety documentation

**Testing & Quality Assurance**
- **Unit Testing**: #[test] modules with assertions
- **Integration Testing**: tests/ directory for end-to-end validation
- **Criterion**: Micro-benchmarking with statistical analysis
- **Miri**: Undefined behavior detection in unsafe code
- **Fuzzing**: cargo-fuzz for security and robustness testing

## Essential Commands

```bash
# Project setup
cargo new my-project      # Binary crate
cargo new my-lib --lib    # Library crate
cargo init                # Initialize in existing directory

# Development workflow
cargo build                      # Debug build
cargo build --release           # Optimized build
cargo run                       # Build and run
cargo run --release             # Run optimized
cargo test                      # Run all tests
cargo test --lib               # Library tests only
cargo bench                     # Run benchmarks

# Code quality
cargo clippy                    # Lint code
cargo clippy -- -W clippy::pedantic  # Stricter lints
cargo fmt                       # Format code
cargo fmt --check              # Check formatting
cargo fix                       # Auto-fix warnings

# Dependencies
cargo add serde --features derive  # Add dependency
cargo update                       # Update deps
cargo audit                        # Security audit
cargo deny check                   # License/advisory check

# Advanced tools
cargo expand                    # Macro expansion
cargo flamegraph               # Profile with flame graph
cargo doc --open               # Generate and open docs
cargo miri test                # Check for UB

# Cross-compilation
rustup target add wasm32-unknown-unknown
cargo build --target wasm32-unknown-unknown
```

## Best Practices

**Idiomatic Rust Patterns**
```rust
// Use iterators over manual loops
let sum: i32 = numbers.iter().filter(|x| **x > 0).sum();

// Prefer combinators for Option/Result
let value = config.get("key")
    .and_then(|v| v.parse().ok())
    .unwrap_or_default();

// Use pattern matching effectively
match result {
    Ok(value) if value > 0 => process(value),
    Ok(_) => handle_zero(),
    Err(e) => return Err(e.into()),
}

// Let-else for early returns
let Some(config) = load_config() else {
    return Err(ConfigError::NotFound);
};
```

**Project Structure**
```
my-project/
├── Cargo.toml
├── src/
│   ├── lib.rs        # Library root
│   ├── main.rs       # Binary entry point
│   ├── error.rs      # Error types
│   └── modules/
│       └── mod.rs
├── tests/            # Integration tests
├── benches/          # Benchmarks
└── examples/         # Example programs
```

**Error Handling**
```rust
use thiserror::Error;

#[derive(Error, Debug)]
pub enum AppError {
    #[error("IO error: {0}")]
    Io(#[from] std::io::Error),

    #[error("parse error: {message}")]
    Parse { message: String },

    #[error("not found: {0}")]
    NotFound(String),
}

pub type Result<T> = std::result::Result<T, AppError>;
```

**Common Crates**
| Crate | Purpose |
|-------|---------|
| `serde` | Serialization/deserialization |
| `tokio` | Async runtime |
| `reqwest` | HTTP client |
| `sqlx` | Async SQL |
| `clap` | CLI argument parsing |
| `tracing` | Logging/diagnostics |
| `anyhow` | Application errors |
| `thiserror` | Library errors |

For detailed async patterns, unsafe code guidelines, WebAssembly compilation, embedded development, and advanced debugging, see REFERENCE.md.
