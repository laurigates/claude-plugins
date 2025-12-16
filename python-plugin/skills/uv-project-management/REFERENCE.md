# UV Project Management - Comprehensive Reference

Complete guide to UV project lifecycle and dependency management.

## Table of Contents

1. [Project Initialization](#project-initialization)
2. [Dependency Management](#dependency-management)
3. [Lockfile Operations](#lockfile-operations)
4. [Environment Synchronization](#environment-synchronization)
5. [Running Commands](#running-commands)
6. [Configuration](#configuration)
7. [Common Workflows](#common-workflows)
8. [Troubleshooting](#troubleshooting)
9. [Best Practices](#best-practices)
10. [Migration Guides](#migration-guides)

---

## Project Initialization

### Creating New Projects

```bash
# Basic project initialization
uv init my-project

# Initialize in existing directory
cd existing-project
uv init

# Specify Python version
uv init --python 3.11 my-app
uv init --python 3.12 my-app

# Initialize library (no src layout)
uv init --lib my-library

# Initialize application (with src layout)
uv init --app my-application
```

### Generated Project Structure

**Application (default):**
```
my-project/
├── pyproject.toml
├── README.md
├── .python-version      # Optional, if --python specified
└── src/
    └── my_project/
        ├── __init__.py
        └── __main__.py
```

**Library:**
```
my-library/
├── pyproject.toml
├── README.md
└── my_library/
    └── __init__.py
```

### Initial pyproject.toml

```toml
[project]
name = "my-project"
version = "0.1.0"
description = "Add your description here"
readme = "README.md"
requires-python = ">=3.11"
dependencies = []

[build-system]
requires = ["uv_build>=0.9.2,<0.10.0"]
build-backend = "uv_build"
```

---

## Dependency Management

### Adding Dependencies

**Basic Addition:**
```bash
# Add single package (latest version)
uv add requests

# Add with version constraint
uv add 'flask>=2.0'
uv add 'django>=4.0,<5.0'
uv add 'requests==2.31.0'

# Add multiple packages
uv add httpx aiohttp requests
```

**Development Dependencies:**
```bash
# Add to dev dependencies
uv add --dev pytest
uv add --dev pytest pytest-cov black ruff mypy

# Alternative syntax
uv add -d pytest
```

**Optional Dependency Groups:**
```bash
# Add to named group
uv add --group docs sphinx sphinx-rtd-theme
uv add --group test pytest pytest-asyncio

# Groups are defined in pyproject.toml:
# [dependency-groups]
# docs = ["sphinx>=7.0", "sphinx-rtd-theme"]
# test = ["pytest>=7.0", "pytest-asyncio"]
```

**Extras (Optional Features):**
```bash
# Install package with extras
uv add 'fastapi[all]'
uv add 'mkdocs[i18n]'
uv add 'sqlalchemy[postgresql,mypy]'
```

### Removing Dependencies

```bash
# Remove single dependency
uv remove requests

# Remove multiple dependencies
uv remove flask requests django

# Remove from specific group
uv remove --group docs sphinx
```

### Migrating from requirements.txt

```bash
# Add all requirements
uv add -r requirements.txt

# Add dev requirements
uv add --dev -r requirements-dev.txt

# Add optional group
uv add --group test -r requirements-test.txt
```

### Updating pyproject.toml Manually

After manual edits to `pyproject.toml`, synchronize:

```bash
# Update lockfile and install
uv sync

# Just update lockfile
uv lock
```

**Example pyproject.toml with dependencies:**
```toml
[project]
dependencies = [
    "fastapi>=0.110.0",
    "uvicorn[standard]>=0.27.0",
    "pydantic>=2.0.0",
    "sqlalchemy>=2.0.0",
]

[dependency-groups]
dev = [
    "pytest>=7.4.0",
    "pytest-asyncio>=0.21.0",
    "ruff>=0.1.0",
    "mypy>=1.7.0",
]
docs = [
    "mkdocs-material>=9.0.0",
    "mkdocstrings[python]>=0.24.0",
]
```

---

## Lockfile Operations

### Understanding uv.lock

The `uv.lock` file:
- **Pins exact versions** of all dependencies (direct and transitive)
- **Ensures reproducibility** across environments
- **Tracks package hashes** for security
- **Auto-generated** - use uv commands to update
- **Should be committed** to version control

### Creating and Updating Lockfiles

```bash
# Create or update lockfile
uv lock

# Update specific package
uv lock --upgrade-package requests

# Update multiple packages
uv lock --upgrade-package requests --upgrade-package flask

# Upgrade all dependencies
uv lock --upgrade

# Lock without installing
uv lock --no-install
```

### Lockfile Behavior

**Frozen Mode:**
```bash
# Use existing lockfile without updating
uv lock --frozen

# Error if changes needed
uv sync --frozen
```

**Locked Mode:**
```bash
# Error if lockfile is out of date
uv sync --locked
```

### Lockfile in CI/CD

**Recommended CI approach:**
```bash
# Option 1: Verify lockfile is up to date
uv lock --locked

# Option 2: Use frozen mode
uv sync --frozen
```

**GitHub Actions example:**
```yaml
- name: Install dependencies
  run: uv sync --frozen

- name: Verify lockfile
  run: uv lock --locked
```

---

## Environment Synchronization

### sync Command

The `uv sync` command:
1. Reads `uv.lock` (creating it if needed)
2. Creates or updates `.venv/`
3. Installs all locked dependencies
4. Removes packages not in lockfile

```bash
# Standard sync (default behavior)
uv sync

# Sync without updating lockfile
uv sync --frozen

# Error if lockfile needs update
uv sync --locked

# Sync only specific groups
uv sync --group docs
uv sync --group dev --group test

# Sync without dev dependencies
uv sync --no-dev

# Sync and include all groups
uv sync --all-groups
```

### Virtual Environment Management

UV automatically manages virtual environments:

```bash
# Environment created at
.venv/

# Activate manually (optional)
source .venv/bin/activate  # Unix
.venv\Scripts\activate     # Windows

# Deactivate
deactivate
```

**UV handles activation automatically** with `uv run`, so manual activation is rarely needed.

### Clean Reinstall

```bash
# Remove virtual environment
rm -rf .venv

# Recreate from lockfile
uv sync
```

---

## Running Scripts

For running Python scripts, see the **uv-run** skill which covers:
- `uv run script.py` - Direct script execution
- `uv run --with pkg script.py` - Temporary dependencies
- PEP 723 inline script dependencies
- Shebang patterns for executable scripts

---

## Configuration

### pyproject.toml Structure

```toml
[project]
name = "my-project"
version = "0.1.0"
description = "Project description"
readme = "README.md"
requires-python = ">=3.11"
license = {text = "MIT"}
authors = [
    {name = "Your Name", email = "you@example.com"}
]
keywords = ["python", "package"]
classifiers = [
    "Programming Language :: Python :: 3",
    "License :: OSI Approved :: MIT License",
]

# Core dependencies
dependencies = [
    "fastapi>=0.110.0",
    "uvicorn[standard]>=0.27.0",
]

# Entry points
[project.scripts]
my-cli = "my_project.cli:main"

# Optional features
[project.optional-dependencies]
dev = ["pytest>=7.0", "ruff>=0.1"]

# Modern dependency groups (preferred)
[dependency-groups]
dev = ["pytest>=7.0", "ruff>=0.1"]
docs = ["mkdocs-material>=9.0"]

# UV-specific configuration
[tool.uv]
dev-dependencies = []  # Legacy, use dependency-groups
```

### UV Configuration Options

```toml
[tool.uv]
# Python version constraints
python = ">=3.11"

# Index configuration
index-url = "https://pypi.org/simple"
extra-index-url = ["https://custom.pypi.org/simple"]

# Package resolution
no-build = ["numpy", "scipy"]  # Use wheels only
no-binary = ["pillow"]  # Build from source

# Environment
no-cache = false
cache-dir = ".uv-cache"
```

---

## Common Workflows

### Starting a New Web Application

```bash
# Initialize project
uv init my-api && cd my-api

# Add framework and dependencies
uv add fastapi 'uvicorn[standard]' pydantic sqlalchemy

# Add development tools
uv add --dev pytest pytest-asyncio pytest-cov ruff mypy

# Add documentation
uv add --group docs mkdocs-material mkdocstrings

# Run development server
uv run uvicorn my_api.main:app --reload
```

### Daily Development Workflow

```bash
# Pull latest changes
git pull

# Sync dependencies
uv sync

# Run tests
uv run pytest

# Run linter
uv run ruff check

# Run type checker
uv run mypy src/
```

### Updating Dependencies

```bash
# Check for updates
uv lock --upgrade --dry-run

# Update specific package
uv lock --upgrade-package fastapi
uv sync

# Update all packages
uv lock --upgrade
uv sync

# Verify tests still pass
uv run pytest
```

### Preparing for Production

```bash
# Lock dependencies
uv lock

# Verify lockfile is valid
uv sync --frozen

# Run full test suite
uv run pytest

# Commit lockfile
git add uv.lock pyproject.toml
git commit -m "chore: update dependencies"
```

### CI/CD Pipeline

```yaml
name: CI

on: [push, pull_request]

jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Install UV
        uses: astral-sh/setup-uv@v1

      - name: Install dependencies
        run: uv sync --frozen

      - name: Run tests
        run: uv run pytest

      - name: Run linter
        run: uv run ruff check

      - name: Type check
        run: uv run mypy src/
```

---

## Troubleshooting

### Common Issues

**Issue: `uv.lock` out of date**
```bash
# Solution: Regenerate lockfile
uv lock
```

**Issue: Dependency conflicts**
```bash
# Check resolution
uv lock --verbose

# Try upgrading conflicting packages
uv lock --upgrade-package problematic-package
```

**Issue: Virtual environment corrupted**
```bash
# Recreate environment
rm -rf .venv
uv sync
```

**Issue: Package not found**
```bash
# Check package name and version
uv add 'package-name>=1.0'

# Try explicit index
uv add --index-url https://pypi.org/simple package-name
```

**Issue: Slow dependency resolution**
```bash
# Use existing lockfile
uv sync --frozen

# Clear cache
rm -rf ~/.cache/uv
uv sync
```

### Debugging

```bash
# Verbose output
uv add requests --verbose

# Very verbose (includes HTTP)
uv sync -vv

# Check environment
uv run python -c "import sys; print(sys.executable)"
uv run python -c "import requests; print(requests.__version__)"
```

### Cache Management

```bash
# Show cache location
uv cache dir

# Clear cache
uv cache clean

# Show cache size
du -sh $(uv cache dir)
```

---

## Best Practices

### 1. Commit Lock Files

**Always commit `uv.lock`** to version control:
```bash
git add uv.lock pyproject.toml
git commit -m "chore: update dependencies"
```

### 2. Use Dependency Groups

Prefer modern `[dependency-groups]` over `[project.optional-dependencies]`:

```toml
[dependency-groups]
dev = ["pytest", "ruff", "mypy"]
docs = ["mkdocs-material"]
```

### 3. Pin Python Version

Specify required Python version:
```toml
[project]
requires-python = ">=3.11"
```

Or pin exact version:
```bash
uv python pin 3.11
```

### 4. Use Version Constraints

```toml
dependencies = [
    "fastapi>=0.110.0,<1.0.0",  # Allow minor updates
    "pydantic>=2.0.0",           # Allow all 2.x versions
    "requests==2.31.0",          # Pin exact version (rare)
]
```

### 5. Separate Dev Dependencies

```toml
[dependency-groups]
dev = [
    "pytest>=7.4.0",
    "pytest-cov>=4.1.0",
    "ruff>=0.1.0",
]
```

### 6. Use `uv sync --frozen` in CI

Ensures CI uses exact locked versions:
```yaml
- run: uv sync --frozen
```

### 7. Regular Updates

```bash
# Weekly dependency updates
uv lock --upgrade
uv sync
uv run pytest
```

### 8. Document Custom Indexes

```toml
[tool.uv]
extra-index-url = [
    "https://custom.pypi.org/simple",  # Corporate packages
]
```

---

## Migration Guides

### From pip + requirements.txt

**Before (pip):**
```bash
pip install -r requirements.txt
pip install -r requirements-dev.txt
```

**After (UV):**
```bash
# One-time migration
uv init
uv add -r requirements.txt
uv add --dev -r requirements-dev.txt

# Delete old files
rm requirements.txt requirements-dev.txt

# Daily use
uv sync
uv run pytest
```

### From Poetry

**Before (Poetry):**
```bash
poetry install
poetry add requests
poetry run pytest
```

**After (UV):**
```bash
# One-time migration
uv init
# Manually copy dependencies from pyproject.toml [tool.poetry.dependencies]
uv sync

# Daily use
uv add requests
uv run pytest
```

**Note:** UV's `pyproject.toml` format is similar but not identical to Poetry's.

### From Pipenv

**Before (Pipenv):**
```bash
pipenv install
pipenv install --dev pytest
pipenv run python script.py
```

**After (UV):**
```bash
# One-time migration
uv init
# Manually migrate from Pipfile

# Daily use
uv add --dev pytest
uv run python script.py
```

---

## Performance Tips

### 1. Use `--frozen` When Possible

Skip lockfile updates for faster installs:
```bash
uv sync --frozen
```

### 2. Leverage Cache

UV caches wheels and built packages:
```bash
# Cache location
uv cache dir

# Pre-populate cache in CI
uv sync
```

### 3. Parallelize CI Jobs

```yaml
strategy:
  matrix:
    python-version: ["3.11", "3.12"]
```

### 4. Use Wheels

Prefer binary wheels over source distributions:
```toml
[tool.uv]
prefer-binary = true
```

---

## Advanced Topics

### Resolution Strategies

```toml
[tool.uv]
# Highest compatible versions (default)
resolution = "highest"

# Lowest compatible versions
resolution = "lowest"

# Lowest with direct highest
resolution = "lowest-direct"
```

### Build Configuration

```toml
[tool.uv]
# Skip building these packages
no-build = ["numpy", "scipy"]

# Don't use binary wheels
no-binary = ["pillow"]

# Require hashes
require-hashes = true
```

### Private Package Indexes

```toml
[tool.uv]
index-url = "https://pypi.org/simple"
extra-index-url = [
    "https://${PRIVATE_INDEX_TOKEN}@private.pypi.org/simple",
]
```

Set token via environment:
```bash
export PRIVATE_INDEX_TOKEN="secret"
uv sync
```

---

## Related Skills

- **uv-python-versions** - Installing and managing Python interpreters
- **uv-workspaces** - Monorepo and multi-package management
- **uv-advanced-dependencies** - Git, path, and constraint dependencies
- **uv-tool-management** - Global tool installation
- **python-testing** - Testing with pytest
- **python-code-quality** - Linting and formatting
- **python-packaging** - Building and publishing packages

---

## References

- **Official Documentation**: https://docs.astral.sh/uv/
- **GitHub Repository**: https://github.com/astral-sh/uv
- **PEP 723** (Inline Script Metadata): https://peps.python.org/pep-0723/
- **pyproject.toml Spec**: https://packaging.python.org/specifications/pyproject-toml/
