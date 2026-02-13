---
model: haiku
created: 2025-12-16
modified: 2026-02-11
reviewed: 2025-12-16
name: cargo-machete
description: |
  Detect unused dependencies in Rust projects for cleaner Cargo.toml files and faster builds.
  Use when auditing dependencies, optimizing build times, cleaning up Cargo.toml, or detecting bloat.
  Trigger terms: unused dependencies, cargo-machete, dependency audit, dependency cleanup, bloat detection, cargo-udeps.
allowed-tools: Bash, Read, Grep, Glob
---

# cargo-machete - Unused Dependency Detection

Detect and remove unused dependencies in Rust projects using cargo-machete.

## When to Use This Skill

| Use this skill when... | Use X instead when... |
|------------------------|----------------------|
| Auditing for unused dependencies | Checking for outdated deps -- use `cargo outdated` |
| Cleaning up Cargo.toml | Auditing security vulnerabilities -- use `cargo audit` |
| Optimizing build times by removing bloat | Checking license compliance -- use `cargo deny` |
| Verifying deps in CI | Need nightly-accurate analysis -- use `cargo +nightly udeps` |

## Context

- Cargo.toml: !`test -f Cargo.toml && echo "EXISTS" || echo "MISSING"`
- Workspace: !`grep -q '\[workspace\]' Cargo.toml 2>/dev/null && echo "YES" || echo "NO"`
- cargo-machete installed: !`cargo machete --version 2>/dev/null || echo "NOT INSTALLED"`
- Machete config: !`test -f .cargo-machete.toml && echo "EXISTS" || echo "MISSING"`
- Workspace members: !`grep -A 20 '^\[workspace\]' Cargo.toml 2>/dev/null | grep -o '"[^"]*"' 2>/dev/null`

## Execution

Execute this unused dependency analysis:

### Step 1: Verify installation

Check if cargo-machete is installed (see Context above). If not installed, install it:

```bash
cargo install cargo-machete
```

### Step 2: Run dependency analysis

Run cargo-machete with metadata for detailed output:

```bash
# Single crate
cargo machete --with-metadata

# Workspace (if Context shows workspace)
cargo machete --workspace --with-metadata
```

### Step 3: Evaluate results

Review the output and classify each finding:

| Finding | Action |
|---------|--------|
| Genuinely unused dependency | Remove with `--fix` or manually |
| Proc-macro dependency (e.g., serde derive) | Add `machete:ignore` comment |
| Build.rs-only dependency | Move to `[build-dependencies]` |
| Re-exported dependency | Add `machete:ignore` comment with explanation |

### Step 4: Apply fixes

For confirmed unused dependencies, auto-remove them:

```bash
cargo machete --fix
```

For false positives, add ignore annotations in `Cargo.toml`:

```toml
serde = "1.0"  # machete:ignore - used via derive macro
```

Or create `.cargo-machete.toml` for project-wide ignores:

```toml
[ignore]
dependencies = ["serde", "log"]
```

### Step 5: Verify build

After removing dependencies, confirm everything still compiles:

```bash
cargo check --all-targets
cargo test --no-run
```

## False Positive Handling

| Scenario | Solution |
|----------|----------|
| Proc-macro deps (e.g., serde derive) | `machete:ignore` comment |
| Build.rs-only deps | Move to `[build-dependencies]` |
| Re-exported deps | `machete:ignore` comment with explanation |
| Example/bench-only deps | Verify in `[dev-dependencies]` |

## Comparison with cargo-udeps

| Feature | cargo-machete | cargo-udeps |
|---------|---------------|-------------|
| Accuracy | Good | Excellent |
| Speed | Very fast | Slower |
| Rust version | Stable | Requires nightly |
| False positives | Some | Fewer |

Use cargo-machete for fast CI checks. Use cargo-udeps for thorough audits:

```bash
cargo +nightly udeps --workspace --all-features
```

## Agentic Optimizations

| Context | Command |
|---------|---------|
| Quick check | `cargo machete` |
| Detailed check | `cargo machete --with-metadata` |
| Workspace check | `cargo machete --workspace --with-metadata` |
| Auto-fix | `cargo machete --fix` |
| Verify after fix | `cargo check --all-targets` |
| Accurate check (nightly) | `cargo +nightly udeps --workspace` |

## Quick Reference

| Flag | Description |
|------|-------------|
| `--with-metadata` | Show detailed output with versions and locations |
| `--fix` | Auto-remove unused dependencies from Cargo.toml |
| `--workspace` | Check all workspace members |
| `-p <crate>` | Check specific workspace member |
| `--exclude <crate>` | Exclude specific workspace member |

## Troubleshooting

| Problem | Solution |
|---------|----------|
| Proc macro flagged as unused | Add `machete:ignore` comment in Cargo.toml |
| Build.rs dep flagged | Move to `[build-dependencies]` |
| Re-exported dep flagged | Add `machete:ignore` with explanation |
| Need more accuracy | Use `cargo +nightly udeps` |

For CI integration patterns, configuration file examples, pre-commit setup, and Makefile integration, see [REFERENCE.md](REFERENCE.md).
