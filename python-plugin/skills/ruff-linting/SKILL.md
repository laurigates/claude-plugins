---
name: ruff Linting
description: Python code quality with ruff linter. Fast linting, rule selection, auto-fixing, and configuration. Use when checking Python code quality, enforcing standards, or finding bugs.
allowed-tools: Bash, Read, Edit, Write, Grep, Glob
---

# ruff Linting

Expert knowledge for using `ruff check` as an extremely fast Python linter with comprehensive rule support and automatic fixing.

## Core Expertise

**ruff Advantages**
- Extremely fast (10-100x faster than Flake8)
- Written in Rust for performance
- Replaces multiple tools (Flake8, pylint, isort, pyupgrade, etc.)
- Auto-fix capabilities for many rules
- Compatible with existing configurations
- Over 800 built-in rules

## Basic Usage

### Simple Linting
```bash
# Lint current directory
ruff check

# Lint specific files or directories
ruff check path/to/file.py
ruff check src/ tests/

# IMPORTANT: Pass directory as parameter to stay in repo root
# ✅ Good
ruff check services/orchestrator

# ❌ Bad
cd services/orchestrator && ruff check
```

### Auto-Fixing
```bash
# Show what would be fixed (diff preview)
ruff check --diff

# Apply safe automatic fixes
ruff check --fix

# Fix specific files
ruff check --fix src/main.py

# Fix with preview (see changes before applying)
ruff check --diff services/orchestrator
ruff check --fix services/orchestrator
```

### Output Formats
```bash
# Default output
ruff check

# Show statistics
ruff check --statistics

# JSON output for tooling
ruff check --output-format json

# GitHub Actions annotations
ruff check --output-format github

# GitLab Code Quality report
ruff check --output-format gitlab

# Concise output
ruff check --output-format concise
```

## Rule Selection

### Common Rule Codes

| Code | Description | Example Rules |
|------|-------------|---------------|
| `E` | pycodestyle errors | E501 (line too long) |
| `F` | Pyflakes | F401 (unused import) |
| `W` | pycodestyle warnings | W605 (invalid escape) |
| `B` | flake8-bugbear | B006 (mutable default) |
| `I` | isort | I001 (unsorted imports) |
| `UP` | pyupgrade | UP006 (deprecated types) |
| `SIM` | flake8-simplify | SIM102 (nested if) |
| `D` | pydocstyle | D100 (missing docstring) |
| `N` | pep8-naming | N806 (variable naming) |
| `S` | flake8-bandit (security) | S101 (assert usage) |
| `C4` | flake8-comprehensions | C400 (unnecessary generator) |

### Selecting Rules
```bash
# Select specific rules at runtime
ruff check --select E,F,B,I

# Extend default selection
ruff check --extend-select UP,SIM

# Ignore specific rules
ruff check --ignore E501,E402

# Show which rules would apply
ruff rule --all

# Explain a specific rule
ruff rule F401
```

### Rule Queries
```bash
# List all available rules
ruff rule --all

# Search for rules by pattern
ruff rule --all | grep "import"

# Get detailed rule explanation
ruff rule F401
# Output: unused-import (F401)
#   Derived from the Pyflakes linter.
#   Checks for unused imports.

# List all linters
ruff linter

# JSON output for automation
ruff rule F401 --output-format json
```

## Configuration

### pyproject.toml
```toml
[tool.ruff]
# Line length limit (same as Black)
line-length = 88

# Target Python version
target-version = "py311"

# Exclude directories
exclude = [
    ".git",
    ".venv",
    "__pycache__",
    "build",
    "dist",
]

[tool.ruff.lint]
# Enable specific rule sets
select = [
    "E",   # pycodestyle errors
    "F",   # Pyflakes
    "B",   # flake8-bugbear
    "I",   # isort
    "UP",  # pyupgrade
    "SIM", # flake8-simplify
]

# Disable specific rules
ignore = [
    "E501",  # Line too long (handled by formatter)
    "B008",  # Function calls in argument defaults
]

# Allow automatic fixes
fixable = ["ALL"]
unfixable = ["B"]  # Don't auto-fix bugbear rules

# Per-file ignores
[tool.ruff.lint.per-file-ignores]
"__init__.py" = ["F401", "E402"]
"tests/**/*.py" = ["S101"]  # Allow assert in tests
```

### ruff.toml (standalone)
```toml
# Same options as pyproject.toml but without [tool.ruff] prefix
line-length = 100
target-version = "py39"

[lint]
select = ["E", "F", "B"]
ignore = ["E501"]

[lint.isort]
known-first-party = ["myapp"]
force-single-line = true
```

## Advanced Usage

### Per-File Configuration
```bash
# Override settings for specific paths
ruff check --config path/to/ruff.toml

# Use inline configuration
ruff check --select E,F,B --ignore E501
```

### Targeting Specific Issues
```bash
# Check only specific rule codes
ruff check --select F401,F841  # Only unused imports/variables

# Security-focused check
ruff check --select S  # All bandit rules

# Import organization only
ruff check --select I --fix

# Docstring checks
ruff check --select D
```

### Integration Patterns
```bash
# Check only changed files (git)
git diff --name-only --diff-filter=d | grep '\.py$' | xargs ruff check

# Check files modified in branch
git diff --name-only main...HEAD | grep '\.py$' | xargs ruff check

# Parallel checking of multiple directories
ruff check src/ &
ruff check tests/ &
wait

# Combine with other tools
ruff check && pytest && mypy
```

## CI/CD Integration

