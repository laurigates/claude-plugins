---
name: uv-advanced-dependencies
description: |
  Advanced dependency scenarios in uv projects: Git dependencies, path dependencies,
  editable installs, dependency groups, extras, constraints, and custom indexes.
  Use when user mentions git+https dependencies, local path dependencies, editable
  installs, dependency groups, or private package indexes.
---

# UV Advanced Dependencies

Quick reference for advanced dependency scenarios in UV projects.

## When This Skill Applies

- Git repository dependencies
- Local path dependencies
- Editable installations
- Dependency constraints
- Custom package indexes
- Dependency groups and extras
- Build dependencies

## Quick Reference

### Git Dependencies

```bash
# Add from Git repository
uv add git+https://github.com/psf/requests
uv add git+https://github.com/pallets/flask@main
uv add git+ssh://git@github.com/user/repo.git@v1.0.0

# Specific branch, tag, or commit
uv add git+https://github.com/user/repo@feature-branch
uv add git+https://github.com/user/repo@v2.0.0
uv add git+https://github.com/user/repo@abc123
```

### Path Dependencies

```bash
# Add from local path
uv add --editable ./local-package
uv add ../another-project
uv add /absolute/path/to/package

# Non-editable path
uv add --no-editable ./local-package
```

### Dependency Groups

```bash
# Add to named group
uv add --group docs sphinx mkdocs
uv add --group test pytest pytest-cov

# Install specific groups
uv sync --group docs
uv sync --group test --group docs

# Install all groups
uv sync --all-groups
```

### Extras (Optional Dependencies)

```bash
# Install package with extras
uv add 'fastapi[all]'
uv add 'sqlalchemy[postgresql,mypy]'

# Define extras in pyproject.toml
[project.optional-dependencies]
dev = ["pytest", "ruff"]
docs = ["mkdocs", "mkdocs-material"]
```

### Constraint Files

```bash
# Apply version constraints
uv pip compile requirements.in --constraint constraints.txt

# constraints.txt example:
# numpy<2.0
# pandas==2.0.3
```

### Custom Indexes

```toml
[tool.uv]
index-url = "https://pypi.org/simple"
extra-index-url = [
    "https://custom.pypi.org/simple",
]
```

## Git Dependencies in pyproject.toml

```toml
[project]
dependencies = [
    "my-package",
]

[tool.uv.sources]
my-package = { git = "https://github.com/user/my-package" }

# With branch
my-package = { git = "https://github.com/user/my-package", branch = "main" }

# With tag
my-package = { git = "https://github.com/user/my-package", tag = "v1.0.0" }

# With commit
my-package = { git = "https://github.com/user/my-package", rev = "abc123" }
```

## Path Dependencies in pyproject.toml

```toml
[project]
dependencies = [
    "my-local-package",
]

[tool.uv.sources]
my-local-package = { path = "../my-local-package" }

# Editable (default for paths)
my-local-package = { path = "../my-local-package", editable = true }

# Non-editable
my-local-package = { path = "../my-local-package", editable = false }
```

## Dependency Groups

```toml
[dependency-groups]
dev = [
    "pytest>=7.0",
    "pytest-cov>=4.0",
    "ruff>=0.1.0",
]
docs = [
    "mkdocs-material>=9.0",
    "mkdocstrings[python]>=0.24",
]
test = [
    "pytest-asyncio>=0.21",
    "pytest-mock>=3.12",
]
```

## URL Dependencies

```bash
# Add from direct URL
uv add https://files.pythonhosted.org/packages/.../requests-2.31.0.tar.gz

# In pyproject.toml
[tool.uv.sources]
my-package = { url = "https://example.com/my-package-1.0.tar.gz" }
```

## Private Package Indexes

```toml
[tool.uv]
# Primary index
index-url = "https://pypi.org/simple"

# Additional indexes
extra-index-url = [
    "https://${PRIVATE_TOKEN}@private.pypi.org/simple",
]

# Find links
find-links = [
    "https://download.pytorch.org/whl/cu118",
]
```

```bash
# Set token via environment
export PRIVATE_TOKEN="secret"
uv sync
```

## Build Dependencies

```toml
[build-system]
requires = [
    "setuptools>=68",
    "wheel",
    "Cython>=3.0",
]
build-backend = "setuptools.build_meta"
```

## Common Patterns

### Development from Local Checkout

```bash
# Clone dependency
git clone https://github.com/user/lib.git ../lib

# Add as editable
cd my-project
uv add --editable ../lib
```

### Monorepo Path Dependencies

```toml
[tool.uv.sources]
my-core = { path = "packages/core" }
my-utils = { path = "packages/utils" }
```

### Mixed Sources

```toml
[project]
dependencies = [
    "fastapi",          # PyPI
    "my-lib",           # Git
    "my-local",         # Path
]

[tool.uv.sources]
my-lib = { git = "https://github.com/user/my-lib" }
my-local = { path = "../my-local" }
```

## Resolution Strategies

```toml
[tool.uv]
# Highest compatible (default)
resolution = "highest"

# Lowest compatible
resolution = "lowest"

# Lowest direct, highest transitive
resolution = "lowest-direct"
```

## See Also

- `uv-project-management` - Basic dependency management
- `uv-workspaces` - Workspace member dependencies
- `python-packaging` - Build system configuration

## References

- Official docs: https://docs.astral.sh/uv/concepts/dependencies/
- Detailed guide: See REFERENCE.md in this skill directory
