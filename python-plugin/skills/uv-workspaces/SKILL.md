---
name: uv-workspaces
description: |
  Manage monorepo and multi-package Python projects with uv workspaces. Covers
  workspace configuration, member dependencies, shared lockfiles, and building.
  Use when user mentions uv workspaces, Python monorepo, multi-package projects,
  workspace members, or shared dependencies across packages.
---

# UV Workspaces

Quick reference for managing monorepo and multi-package projects with UV workspaces.

## When This Skill Applies

- Monorepo projects with multiple Python packages
- Shared dependencies across multiple packages
- Library packages with example applications
- Projects with plugins or extensions
- Internal package dependencies

## Quick Reference

### Workspace Structure

```
my-workspace/
├── pyproject.toml          # Root workspace config
├── uv.lock                # Shared lockfile
├── packages/
│   ├── core/
│   │   ├── pyproject.toml
│   │   └── src/core/
│   ├── api/
│   │   ├── pyproject.toml
│   │   └── src/api/
│   └── cli/
│       ├── pyproject.toml
│       └── src/cli/
└── README.md
```

### Root pyproject.toml

```toml
[tool.uv.workspace]
members = [
    "packages/*",
]

# Or explicit:
members = [
    "packages/core",
    "packages/api",
    "packages/cli",
]

# Exclude patterns
exclude = [
    "packages/experimental",
]
```

### Package pyproject.toml

```toml
[project]
name = "my-core"
version = "0.1.0"
dependencies = []

# Depend on workspace member
[project]
dependencies = ["my-utils"]

[tool.uv.sources]
my-utils = { workspace = true }
```

## Common Commands

```bash
# Install all workspace members
uv sync

# Build specific package
uv build --package my-core

# Run in package context
uv run --package my-api python script.py

# Add dependency to specific member
cd packages/my-core
uv add requests

# Lock entire workspace
uv lock
```

## Workspace Members

### Declaring Members

```toml
[tool.uv.workspace]
# Glob patterns
members = ["packages/*"]

# Explicit paths
members = [
    "packages/core",
    "apps/web",
    "tools/cli",
]

# Mixed
members = [
    "packages/*",
    "apps/special",
]

# Exclusions
exclude = ["packages/archived"]
```

### Member Dependencies

**Depend on another workspace member:**
```toml
# packages/api/pyproject.toml
[project]
name = "my-api"
dependencies = [
    "my-core",  # Workspace member
    "fastapi",  # PyPI package
]

[tool.uv.sources]
my-core = { workspace = true }
```

## Shared Dependencies

### Common Patterns

**Development dependencies in root:**
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

**Member-specific dependencies:**
```toml
# packages/api/pyproject.toml
[project]
dependencies = [
    "fastapi>=0.110.0",
]

[dependency-groups]
test = [
    "pytest-asyncio",  # Only for this member
]
```

## Lockfile Management

```bash
# Single lockfile for entire workspace
uv.lock

# Update lockfile
uv lock

# Upgrade specific package across workspace
uv lock --upgrade-package requests

# Sync all members
uv sync
```

## Building Packages

```bash
# Build all packages
uv build

# Build specific package
uv build --package my-core
uv build --package my-api

# Build multiple packages
uv build --package my-core --package my-api
```

## Common Workflows

### Creating a Workspace

```bash
# Create root
mkdir my-workspace && cd my-workspace

# Create root pyproject.toml
cat > pyproject.toml << 'EOF'
[tool.uv.workspace]
members = ["packages/*"]
EOF

# Create first package
mkdir -p packages/core
cd packages/core
uv init core

# Create second package
cd ../..
mkdir -p packages/api
cd packages/api
uv init api

# Configure workspace dependency
# Edit packages/api/pyproject.toml to depend on core
```

### Adding Inter-Package Dependencies

```bash
# In packages/api/
uv add ../core

# Or manually edit pyproject.toml:
# [project]
# dependencies = ["my-core"]
#
# [tool.uv.sources]
# my-core = { workspace = true }
```

### Testing Across Workspace

```bash
# Test all packages
uv run pytest packages/*/tests/

# Test specific package
uv run --package my-core pytest

# Run with coverage
uv run pytest --cov=packages
```

## Workspace vs Path Dependencies

### Workspace Member

```toml
[tool.uv.sources]
my-package = { workspace = true }
```

- Always editable
- Must be workspace member
- Shared lockfile

### Path Dependency

```toml
[tool.uv.sources]
my-package = { path = "../my-package" }
```

- Can be outside workspace
- Optional editability
- Independent locking

## See Also

- `uv-project-management` - Managing individual packages
- `uv-advanced-dependencies` - Path and Git dependencies
- `python-packaging` - Building and publishing workspace packages

## References

- Official docs: https://docs.astral.sh/uv/concepts/projects/workspaces/
- Detailed guide: See REFERENCE.md in this skill directory
