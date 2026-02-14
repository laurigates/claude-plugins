---
model: haiku
created: 2025-12-16
modified: 2026-02-06
reviewed: 2025-12-16
name: vulture-dead-code
description: |
  Vulture and deadcode tools for detecting unused Python code (functions, classes, variables, imports).
  Use when cleaning up codebases, removing unused code, or enforcing code hygiene in CI.
  Triggered by: vulture, deadcode, dead code detection, unused code, code cleanup, remove unused.
allowed-tools: Bash, Read, Grep, Glob
---

# Vulture and deadcode - Dead Code Detection

Tools for finding unused Python code including functions, classes, variables, imports, and attributes.

## When to Use This Skill

| Use this skill when... | Use another tool instead when... |
|------------------------|----------------------------------|
| Detecting unused functions, classes, variables | Finding unused imports only (use `ruff --select F401`) |
| Cleaning up dead code in a codebase | Checking type correctness (use basedpyright) |
| Enforcing code hygiene in CI | Formatting code (use ruff format) |
| Generating whitelists for false positives | Running general linting (use ruff check) |

## Overview

**Vulture** (mature, confidence-based) and **deadcode** (newer, AST-based) both detect unused code but with different approaches:

| Feature | Vulture | deadcode |
|---------|---------|----------|
| **Approach** | Static analysis + confidence scores | AST-based detection |
| **Accuracy** | Confidence scores (60-100%) | High accuracy, fewer false positives |
| **Speed** | Fast | Very fast |
| **Configuration** | Whitelist files | TOML configuration |
| **Maturity** | Mature (2012) | Newer (2023+) |
| **Best For** | Large codebases, gradual cleanup | New projects, strict enforcement |

## Installation

```bash
# Install vulture
uv add --dev vulture

# Install deadcode (newer alternative)
uv add --dev deadcode

# Install both for comparison
uv add --dev vulture deadcode
```

## Vulture - Confidence-Based Detection

### Basic Usage

```bash
# Check entire project
vulture .

# Check specific files/directories
vulture src/ tests/

# Minimum confidence threshold (60-100%)
vulture --min-confidence 80 .

# Exclude patterns
vulture . --exclude "**/migrations/*,**/tests/*"

# Sort by confidence
vulture --sort-by-size .

# Generate whitelist of current issues
vulture . --make-whitelist > vulture_whitelist.py
```

### Configuration (pyproject.toml)

```toml
[tool.vulture]
min_confidence = 80
paths = ["src", "tests"]
exclude = [
    "**/migrations/*",
    "**/__pycache__/*",
    ".venv/*"
]
ignore_decorators = [
    "@app.route",
    "@pytest.fixture",
    "@property",
    "@staticmethod",
    "@classmethod"
]
ignore_names = [
    "test_*",
    "setUp*",
    "tearDown*",
]
```

## deadcode - AST-Based Detection

### Basic Usage

```bash
# Check entire project
deadcode .

# Check specific files/directories
deadcode src/

# Verbose output
deadcode --verbose .

# Dry run (show what would be removed)
deadcode --dry-run .

# Show unreachable code
deadcode --show-unreachable .

# Generate configuration
deadcode --init
```

### Configuration (pyproject.toml)

```toml
[tool.deadcode]
paths = ["src"]
exclude = [
    "tests/*",
    "**/__pycache__/*",
    "**/migrations/*",
]
ignore_names = [
    "test_*",
    "setUp",
    "tearDown",
    "main",
]
ignore_decorators = [
    "app.route",
    "pytest.fixture",
    "property",
    "staticmethod",
    "classmethod",
    "abstractmethod"
]
show_unreachable = false
```

## Choosing Between Tools

| Choose Vulture when... | Choose deadcode when... |
|------------------------|------------------------|
| Large, mature codebases | New projects |
| Need confidence-based filtering | Want fewer false positives |
| Need whitelist file approach | Prefer TOML configuration |
| Dynamic code (getattr, exec) | Need unreachable code detection |

### Hybrid Approach

```bash
# Run both for comprehensive detection
vulture --min-confidence 80 .
deadcode .
```

## Agentic Optimizations

| Context | Command |
|---------|---------|
| Quick vulture check | `vulture --min-confidence 90 .` |
| Quick deadcode check | `deadcode .` |
| Generate whitelist | `vulture . --make-whitelist > vulture_whitelist.py` |
| CI enforcement | `vulture --min-confidence 80 . vulture_whitelist.py` |
| Unreachable code | `deadcode --show-unreachable .` |
| Combined check | `vulture --min-confidence 80 . && deadcode .` |

## Quick Reference

### Vulture Flags

| Flag | Description |
|------|-------------|
| `--min-confidence N` | Minimum confidence (60-100%) |
| `--exclude PATTERN` | Exclude glob patterns |
| `--sort-by-size` | Sort results by size |
| `--make-whitelist` | Generate whitelist file |

### deadcode Flags

| Flag | Description |
|------|-------------|
| `--verbose` | Verbose output |
| `--dry-run` | Show without modifying |
| `--show-unreachable` | Detect unreachable code |
| `--init` | Generate configuration |
| `--strict` | Strict enforcement mode |

For detailed examples, advanced patterns, and best practices, see [REFERENCE.md](REFERENCE.md).
