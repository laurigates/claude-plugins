---
model: haiku
created: 2025-12-16
modified: 2026-02-14
reviewed: 2025-12-16
name: ruff-formatting
description: Python code formatting with ruff format. Fast, Black-compatible formatting for consistent code style. Use when formatting Python files, enforcing style, or checking format compliance.
allowed-tools: Bash(ruff *), Bash(python *), Bash(uv *), Read, Edit, Write, Grep, Glob
---

# ruff Formatting

Expert knowledge for using `ruff format` as an extremely fast Python code formatter with Black compatibility.

## When to Use This Skill

| Use this skill when... | Use another tool instead when... |
|------------------------|----------------------------------|
| Formatting Python files | Linting for code issues (use ruff check) |
| Checking format compliance in CI | Type checking (use basedpyright) |
| Migrating from Black | Detecting dead code (use vulture/deadcode) |
| Setting up format-on-save | Running tests (use pytest) |

## Core Expertise

**ruff format Advantages**
- 10-30x faster than Black
- Drop-in Black replacement (99.9% compatible)
- Written in Rust for performance
- Supports Black's configuration options
- Format checking and diff preview
- Respects `.gitignore` automatically

## Basic Usage

### Simple Formatting
```bash
# Format current directory
ruff format

# Format specific files or directories
ruff format path/to/file.py
ruff format src/ tests/

# IMPORTANT: Pass directory as parameter to stay in repo root
ruff format services/orchestrator
```

### Format Checking
```bash
# Check if files are formatted (exit code 1 if not)
ruff format --check

# Show diff without modifying files
ruff format --diff

# Check specific files
ruff format --check src/ tests/

# Preview changes before applying
ruff format --diff services/orchestrator
ruff format services/orchestrator  # Apply after review
```

### Selective Formatting
```bash
# Format only Python files
ruff format src/**/*.py

# Format excluding tests
ruff format --exclude tests/

# Format only changed files (git)
git diff --name-only --diff-filter=d | grep '\.py$' | xargs ruff format

# Format files in specific directory
ruff format src/core/ src/utils/
```

## Configuration

### pyproject.toml
```toml
[tool.ruff]
line-length = 88
target-version = "py39"

[tool.ruff.format]
quote-style = "double"
indent-style = "space"
skip-magic-trailing-comma = false
line-ending = "auto"
docstring-code-format = true
docstring-code-line-length = "dynamic"
exclude = [
    "*.pyi",
    "**/__pycache__",
    "**/node_modules",
    ".venv",
]
```

### ruff.toml (standalone)
```toml
line-length = 88

[format]
quote-style = "single"
indent-style = "space"
skip-magic-trailing-comma = false
docstring-code-format = true
```

### Black Compatibility
```toml
[tool.ruff]
line-length = 88
indent-width = 4
target-version = "py39"

[tool.ruff.format]
quote-style = "double"
indent-style = "space"
skip-magic-trailing-comma = false
line-ending = "auto"
```

## Format Workflow

1. **Preview**: `ruff format --diff` (see changes)
2. **Check**: `ruff format --check` (CI validation)
3. **Apply**: `ruff format` (modify files)
4. **Verify**: `ruff format --check` (confirm)

## Best Practices

- Pass directory parameter directly: `ruff format src/`
- Preview changes first with `--diff`
- Use one formatter per project (ruff format replaces Black)
- Exclude generated files in `pyproject.toml`
- Keep pre-commit config in sync with formatter choice
- Enable `docstring-code-format` for better docs

## Agentic Optimizations

| Context | Command |
|---------|---------|
| Format directory | `ruff format src/` |
| Check formatting | `ruff format --check` |
| Show diff | `ruff format --diff` |
| CI check + diff | `ruff format --check --diff` |
| Format + lint | `ruff format && ruff check` |
| Format changed files | `git diff --name-only --diff-filter=d \| grep '\.py$' \| xargs ruff format` |

## Quick Reference

### Essential Commands

```bash
ruff format                         # Format current directory
ruff format path/to/dir             # Format specific directory
ruff format --check                 # Check if formatted
ruff format --diff                  # Show formatting changes
ruff format file1.py file2.py       # Format specific files
ruff format --exclude tests/        # Exclude directory
ruff format --line-length 100       # Override line length
```

### Format vs Check

| Command | Purpose | Exit Code | Modifies Files |
|---------|---------|-----------|----------------|
| `ruff format` | Format files | 0 | Yes |
| `ruff format --check` | Validate formatting | 1 if unformatted | No |
| `ruff format --diff` | Show changes | 0 | No |
| `ruff format --check --diff` | Validate + show | 1 if unformatted | No |

### Configuration Quick Start

**Minimal (Black-compatible)**
```toml
[tool.ruff]
line-length = 88

[tool.ruff.format]
quote-style = "double"
indent-style = "space"
```

**Recommended**
```toml
[tool.ruff]
line-length = 88
target-version = "py311"

[tool.ruff.format]
quote-style = "double"
indent-style = "space"
skip-magic-trailing-comma = false
docstring-code-format = true
line-ending = "auto"
exclude = [
    "*.pyi",
    "migrations/**/*.py",
]
```

For detailed examples, advanced patterns, integration guides, and migration checklists, see [REFERENCE.md](REFERENCE.md).
