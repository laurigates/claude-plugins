---
name: ruff Formatting
description: Python code formatting with ruff format. Fast, Black-compatible formatting for consistent code style. Use when formatting Python files, enforcing style, or checking format compliance.
allowed-tools: Bash, Read, Edit, Write, Grep, Glob
---

# ruff Formatting

Expert knowledge for using `ruff format` as an extremely fast Python code formatter with Black compatibility.

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
# ✅ Good
ruff format services/orchestrator

# ❌ Bad
cd services/orchestrator && ruff format
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
[tool.ruff.format]
# Quote style
quote-style = "double"  # or "single"

# Indentation
indent-style = "space"  # or "tab"

# Line endings
line-ending = "auto"  # or "lf", "cr-lf", "native"

# Magic trailing comma handling
skip-magic-trailing-comma = false

# Format docstring code examples
docstring-code-format = true

# Docstring code line length
docstring-code-line-length = "dynamic"  # or number like 80

# Exclude patterns
exclude = [
    "*.pyi",           # Type stubs
    "**/__pycache__",
    "**/node_modules",
    ".venv",
]
```

### ruff.toml (standalone)
```toml
# Line length (affects both formatting and linting)
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
# Same as Black defaults
line-length = 88
indent-width = 4
target-version = "py39"

[tool.ruff.format]
quote-style = "double"
indent-style = "space"
skip-magic-trailing-comma = false
line-ending = "auto"
```

## Advanced Features

### Quote Styles
```bash
# Use single quotes
ruff format --config '[format]\nquote-style = "single"'

# Use double quotes (Black default)
ruff format --config '[format]\nquote-style = "double"'

# Preserve existing quotes (not recommended)
# Not supported - ruff enforces consistency
```

**Quote Style Behavior**
```python
# double quotes (default)
greeting = "Hello, world!"
name = "Alice"

# single quotes
greeting = 'Hello, world!'
name = 'Alice'

# Triple quotes always use double (Black compatibility)
docstring = """
This is a docstring.
Always uses double quotes.
"""
```

### Indentation Styles
```toml
[tool.ruff.format]
# Space indentation (default, recommended)
indent-style = "space"

# Tab indentation (not recommended)
indent-style = "tab"
```

### Line Endings
```toml
[tool.ruff.format]
# Auto-detect from existing files (default)
line-ending = "auto"

# Force Unix line endings (LF)
line-ending = "lf"

# Force Windows line endings (CRLF)
line-ending = "cr-lf"

# Use platform native
line-ending = "native"
```

### Docstring Code Formatting
```toml
[tool.ruff.format]
# Format code in docstrings (default: false)
docstring-code-format = true

# Control line length for docstring code
docstring-code-line-length = "dynamic"  # Uses main line-length
# or
docstring-code-line-length = 80  # Fixed length
```

**Example**
```python
def example():
    """
    Example function.

    ```python
    # This code will be formatted when docstring-code-format = true
    result = calculate(
        x=1,
        y=2,
        z=3,
    )
    ```
    """
    pass
```

### Magic Trailing Comma
```python
# When skip-magic-trailing-comma = false (default)
# Trailing comma forces multi-line
items = [
    "apple",
    "banana",
    "cherry",  # ← This comma forces expansion
]

# Without trailing comma, can be single-line
items = ["apple", "banana", "cherry"]

# When skip-magic-trailing-comma = true
# Trailing comma is ignored, formatter decides layout
```

## Integration Patterns

### Pre-commit Hook
```yaml
# .pre-commit-config.yaml
repos:
  - repo: https://github.com/astral-sh/ruff-pre-commit
    rev: v0.14.0
    hooks:
      # Formatter
      - id: ruff-format
        types_or: [python, pyi]

      # Advanced configuration
      - id: ruff-format
        args:
          - --config=pyproject.toml
        types_or: [python, pyi]
```

### GitHub Actions
```yaml
# .github/workflows/format.yml
name: Format Check

on: [push, pull_request]

jobs:
  format:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Install ruff
        run: pip install ruff

      - name: Check formatting
        run: ruff format --check

      # Or with auto-commit
      - name: Format code
        run: ruff format

      - name: Commit changes
        if: failure()
        run: |
          git config user.name "github-actions"
          git config user.email "github-actions@github.com"
          git add .
          git commit -m "Auto-format with ruff"
          git push
```

### GitLab CI
```yaml
# .gitlab-ci.yml
Ruff Format:
  stage: build
  image: ghcr.io/astral-sh/ruff:0.14.0-alpine
  script:
    - ruff format --check --diff
  allow_failure: false
```

### Editor Integration

#### VS Code
```json
// .vscode/settings.json
{
  "[python]": {
    "editor.formatOnSave": true,
    "editor.defaultFormatter": "charliermarsh.ruff"
  },
  "ruff.format.args": [
    "--line-length=100"
  ]
}
```

#### Neovim
```lua
-- Using nvimf-lint and conform.nvim
require("conform").setup({
  formatters_by_ft = {
    python = { "ruff_format" },
  },
  format_on_save = {
    timeout_ms = 500,
    lsp_fallback = true,
  },
})
```

## Common Patterns

### Format Check in CI
```bash
# Exit with error if not formatted
ruff format --check

