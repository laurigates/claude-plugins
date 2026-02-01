---
model: haiku
created: 2026-01-29
modified: 2026-01-29
reviewed: 2026-01-29
name: ty Type Checking
description: |
  Python type checking with ty, Astral's extremely fast type checker (10-100x faster than mypy/Pyright).
  Use when checking Python types, configuring type checking rules, or setting up type checking in projects.
  Triggered by: ty, type checking, type errors, static analysis, mypy alternative, pyright alternative.
allowed-tools: Bash(ty *), Bash(python *), Bash(uv *), Read, Edit, Write, Grep, Glob, TodoWrite
---

# ty Type Checking

Expert knowledge for using `ty` as an extremely fast Python type checker from Astral (creators of uv and ruff).

## When to Use This Skill

| Use this skill when... | Use basedpyright instead when... | Use mypy instead when... |
|------------------------|----------------------------------|--------------------------|
| Want fastest type checking (10-100x faster) | Need strictest defaults out of box | Need extensive plugin ecosystem |
| Using Astral toolchain (uv, ruff) | Want Microsoft-backed alternative | Have legacy mypy configuration |
| Need excellent diagnostics | Need Pylance compatibility | Require mypy-specific plugins |
| Want incremental/watch mode | Team prefers Pyright conventions | Need Django/Pydantic mypy plugins |
| Setting up new Python project | Already using basedpyright | Existing mypy expertise |

## Core Expertise

**ty Advantages**
- Extremely fast (10-100x faster than mypy and Pyright)
- Written in Rust for performance
- Best-in-class diagnostic messages inspired by Rust compiler
- Incremental analysis optimized for IDE workflows
- Built-in LSP for editor integration
- First-class intersection types
- Advanced type narrowing and reachability analysis
- Part of Astral ecosystem (uv, ruff)

## Installation

### Via uv (Recommended)

```bash
# Install globally as tool
uv tool install ty@latest

# Run without installing
uvx ty check

# Install as dev dependency
uv add --dev ty
```

### Via pip

```bash
pip install ty
```

### VS Code Extension

Install the `astral-sh.ty` extension from the VS Code marketplace.

## Basic Usage

### Type Checking

```bash
# Check current directory
ty check

# Check specific files or directories
ty check src/
ty check src/ tests/
ty check path/to/file.py

# Verbose output
ty check --verbose

# Hide progress indicators
ty check --hide-progress
```

### Output Control

```bash
# Default output with diagnostics
ty check

# Hide progress spinners (useful for CI)
ty check --hide-progress

# Verbose mode for debugging
ty check --verbose
```

## Configuration

### pyproject.toml

```toml
[tool.ty]
# Python version targeting
python-version = "3.12"

# Files to exclude
exclude = [
    "**/__pycache__",
    "**/.venv",
    "**/node_modules",
    "tests/fixtures/**",
]

[tool.ty.rules]
# Configure rule severity: "error", "warn", or "ignore"
index-out-of-bounds = "error"
possibly-unbound = "warn"
unknown-type = "ignore"
```

### ty.toml (standalone)

```toml
# ty.toml takes precedence over pyproject.toml
python-version = "3.12"

exclude = [
    "**/__pycache__",
    "**/.venv",
]

[rules]
index-out-of-bounds = "error"
possibly-unbound = "warn"
```

### Configuration Hierarchy

1. Command-line arguments (highest priority)
2. `ty.toml` in current directory
3. `pyproject.toml` `[tool.ty]` section
4. User config: `~/.config/ty/ty.toml` (Linux) or `%APPDATA%\ty\ty.toml` (Windows)
5. ty defaults (lowest priority)

## CLI Options

### Core Options

| Flag | Description |
|------|-------------|
| `--python <VERSION>` | Python environment/version to use |
| `--project <PATH>` | Run within given project directory |
| `--config <PATH>` | Path to ty.toml configuration file |
| `--verbose` | Enable verbose output |
| `--hide-progress` | Hide progress spinners/bars |

### Rule Configuration

| Flag | Description |
|------|-------------|
| `--error <RULE>` | Treat rule as error severity |
| `--warn <RULE>` | Treat rule as warning severity |
| `--ignore <RULE>` | Ignore rule completely |

### File Selection

| Flag | Description |
|------|-------------|
| `--exclude <PATTERN>` | Glob patterns for files to exclude |
| `--respect-ignore-files` | Respect .gitignore (default) |
| `--no-respect-ignore-files` | Ignore .gitignore files |

## Editor Integration

### VS Code

1. Install extension: `astral-sh.ty`
2. ty provides LSP with:
   - Real-time type checking
   - Go to Definition
   - Auto-complete with type hints
   - Auto-import suggestions
   - Rename symbol
   - Inlay hints
   - Semantic highlighting

### Neovim

```lua
-- Using nvim-lspconfig
require("lspconfig").ty.setup({
  settings = {
    ty = {
      -- Configuration options
    }
  }
})
```

### PyCharm

ty provides a PyCharm plugin for IDE integration.

## CI Integration

### GitHub Actions

