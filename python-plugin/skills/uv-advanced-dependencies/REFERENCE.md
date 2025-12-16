# UV Advanced Dependencies - Comprehensive Reference

Complete guide to advanced dependency scenarios in UV projects.

## Table of Contents

1. [Git Dependencies](#git-dependencies)
2. [Path Dependencies](#path-dependencies)
3. [URL Dependencies](#url-dependencies)
4. [Dependency Groups](#dependency-groups)
5. [Optional Dependencies (Extras)](#optional-dependencies-extras)
6. [Constraint Files](#constraint-files)
7. [Custom Package Indexes](#custom-package-indexes)
8. [Build Dependencies](#build-dependencies)
9. [Resolution Strategies](#resolution-strategies)
10. [Best Practices](#best-practices)

---

## Git Dependencies

### Adding Git Dependencies

```bash
# HTTPS
uv add git+https://github.com/psf/requests

# SSH
uv add git+ssh://git@github.com/user/repo.git

# With subdirectory
uv add 'git+https://github.com/user/mono.git#subdirectory=packages/lib'
```

### Specifying Refs

```bash
# Branch
uv add git+https://github.com/user/repo@main
uv add git+https://github.com/user/repo@develop

# Tag
uv add git+https://github.com/user/repo@v1.0.0

# Commit SHA
uv add git+https://github.com/user/repo@abc1234567890
```

### pyproject.toml Configuration

```toml
[project]
dependencies = ["my-package"]

[tool.uv.sources]
my-package = { git = "https://github.com/user/my-package" }

# Branch
my-package = { git = "https://github.com/user/my-package", branch = "main" }

# Tag
my-package = { git = "https://github.com/user/my-package", tag = "v2.0.0" }

# Commit
my-package = { git = "https://github.com/user/my-package", rev = "abc1234" }

# Subdirectory
my-package = { git = "https://github.com/user/mono", subdirectory = "packages/lib" }
```

### Authentication

```bash
# SSH keys (recommended)
uv add git+ssh://git@github.com/user/private-repo.git

# HTTPS with token
export GIT_TOKEN="ghp_..."
uv add git+https://${GIT_TOKEN}@github.com/user/private-repo.git

# Git credentials helper
git config --global credential.helper store
```

---

## Path Dependencies

### Adding Path Dependencies

```bash
# Relative path (editable by default)
uv add ../my-local-package
uv add ./local-lib

# Absolute path
uv add /home/user/projects/my-package

# Explicit editable
uv add --editable ./local-package

# Non-editable
uv add --no-editable ./local-package
```

### pyproject.toml Configuration

```toml
[project]
dependencies = ["my-local"]

[tool.uv.sources]
my-local = { path = "../my-local" }

# Editable (default for local paths)
my-local = { path = "../my-local", editable = true }

# Non-editable
my-local = { path = "../my-local", editable = false }
```

### Use Cases

**Development workflow:**
```bash
# Clone dependency
git clone https://github.com/user/lib.git ../lib

# Add as editable
uv add --editable ../lib

# Changes to ../lib immediately available
```

**Monorepo:**
```toml
[tool.uv.sources]
my-core = { path = "packages/core" }
my-utils = { path = "packages/utils" }
```

---

## URL Dependencies

### Direct URLs

```bash
# HTTP/HTTPS URL
uv add https://example.com/package-1.0.tar.gz

# Wheel file
uv add https://example.com/package-1.0-py3-none-any.whl
```

### pyproject.toml Configuration

```toml
[project]
dependencies = ["my-package"]

[tool.uv.sources]
my-package = { url = "https://example.com/my-package-1.0.tar.gz" }
```

### Find Links

```toml
[tool.uv]
find-links = [
    "https://download.pytorch.org/whl/cu118",
    "file:///local/packages/",
]
```

---

## Dependency Groups

### Modern Dependency Groups

```toml
[dependency-groups]
dev = [
    "pytest>=7.0",
    "pytest-cov>=4.0",
    "ruff>=0.1.0",
    "mypy>=1.7",
]
docs = [
    "mkdocs-material>=9.0",
    "mkdocstrings[python]>=0.24",
]
test = [
    "pytest-asyncio>=0.21",
    "httpx>=0.25",
]
```

### Installing Groups

```bash
# Install specific group
uv sync --group docs

# Multiple groups
uv sync --group dev --group test

# All groups
uv sync --all-groups

# Exclude dev (production)
uv sync --no-dev
```

### Legacy Optional Dependencies

```toml
[project.optional-dependencies]
dev = ["pytest", "ruff"]
docs = ["mkdocs"]
```

```bash
# Install extras
uv pip install -e .[dev]
uv sync --extra dev
```

---

## Optional Dependencies (Extras)

### Defining Extras

```toml
[project.optional-dependencies]
postgresql = ["psycopg2>=2.9"]
mysql = ["PyMySQL>=1.1"]
all = [
    "psycopg2>=2.9",
    "PyMySQL>=1.1",
]
```

### Installing with Extras

```bash
# Single extra
uv add 'sqlalchemy[postgresql]'

# Multiple extras
uv add 'fastapi[all]'
uv add 'sqlalchemy[postgresql,mypy]'

# In requirements
uv pip install 'package[extra1,extra2]'
```

---

## Constraint Files

### Creating Constraints

```
# constraints.txt
numpy<2.0
pandas==2.0.3
scipy>=1.11,<2.0
```

### Applying Constraints

```bash
# During compilation
uv pip compile requirements.in --constraint constraints.txt

# During installation
uv pip install -r requirements.txt --constraint constraints.txt
```

### Build Constraints

```
# build-constraints.txt
setuptools==75.0.0
wheel==0.42.0
```

```bash
uv pip compile pyproject.toml --build-constraint build-constraints.txt
```

---

## Custom Package Indexes

### Configuration

```toml
[tool.uv]
# Primary index
index-url = "https://pypi.org/simple"

# Additional indexes (searched in order)
extra-index-url = [
    "https://custom.pypi.org/simple",
    "https://corporate.packages.com/simple",
]
```

### Private Indexes with Authentication

```toml
[tool.uv]
extra-index-url = [
    "https://${PRIVATE_TOKEN}@private.pypi.org/simple",
]
```

```bash
# Set token
export PRIVATE_TOKEN="secret-token"
uv sync
```

### Per-Package Index

```toml
[tool.uv.sources]
my-package = { index = "custom-index" }

[[tool.uv.index]]
name = "custom-index"
url = "https://custom.pypi.org/simple"
```

---

## Build Dependencies

### Build System Configuration

```toml
[build-system]
requires = [
    "setuptools>=68",
    "setuptools-scm>=8",
    "wheel",
]
build-backend = "setuptools.build_meta"
```

### Build Dependencies with Constraints

```toml
[build-system]
requires = [
    "hatchling>=1.18",
    "numpy>=2.0; python_version>='3.9'",
]
```

---

## Resolution Strategies

### Configuration

```toml
[tool.uv]
# Highest compatible versions (default)
resolution = "highest"

# Lowest compatible versions
resolution = "lowest"

# Lowest direct, highest transitive
resolution = "lowest-direct"
```

### Use Cases

**Highest (default):**
- Normal development
- Get latest features and fixes

**Lowest:**
- Test minimum supported versions
- Ensure compatibility

**Lowest-direct:**
- Conservative updates
- Stable dependencies

---

## Best Practices

### 1. Prefer PyPI When Possible

```bash
# ✅ Good
uv add requests

# ⚠️ Use only when needed
uv add git+https://github.com/psf/requests
```

### 2. Pin Git Dependencies

```toml
# ❌ Bad - unstable
my-package = { git = "https://github.com/user/pkg", branch = "main" }

# ✅ Good - stable
my-package = { git = "https://github.com/user/pkg", tag = "v1.0.0" }
my-package = { git = "https://github.com/user/pkg", rev = "abc1234" }
```

### 3. Document Custom Sources

```toml
# pyproject.toml
[tool.uv.sources]
# Corporate package repository
my-internal = { index = "corporate" }

# Development dependency from local checkout
my-dev-lib = { path = "../my-dev-lib", editable = true }
```

### 4. Use Dependency Groups

```toml
[dependency-groups]
dev = ["pytest", "ruff"]
docs = ["mkdocs"]
```

### 5. Secure Private Indexes

```bash
# Use environment variables
export PRIVATE_TOKEN="..."

# Never commit tokens
echo "PRIVATE_TOKEN=secret" >> .env
echo ".env" >> .gitignore
```

---

## Related Skills

- **uv-project-management** - Basic dependency management
- **uv-workspaces** - Workspace dependencies
- **python-packaging** - Build configuration

---

## References

- **Official Docs**: https://docs.astral.sh/uv/concepts/dependencies/
- **Git URLs**: https://pip.pypa.io/en/stable/topics/vcs-support/
- **PEP 508**: https://peps.python.org/pep-0508/ (dependency specification)