# Show what would change
ruff format --diff

# Both check and show diff
ruff format --check --diff
```

### Format Only Changed Files
```bash
# Git: Format only modified files
git diff --name-only --diff-filter=d | grep '\.py$' | xargs ruff format

# Git: Format files in current branch
git diff --name-only main...HEAD | grep '\.py$' | xargs ruff format

# Git: Format staged files
git diff --cached --name-only --diff-filter=d | grep '\.py$' | xargs ruff format
```

### Parallel Formatting
```bash
# Format multiple directories in parallel
ruff format src/ &
ruff format tests/ &
ruff format scripts/ &
wait

# Or use find with parallel
find src tests -name "*.py" -print0 | xargs -0 -P 4 ruff format
```

### Combined with Linting
```bash
# Format first, then lint
ruff format && ruff check

# Format and lint with fixes
ruff format && ruff check --fix

# Check both without modifying
ruff format --check && ruff check
```

### Migration from Black
```bash
# 1. Update dependencies
pip uninstall black
pip install ruff

# 2. Keep Black configuration
# ruff respects [tool.black] in pyproject.toml

# 3. Test formatting
ruff format --diff

# 4. Format entire codebase
ruff format .

# 5. Update pre-commit config
# Replace black with ruff-format
```

## Excluding Files

### Configuration-based
```toml
[tool.ruff.format]
exclude = [
    "*.pyi",                    # Type stubs
    "**/node_modules",          # Dependencies
    ".venv",                    # Virtual environment
    "**/__pycache__",           # Cache
    "**/migrations/*.py",       # Django migrations
    "generated/**/*.py",        # Generated code
]
```

### Command-line
```bash
# Exclude patterns
ruff format --exclude "migrations" --exclude "*.pyi"

# Multiple patterns
ruff format --exclude "{migrations,node_modules,generated}"

# Using extend-exclude (add to defaults)
ruff format --extend-exclude "legacy/"
```

## Notebook Support

### Jupyter Notebooks
```bash
# Format Jupyter notebooks
ruff format notebook.ipynb

# Check notebook formatting
ruff format --check *.ipynb

# Exclude notebooks
ruff format --exclude "*.ipynb"
```

**Configuration**
```toml
[tool.ruff.format]
# Include notebooks by default
# Exclude if needed:
exclude = ["*.ipynb"]

[tool.ruff.lint.per-file-ignores]
"*.ipynb" = ["E501"]  # Ignore line length in notebooks
```

## Best Practices

**When to Use ruff format**
- Pre-commit formatting
- CI/CD format checking
- Editor format-on-save
- Codebase reformatting
- Migration from Black

**Critical: Directory Parameters**
- ✅ **Always** pass directory as parameter: `ruff format services/orchestrator`
- ❌ **Never** use cd: `cd services/orchestrator && ruff format`
- Reason: Parallel execution, clearer output, tool compatibility

**Format Workflow**
1. **Preview**: `ruff format --diff` (see changes)
2. **Check**: `ruff format --check` (CI validation)
3. **Apply**: `ruff format` (modify files)
4. **Verify**: `ruff format --check` (confirm)

**Configuration Strategy**
1. Start with Black defaults (88 char line length)
2. Adjust quote-style if team prefers single quotes
3. Enable docstring-code-format for better docs
4. Use auto line-ending detection
5. Exclude generated code and type stubs

**Common Mistakes to Avoid**
- Using `cd` instead of passing directory parameter
- Not previewing with `--diff` before formatting
- Mixing formatters (Black and ruff format)
- Not excluding generated files
- Forgetting to update pre-commit config

**Black Migration Checklist**
- [ ] Remove Black from dependencies
- [ ] Add ruff to dependencies
- [ ] Update pre-commit config (black → ruff-format)
- [ ] Update CI/CD pipelines
- [ ] Test with `ruff format --diff`
- [ ] Format entire codebase
- [ ] Update editor configuration
- [ ] Document in team guidelines

## Quick Reference

### Essential Commands

```bash
# Basic operations
ruff format                         # Format current directory
ruff format path/to/dir             # Format specific directory
ruff format --check                 # Check if formatted
ruff format --diff                  # Show formatting changes

# File operations
ruff format file1.py file2.py       # Format specific files
ruff format src/ tests/             # Format multiple directories
ruff format --exclude tests/        # Exclude directory

# Configuration
ruff format --config path/to/ruff.toml  # Custom config
ruff format --line-length 100          # Override line length
```

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

### Format vs Check

| Command | Purpose | Exit Code | Modifies Files |
|---------|---------|-----------|----------------|
| `ruff format` | Format files | 0 | Yes |
| `ruff format --check` | Validate formatting | 1 if unformatted | No |
| `ruff format --diff` | Show changes | 0 | No |
| `ruff format --check --diff` | Validate + show | 1 if unformatted | No |

This makes ruff format the preferred tool for fast, consistent Python code formatting.