### Pre-commit Hook
```yaml
# .pre-commit-config.yaml
repos:
  - repo: https://github.com/astral-sh/ruff-pre-commit
    rev: v0.14.0
    hooks:
      # Linter with auto-fix
      - id: ruff-check
        args: [--fix]

      # Advanced configuration
      - id: ruff-check
        name: Ruff linter
        args:
          - --fix
          - --config=pyproject.toml
          - --select=E,F,B,I
        types_or: [python, pyi, jupyter]
```

### GitHub Actions
```yaml
# .github/workflows/lint.yml
name: Lint

on: [push, pull_request]

jobs:
  lint:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - uses: astral-sh/ruff-action@v3
        with:
          args: 'check --output-format github'
          changed-files: 'true'

      # Or using pip
      - name: Install ruff
        run: pip install ruff

      - name: Run linter
        run: ruff check --output-format github
```

### GitLab CI
```yaml
# .gitlab-ci.yml
Ruff Check:
  stage: build
  image: ghcr.io/astral-sh/ruff:0.14.0-alpine
  script:
    - ruff check --output-format=gitlab > code-quality-report.json
  artifacts:
    reports:
      codequality: code-quality-report.json
```

## Common Patterns

### Finding Specific Issues
```bash
# Find unused imports
ruff check --select F401

# Find mutable default arguments
ruff check --select B006

# Find deprecated type usage
ruff check --select UP006

# Security issues
ruff check --select S

# Code complexity
ruff check --select C901

# Find all TODOs
ruff check --select FIX  # flake8-fixme
```

### Gradual Adoption
```bash
# Start with minimal rules
ruff check --select E,F

# Add bugbear
ruff check --select E,F,B

# Add import sorting
ruff check --select E,F,B,I --fix

# Add pyupgrade
ruff check --select E,F,B,I,UP --fix

# Generate baseline configuration
ruff check --select ALL --ignore <violations> > ruff-baseline.toml
```

### Refactoring Support
```bash
# Auto-fix all safe violations
ruff check --fix

# Preview changes before fixing
ruff check --diff | less

# Fix only imports
ruff check --select I --fix

# Modernize code
ruff check --select UP --fix

# Simplify comprehensions
ruff check --select C4,SIM --fix
```

## Plugin Configuration

### isort (Import Sorting)
```toml
[tool.ruff.lint.isort]
combine-as-imports = true
known-first-party = ["myapp"]
section-order = ["future", "standard-library", "third-party", "first-party", "local-folder"]
```

### flake8-quotes
```toml
[tool.ruff.lint.flake8-quotes]
docstring-quotes = "double"
inline-quotes = "single"
multiline-quotes = "double"
```

### pydocstyle
```toml
[tool.ruff.lint.pydocstyle]
convention = "google"  # or "numpy", "pep257"
```

### pylint
```toml
[tool.ruff.lint.pylint]
max-args = 10
max-branches = 15
max-returns = 8
max-statements = 60
```

## Best Practices

**When to Use ruff check**
- Code quality enforcement
- Pre-commit validation
- CI/CD pipelines
- Refactoring assistance
- Security scanning
- Import organization

**Critical: Directory Parameters**
- ✅ **Always** pass directory as parameter: `ruff check services/orchestrator`
- ❌ **Never** use cd: `cd services/orchestrator && ruff check`
- Reason: Parallel execution, clearer output, tool compatibility

**Rule Selection Strategy**
1. Start minimal: `select = ["E", "F"]` (errors + pyflakes)
2. Add bugbear: `select = ["E", "F", "B"]`
3. Add imports: `select = ["E", "F", "B", "I"]`
4. Add pyupgrade: `select = ["E", "F", "B", "I", "UP"]`
5. Consider security: `select = ["E", "F", "B", "I", "UP", "S"]`

**Fixable vs Unfixable**
- Mark uncertain rules as `unfixable` to review manually
- Common unfixables: `B` (bugbear), `F` (pyflakes F401)
- Let ruff fix safe rules: `I` (isort), `UP` (pyupgrade)

**Common Mistakes to Avoid**
- Using `cd` instead of passing directory parameter
- Enabling ALL rules immediately (use gradual adoption)
- Not using `--diff` before `--fix`
- Ignoring rule explanations (`ruff rule <code>`)
- Not configuring per-file ignores for special cases

## Quick Reference

### Essential Commands

```bash
# Basic operations
ruff check                          # Lint current directory
ruff check path/to/dir              # Lint specific directory
ruff check --diff                   # Show fix preview
ruff check --fix                    # Apply fixes

# Rule management
ruff rule --all                     # List all rules
ruff rule F401                      # Explain rule F401
ruff linter                         # List all linters

# Output formats
ruff check --statistics             # Show violation counts
ruff check --output-format json     # JSON output
ruff check --output-format github   # GitHub Actions format

# Selection
ruff check --select E,F,B          # Select rules
ruff check --ignore E501           # Ignore rules
ruff check --extend-select UP      # Extend selection
```

### Configuration Hierarchy

1. Command-line arguments (highest priority)
2. `ruff.toml` in current directory
3. `pyproject.toml` in current directory
4. Parent directory configs (recursive)
5. User config: `~/.config/ruff/ruff.toml`

### Common Rule Combinations

```bash
# Minimal safety
ruff check --select E,F

# Good default
ruff check --select E,F,B,I

# Comprehensive
ruff check --select E,F,B,I,UP,SIM

# Security-focused
ruff check --select E,F,B,S

# Docstring enforcement
ruff check --select D --config '[lint.pydocstyle]\nconvention = "google"'
```

This makes ruff check the preferred tool for fast, comprehensive Python code linting.
