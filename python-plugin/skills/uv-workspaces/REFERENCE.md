# UV Workspaces - Comprehensive Reference

Complete guide to managing monorepo and multi-package projects with UV workspaces.

## Table of Contents

1. [Overview](#overview)
2. [Workspace Configuration](#workspace-configuration)
3. [Member Management](#member-management)
4. [Inter-Package Dependencies](#inter-package-dependencies)
5. [Dependency Resolution](#dependency-resolution)
6. [Building Packages](#building-packages)
7. [Testing Workspaces](#testing-workspaces)
8. [Common Patterns](#common-patterns)
9. [Troubleshooting](#troubleshooting)
10. [Best Practices](#best-practices)

---

## Overview

UV workspaces enable managing multiple related packages in a single repository (monorepo) with shared dependency resolution and a unified lockfile.

### Key Benefits

- **Single lockfile**: All packages use same dependency versions
- **Efficient development**: Changes to member packages available immediately
- **Consistent testing**: Test all packages together
- **Simplified CI/CD**: Build and deploy multiple packages in sync

### When to Use Workspaces

✅ **Use workspaces for:**
- Monorepo with multiple Python packages
- Library with example applications
- Plugins/extensions architecture
- Shared internal packages

❌ **Don't use workspaces for:**
- Single package projects
- Unrelated packages
- External dependencies

---

## Workspace Configuration

### Root pyproject.toml

```toml
[tool.uv.workspace]
members = [
    "packages/*",
]

# Optional: exclude specific paths
exclude = [
    "packages/experimental/*",
    "packages/archived",
]
```

### Directory Structure

**Recommended layout:**
```
my-workspace/
├── pyproject.toml              # Workspace root
├── uv.lock                     # Shared lockfile
├── README.md
├── packages/
│   ├── core/
│   │   ├── pyproject.toml
│   │   ├── README.md
│   │   └── src/
│   │       └── my_core/
│   │           └── __init__.py
│   ├── api/
│   │   ├── pyproject.toml
│   │   └── src/
│   │       └── my_api/
│   │           └── __init__.py
│   └── cli/
│       ├── pyproject.toml
│       └── src/
│           └── my_cli/
│               └── __init__.py
├── apps/
│   └── web/
│       ├── pyproject.toml
│       └── src/
└── tools/
    └── scripts/
```

### Member Discovery

```toml
# Glob patterns
[tool.uv.workspace]
members = [
    "packages/*",      # All direct children
    "apps/*",
    "tools/*",
]

# Explicit paths
members = [
    "packages/core",
    "packages/api",
    "apps/web",
]

# Mixed approach
members = [
    "packages/*",      # Glob for most
    "tools/special",   # Explicit for specific
]

# Exclusions
exclude = [
    "packages/archived",
    "packages/experimental/*",
]
```

---

## Member Management

### Creating Workspace Members

```bash
# Create workspace root
mkdir my-workspace && cd my-workspace

# Create root config
cat > pyproject.toml << 'EOF'
[tool.uv.workspace]
members = ["packages/*"]
EOF

# Create first member
mkdir -p packages/core
cd packages/core
uv init my-core

# Create second member
cd ../..
mkdir -p packages/api
cd packages/api
uv init my-api
```

### Member pyproject.toml

```toml
[project]
name = "my-core"
version = "0.1.0"
description = "Core library"
requires-python = ">=3.11"
dependencies = [
    "pydantic>=2.0",
]

[dependency-groups]
dev = [
    "pytest>=7.0",
]

[build-system]
requires = ["uv_build>=0.9.2,<0.10.0"]
build-backend = "uv_build"
```

### Workspace Operations

```bash
# From workspace root:

# Install all members
uv sync

# Update lockfile
uv lock

# Run command in workspace context
uv run python script.py

# Run in specific package
uv run --package my-core python script.py
```

---

## Inter-Package Dependencies

### Declaring Workspace Dependencies

**In member pyproject.toml:**
```toml
[project]
name = "my-api"
version = "0.1.0"
dependencies = [
    "my-core",        # Workspace member
    "fastapi>=0.110.0",  # External dependency
]

# Mark as workspace dependency
[tool.uv.sources]
my-core = { workspace = true }
```

### Multiple Workspace Dependencies

```toml
[project]
name = "my-app"
dependencies = [
    "my-core",
    "my-utils",
    "my-shared",
]

[tool.uv.sources]
my-core = { workspace = true }
my-utils = { workspace = true }
my-shared = { workspace = true }
```

### Adding Workspace Dependencies

```bash
# Method 1: Navigate to member directory
cd packages/api
uv add ../core

# UV automatically detects workspace member
# and adds to [tool.uv.sources]

# Method 2: Manual edit
# Edit packages/api/pyproject.toml as shown above
```

### Editable Installations

Workspace members are **always editable**:
- Changes to source code immediately available
- No reinstallation needed
- Ideal for development

---

## Dependency Resolution

### Unified Lockfile

```bash
# Single lockfile for entire workspace
uv.lock

# Contains all dependencies for all members
# Ensures version consistency
```

### Resolution Strategy

```bash
# All workspace members must use compatible versions
# UV resolves to satisfy all constraints

# Example:
# packages/core: requests>=2.30
# packages/api:  requests>=2.28,<3.0
# Resolution:    requests==2.31.0 (satisfies both)
```

### Conflicting Requirements

```toml
# packages/core/pyproject.toml
[project]
dependencies = ["numpy>=2.0"]

# packages/api/pyproject.toml
[project]
dependencies = ["numpy<2.0"]  # Conflict!

# UV will error - must resolve manually
```

**Resolution:**
```toml
# Align requirements across workspace
[project]
dependencies = ["numpy>=1.26,<3.0"]
```

### Upgrading Dependencies

```bash
# Upgrade across entire workspace
uv lock --upgrade-package requests

# All members get same version
uv sync
```

---

## Building Packages

### Build Commands

```bash
# Build all workspace members
uv build

# Build specific package
uv build --package my-core

# Build multiple packages
uv build --package my-core --package my-api

# Output location
# packages/my-core/dist/
# packages/my-api/dist/
```

### Build Configuration

```toml
# Per-member build config
[build-system]
requires = ["uv_build>=0.9.2,<0.10.0"]
build-backend = "uv_build"

# Alternative backends
[build-system]
requires = ["setuptools>=68", "wheel"]
build-backend = "setuptools.build_meta"
```

### Publishing Workflow

```bash
# Build all packages
uv build

# Publish to PyPI
cd packages/core
twine upload dist/*

cd ../api
twine upload dist/*
```

---

## Testing Workspaces

### Testing All Packages

```bash
# Run tests for all members
uv run pytest

# From workspace root
uv run pytest packages/*/tests/

# With coverage
uv run pytest --cov=packages
```

### Testing Specific Packages

```bash
# Run tests for specific package
uv run --package my-core pytest

# Navigate and test
cd packages/core
uv run pytest

# Test multiple specific packages
uv run pytest packages/core/tests packages/api/tests
```

### Test Configuration

**Root conftest.py:**
```python
# tests/conftest.py
import sys
from pathlib import Path

# Add all packages to path
workspace_root = Path(__file__).parent.parent
for package_dir in (workspace_root / "packages").iterdir():
    sys.path.insert(0, str(package_dir / "src"))
```

**Shared test utilities:**
```python
# tests/shared/helpers.py
# Shared test helpers for all packages
```

### CI/CD Testing

```yaml
# .github/workflows/test.yml
name: Test Workspace

on: [push, pull_request]

jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - uses: astral-sh/setup-uv@v1

      - name: Install dependencies
        run: uv sync --frozen

      - name: Test all packages
        run: uv run pytest --cov=packages

      - name: Test specific packages
        run: |
          uv run --package my-core pytest
          uv run --package my-api pytest
```

---

## Common Patterns

### Library with Examples

```
my-library/
├── pyproject.toml
├── packages/
│   └── mylib/
│       ├── pyproject.toml      # Main library
│       └── src/mylib/
└── examples/
    ├── basic/
    │   ├── pyproject.toml      # Example app
    │   └── src/
    └── advanced/
        ├── pyproject.toml      # Example app
        └── src/
```

```toml
# Root pyproject.toml
[tool.uv.workspace]
members = [
    "packages/mylib",
    "examples/*",
]
```

### Plugin Architecture

```
my-app/
├── pyproject.toml
├── packages/
│   ├── core/              # Core application
│   └── plugins/
│       ├── auth/          # Authentication plugin
│       ├── logging/       # Logging plugin
│       └── metrics/       # Metrics plugin
```

```toml
# Root
[tool.uv.workspace]
members = [
    "packages/core",
    "packages/plugins/*",
]

# Plugin pyproject.toml
[project]
dependencies = ["my-app-core"]

[tool.uv.sources]
my-app-core = { workspace = true }
```

### Shared Utilities

```
my-company/
├── pyproject.toml
├── packages/
│   ├── shared/            # Shared utilities
│   ├── service-a/         # Microservice A
│   ├── service-b/         # Microservice B
│   └── service-c/         # Microservice C
```

```toml
# Each service depends on shared
[project]
dependencies = ["my-company-shared"]

[tool.uv.sources]
my-company-shared = { workspace = true }
```

---

## Troubleshooting

### Common Issues

**Workspace not detected:**
```bash
# Ensure pyproject.toml in root
ls pyproject.toml

# Verify workspace config
grep -A 5 "\[tool.uv.workspace\]" pyproject.toml

# Check member paths exist
ls packages/*/pyproject.toml
```

**Dependency resolution conflicts:**
```bash
# Identify conflict
uv lock --verbose

# Align requirements across members
# Edit conflicting pyproject.toml files

# Retry
uv lock
```

**Member not found:**
```bash
# Verify member in workspace config
grep -A 10 "members" pyproject.toml

# Check member has pyproject.toml
ls packages/my-member/pyproject.toml

# Resync workspace
uv sync
```

**Build failures:**
```bash
# Build specific package with verbose output
uv build --package my-core --verbose

# Check build-system configuration
grep -A 3 "\[build-system\]" packages/my-core/pyproject.toml

# Verify package structure
tree packages/my-core
```

---

## Best Practices

### 1. Consistent Naming

```toml
# Use consistent prefix for all workspace members
[project]
name = "myproject-core"
name = "myproject-api"
name = "myproject-cli"
```

### 2. Version Synchronization

Keep related packages at same version:
```toml
# All packages
version = "0.1.0"

# Bump together when releasing
version = "0.2.0"
```

### 3. Shared Development Dependencies

```toml
# Root pyproject.toml
[dependency-groups]
dev = [
    "pytest>=7.0",
    "ruff>=0.1.0",
    "mypy>=1.7",
]

# All members can use these
```

### 4. Clear Member Organization

```
packages/     # Library packages
apps/         # Applications
tools/        # Development tools
examples/     # Example applications
```

### 5. Document Dependencies

```markdown
# README.md

## Workspace Structure

- `packages/core` - Core library
- `packages/api` - REST API (depends on core)
- `packages/cli` - CLI tool (depends on core)
```

### 6. Automated Testing

Test all packages together:
```bash
uv run pytest
```

### 7. Single Source of Truth

Use workspace lockfile as single source:
```bash
# Commit uv.lock
git add uv.lock
git commit -m "chore: update dependencies"
```

---

## Related Skills

- **uv-project-management** - Managing individual packages
- **uv-advanced-dependencies** - Path and Git dependencies
- **python-packaging** - Building and publishing packages

---

## References

- **Official Docs**: https://docs.astral.sh/uv/concepts/projects/workspaces/
- **Workspace Layout**: https://docs.astral.sh/uv/concepts/projects/layout/