```yaml
name: Type Check

on: [push, pull_request]

jobs:
  type-check:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Install uv
        uses: astral-sh/setup-uv@v2
        with:
          enable-cache: true

      - name: Run ty
        run: uvx ty check --hide-progress
```

### Pre-commit Hook

```yaml
# .pre-commit-config.yaml
repos:
  - repo: https://github.com/astral-sh/ty
    rev: v0.0.10
    hooks:
      - id: ty
```

### GitLab CI

```yaml
ty-check:
  stage: test
  image: python:3.12
  before_script:
    - pip install ty
  script:
    - ty check --hide-progress
```

## Common Patterns

### Quick Type Check

```bash
# Fast check of current project
ty check

# Check specific module
ty check src/api/

# Check with custom Python version
ty check --python 3.11
```

### Configuring Rule Severity

```bash
# Make specific rules errors
ty check --error index-out-of-bounds --error possibly-unbound

# Ignore noisy rules
ty check --ignore unknown-type

# Mix severities
ty check --error division-by-zero --warn possibly-unbound --ignore unknown-type
```

### Excluding Files

```bash
# Exclude test fixtures
ty check --exclude "tests/fixtures/**"

# Exclude multiple patterns
ty check --exclude "**/*_test.py" --exclude "**/conftest.py"

# Don't respect .gitignore
ty check --no-respect-ignore-files
```

## Comparison with Other Type Checkers

### Performance

| Type Checker | Relative Speed | Notes |
|--------------|----------------|-------|
| ty | 1x (baseline) | Fastest, Rust-based |
| Pyright | 10-60x slower | Good performance |
| mypy | 10-100x slower | Slower but mature |

In editor (after file edit):
- ty: ~5ms to recompute diagnostics
- Pyright: ~400ms
- mypy: Several seconds

### Feature Comparison

| Feature | ty | basedpyright | mypy |
|---------|----|--------------| -----|
| Speed | Fastest | Fast | Moderate |
| LSP | Built-in | Built-in | dmypy |
| Diagnostics | Excellent | Good | Basic |
| Plugin system | Limited | Limited | Extensive |
| Intersection types | First-class | Partial | Limited |
| Ecosystem | Astral (uv, ruff) | Microsoft | Standalone |

## Migration

### From mypy

```toml
# mypy.ini / [tool.mypy]
[mypy]
python_version = 3.12
strict = true
warn_unused_ignores = true

# Equivalent ty configuration
[tool.ty]
python-version = "3.12"

[tool.ty.rules]
# Configure equivalent strictness via rules
```

### From Pyright/basedpyright

```toml
# [tool.pyright] or [tool.basedpyright]
[tool.basedpyright]
pythonVersion = "3.12"
typeCheckingMode = "strict"

# Equivalent ty configuration
[tool.ty]
python-version = "3.12"

[tool.ty.rules]
# Configure strictness via rules
```

## Best Practices

### 1. Use with Astral Toolchain

```bash
# Combine with uv and ruff for complete workflow
uv init my-project && cd my-project
uv add --dev ty ruff
uv run ty check
uv run ruff check --fix
```

### 2. Configure Project-Level Settings

```toml
# pyproject.toml - recommended setup
[tool.ty]
python-version = "3.12"
exclude = [
    "**/__pycache__",
    "**/.venv",
    "**/build",
    "**/dist",
]

[tool.ty.rules]
# Start with defaults, adjust as needed
```

### 3. CI with Hide Progress

```bash
# Always use --hide-progress in CI for cleaner logs
ty check --hide-progress
```

### 4. Incremental Adoption

```bash
# Start by checking new code only
ty check src/new_module/

# Gradually expand coverage
ty check src/
```

## Agentic Optimizations

| Context | Command |
|---------|---------|
| Quick check | `ty check` |
| CI check | `ty check --hide-progress` |
| Verbose debug | `ty check --verbose` |
| Check module | `ty check src/module/` |
| Strict errors | `ty check --error possibly-unbound` |
| Ignore rule | `ty check --ignore unknown-type` |

## Quick Reference

### Essential Commands

```bash
# Basic type checking
ty check                          # Check current directory
ty check src/                     # Check specific directory
ty check file.py                  # Check specific file

# Configuration
ty check --config ty.toml         # Use custom config
ty check --python 3.12            # Specify Python version

# Output control
ty check --verbose                # Verbose output
ty check --hide-progress          # No progress indicators

# Rule control
ty check --error RULE             # Treat as error
ty check --warn RULE              # Treat as warning
ty check --ignore RULE            # Ignore rule

# File selection
ty check --exclude "pattern"      # Exclude files
```

### Minimal Configuration

```toml
# pyproject.toml
[tool.ty]
python-version = "3.12"
exclude = ["**/__pycache__", "**/.venv"]
```

## See Also

- **basedpyright-type-checking** - Alternative type checker with stricter defaults
- **ruff-linting** - Fast linting from same ecosystem
- **ruff-formatting** - Fast formatting from same ecosystem
- **python-development** - General Python development patterns

## References

- Official docs: https://docs.astral.sh/ty/
- GitHub: https://github.com/astral-sh/ty
- Blog announcement: https://astral.sh/blog/ty
- Playground: https://play.ty.dev/
