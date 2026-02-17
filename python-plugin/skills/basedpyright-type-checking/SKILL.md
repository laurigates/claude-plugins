---
model: haiku
created: 2025-12-16
modified: 2026-02-14
reviewed: 2025-12-16
name: basedpyright-type-checking
description: |
  Basedpyright static type checker configuration, installation, and usage patterns.
  Use when implementing type checking, configuring LSP, comparing type checkers,
  or setting up strict type validation in Python projects.
  Triggered by: basedpyright, pyright, type checking, LSP, mypy alternative, static analysis.
allowed-tools: Bash, Read, Grep, Glob
---

# Basedpyright Type Checking

Basedpyright is a fork of Pyright with additional features and stricter defaults, designed for maximum type safety and performance.

## When to Use This Skill

| Use this skill when... | Use another tool instead when... |
|------------------------|----------------------------------|
| Setting up type checking for Python | Formatting code (use ruff format) |
| Configuring strict type validation | Linting for style issues (use ruff check) |
| Comparing type checkers (basedpyright vs mypy) | Detecting unused code (use vulture/deadcode) |
| Setting up LSP for type-aware editor support | Running tests (use pytest) |

## Installation

### Via uv (Recommended)
```bash
# Install globally
uv tool install basedpyright

# Install as dev dependency
uv add --dev basedpyright

# Run with uv
uv run basedpyright
```

### Via pipx
```bash
pipx install basedpyright
```

## Basic Usage

```bash
# Check entire project
basedpyright

# Check specific files/directories
basedpyright src/ tests/

# Watch mode for development
basedpyright --watch

# Output JSON for tooling integration
basedpyright --outputjson

# Verbose diagnostics
basedpyright --verbose
```

## Configuration

### Minimal Strict Configuration (pyproject.toml)

```toml
[tool.basedpyright]
typeCheckingMode = "strict"
pythonVersion = "3.12"
include = ["src"]
exclude = ["**/__pycache__", "**/.venv"]

# Basedpyright-specific strict rules
reportUnusedCallResult = "error"
reportImplicitStringConcatenation = "error"
reportMissingSuperCall = "error"
reportUninitializedInstanceVariable = "error"
```

## Type Checking Modes

| Mode | Description | Use Case |
|------|-------------|----------|
| `off` | No type checking | Legacy code, migration start |
| `basic` | Basic type checking | Gradual typing adoption |
| `standard` | Standard strictness | Most projects (default Pyright) |
| `strict` | Strict type checking | Type-safe codebases |
| `all` | Maximum strictness | High-assurance systems |

### Progressive Type Checking

```toml
# Start with basic mode
[tool.basedpyright]
typeCheckingMode = "basic"
include = ["src/new_module"]  # Type check new code only

# Gradually expand
include = ["src/new_module", "src/api"]

# Eventually enable strict mode
typeCheckingMode = "strict"
include = ["src"]
```

## Choosing a Type Checker

| Factor | Basedpyright | Pyright | mypy |
|--------|-------------|---------|------|
| **Speed** | Fastest | Fastest | Slower |
| **Strictness** | Strictest defaults | Configurable | Configurable |
| **LSP Support** | Built-in | Built-in | Via dmypy |
| **Plugin System** | Limited | Limited | Extensive |

**Choose Basedpyright** for maximum type safety with stricter defaults and fastest speed.
**Choose Pyright** for Microsoft's official support and VS Code Pylance compatibility.
**Choose mypy** for extensive plugin ecosystem (django-stubs, pydantic-mypy).

## Inline Error Suppression

```python
# Inline type ignore
result = unsafe_operation()  # type: ignore[reportUnknownVariableType]

# Function-level ignore
def legacy_function():  # basedpyright: ignore
    pass
```

## Agentic Optimizations

| Context | Command |
|---------|---------|
| Quick check | `basedpyright` |
| JSON output | `basedpyright --outputjson` |
| Watch mode | `basedpyright --watch` |
| CI check | `uv run basedpyright` |
| Verbose | `basedpyright --verbose` |

## Quick Reference

| Flag | Description |
|------|-------------|
| `--watch` | Watch mode for development |
| `--outputjson` | JSON output for tooling |
| `--verbose` | Verbose diagnostics |
| `--pythonversion X.Y` | Override Python version |
| `--level <mode>` | Override type checking mode |

For detailed configuration options, LSP integration, migration guides, CI setup, and best practices, see [REFERENCE.md](REFERENCE.md).
