# UV Workspaces - Comprehensive Reference

Complete guide to managing monorepo and multi-package projects with UV workspaces.

## Table of Contents

1. [Overview](#overview)
2. [Workspace Types](#workspace-types)
3. [Workspace Configuration](#workspace-configuration)
4. [Member Management](#member-management)
5. [Inter-Package Dependencies](#inter-package-dependencies)
6. [Source Inheritance](#source-inheritance)
7. [Dependency Resolution](#dependency-resolution)
8. [Syncing Workspaces](#syncing-workspaces)
9. [Building Packages](#building-packages)
10. [Testing Workspaces](#testing-workspaces)
11. [Docker Integration](#docker-integration)
12. [Common Patterns](#common-patterns)
13. [Troubleshooting](#troubleshooting)
14. [Best Practices](#best-practices)

---

## Overview

UV workspaces enable managing multiple related packages in a single repository (monorepo) with shared dependency resolution and a unified lockfile. Inspired by Cargo workspaces.

### Key Benefits

- **Single lockfile**: All packages use same dependency versions
- **Efficient development**: Workspace members are always editable
- **Consistent testing**: Test all packages together
- **Simplified CI/CD**: Build and deploy multiple packages in sync

### When to Use Workspaces

**Use workspaces for:**
- Monorepo with multiple Python packages
- Library with example applications
- Plugins/extensions architecture
- Shared internal packages

**Use path dependencies instead when:**
- Members have conflicting dependency requirements
- Members need separate virtual environments
- Packages are truly independent

---

## Workspace Types

### Standard Workspace

The root is both the workspace definition and a member:

```toml
# Root pyproject.toml
[project]
name = "my-workspace"
version = "0.1.0"
requires-python = ">=3.11"

[tool.uv.workspace]
members = ["packages/*"]
```

- Root is a workspace member
- `uv sync` defaults to syncing the root package
- Root can have its own dependencies

### Virtual Workspace

The root is purely organizational — no `[project]` table:

```toml
# Root pyproject.toml — virtual workspace
[tool.uv.workspace]
members = ["packages/*"]
```

- Root is **not** a workspace member
- No root package to sync or build
- `uv run` and `uv sync` require `--package` or `--all-packages`
- Common for monorepos where each package is independently versioned

### Choosing Between Types

| Scenario | Type |
|----------|------|
| Monorepo with a "main" app + libraries | Standard |
| Collection of independent packages | Virtual |
| Library with examples | Standard (library as root) |
| Microservices sharing utilities | Virtual |

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

**Standard workspace layout:**
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

**Virtual workspace layout (flat):**
```
my-monorepo/
├── pyproject.toml              # Virtual root (no [project])
├── uv.lock
├── packages/
│   ├── service-a/
│   │   ├── pyproject.toml
│   │   └── src/
│   ├── service-b/
│   │   ├── pyproject.toml
│   │   └── src/
│   └── shared-lib/
│       ├── pyproject.toml
│       └── src/
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

Every matched directory must contain a `pyproject.toml` file.

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

# Install root member's deps (standard workspace)
uv sync

# Install ALL members' deps
uv sync --all-packages

# Install specific member's deps
uv sync --package my-core

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

## Source Inheritance

### How It Works

Any `tool.uv.sources` definitions in the workspace root apply to **all members**, unless overridden:

```toml
# Root pyproject.toml
[tool.uv.sources]
my-utils = { workspace = true }
my-config = { workspace = true }
```

All members that depend on `my-utils` or `my-config` will resolve them as workspace members without needing their own `[tool.uv.sources]` entry.

### Override Behavior

If a member provides `tool.uv.sources` for a dependency, it **completely ignores** the root source for that same dependency:

```toml
# Root pyproject.toml
[tool.uv.sources]
my-utils = { workspace = true }

# packages/special/pyproject.toml
[tool.uv.sources]
my-utils = { path = "../custom-utils" }
# ^^^ Root's workspace source for my-utils is fully ignored
```

The override is **per-dependency and total** — even if the member's source is limited by a marker, the root source is still ignored.

### Practical Pattern

Define common workspace sources in the root, override only where specific members need different behavior:

```toml
# Root — defines defaults for all members
[tool.uv.sources]
shared-lib = { workspace = true }
config-lib = { workspace = true }
api-client = { workspace = true }

# packages/legacy/pyproject.toml — needs a pinned version instead
[tool.uv.sources]
api-client = { path = "../api-client-v1" }
```

---

## Dependency Resolution

### Unified Lockfile

```bash
# Single lockfile for entire workspace
uv.lock

# Contains all dependencies for all members
# Ensures version consistency
```

### requires-python Intersection

The workspace enforces a single `requires-python` by taking the **intersection** of all members' values:

```toml
# packages/core: requires-python = ">=3.10"
# packages/api:  requires-python = ">=3.11"
# packages/cli:  requires-python = ">=3.10,<3.13"
# Effective:     requires-python = ">=3.11,<3.13"
```

All members must have compatible Python version ranges. Incompatible ranges cause resolution errors.

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

# UV will error — must resolve manually
```

**Resolution options:**
1. Align requirements across workspace
2. Switch conflicting member to path dependency instead of workspace member

### Upgrading Dependencies

```bash
# Upgrade specific package across entire workspace
uv lock --upgrade-package requests

# All members get same version
uv sync --all-packages
```

---

## Syncing Workspaces

### Default Behavior

`uv sync` operates on the **workspace root only** by default. In a virtual workspace (no root project), you must specify a target.

### Scope Flags

```bash
# Sync root package only (default for standard workspace)
uv sync

# Sync ALL workspace members
uv sync --all-packages

# Sync specific member
uv sync --package my-api

# Sync multiple specific members
uv sync --package my-core --package my-api
```

### Partial Installation Flags

Control what gets installed for Docker layer caching and CI:

| Flag | Effect |
|------|--------|
| `--no-install-project` | Skip current project, install its deps only |
| `--no-install-workspace` | Skip all workspace members, install external deps only |
| `--no-install-package <name>` | Skip specific package(s) |
| `--frozen` | Skip lockfile up-to-date check |
| `--inexact` | Keep packages not in lockfile (default is exact/remove) |

### Dependency Groups

```bash
# Include all dependency groups
uv sync --all-packages --all-groups

# Include specific group
uv sync --all-packages --group test

# Exclude default groups
uv sync --all-packages --no-default-groups --group prod
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
# Build specific packages
uv build --package my-core
uv build --package my-api

# Publish
uv publish --package my-core
uv publish --package my-api
```

---

## Testing Workspaces

### Testing All Packages

```bash
# Run tests for all members
uv run --all-packages pytest

# From workspace root
uv run pytest packages/*/tests/

# With coverage
uv run --all-packages pytest --cov
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

      - uses: astral-sh/setup-uv@v5

      - name: Install dependencies
        run: uv sync --all-packages --frozen

      - name: Test all packages
        run: uv run --all-packages pytest --dots --bail=1

      - name: Test specific packages
        run: |
          uv run --package my-core pytest --dots --bail=1
          uv run --package my-api pytest --dots --bail=1
```

---

## Docker Integration

### Basic Workspace Dockerfile

```dockerfile
FROM python:3.12-slim

COPY --from=ghcr.io/astral-sh/uv:latest /uv /usr/local/bin/uv

WORKDIR /app

# Copy lockfile and all pyproject.toml files
COPY pyproject.toml uv.lock ./
COPY packages/core/pyproject.toml packages/core/pyproject.toml
COPY packages/api/pyproject.toml packages/api/pyproject.toml

# Install external deps only (cached layer)
RUN uv sync --frozen --no-install-workspace

# Copy source code
COPY . .

# Install workspace members
RUN uv sync --frozen --package my-api
```

### Multi-Stage Build

```dockerfile
# Build stage
FROM python:3.12-slim AS builder

COPY --from=ghcr.io/astral-sh/uv:latest /uv /usr/local/bin/uv

WORKDIR /app
COPY pyproject.toml uv.lock ./
COPY packages/ packages/

RUN uv sync --frozen --all-packages --no-dev

# Runtime stage
FROM python:3.12-slim

COPY --from=builder /app/.venv /app/.venv
COPY --from=builder /app/packages /app/packages

ENV PATH="/app/.venv/bin:$PATH"
```

### Layer Caching Strategy

| Layer | Contents | Cache hit when... |
|-------|----------|-------------------|
| 1 | pyproject.toml + uv.lock | Deps unchanged |
| 2 | `uv sync --frozen --no-install-workspace` | Deps unchanged |
| 3 | Source code COPY | Never (code changes) |
| 4 | `uv sync --frozen` | Always rebuilds |

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

### Microservices (Virtual Workspace)

```
my-company/
├── pyproject.toml          # Virtual workspace (no [project])
├── uv.lock
├── packages/
│   ├── shared/            # Shared utilities
│   ├── service-a/         # Microservice A
│   ├── service-b/         # Microservice B
│   └── service-c/         # Microservice C
```

```toml
# Root pyproject.toml — virtual workspace
[tool.uv.workspace]
members = ["packages/*"]

# Root sources inherited by all members
[tool.uv.sources]
my-company-shared = { workspace = true }
```

```bash
# Sync everything
uv sync --all-packages

# Run specific service
uv run --package service-a python -m service_a

# Build specific service for deployment
uv build --package service-a
```

---

## Troubleshooting

### Common Issues

**Workspace not detected:**
```bash
# Ensure pyproject.toml in root has workspace table
grep -A 5 "\[tool.uv.workspace\]" pyproject.toml

# Check member paths exist with pyproject.toml
ls packages/*/pyproject.toml
```

**Virtual workspace: "No `project` table found":**
```bash
# Virtual workspaces need --package or --all-packages
uv sync --all-packages           # Correct
uv run --package my-api python   # Correct
uv sync                          # Error: no root project
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

**requires-python incompatibility:**
```bash
# Check each member's requires-python
grep "requires-python" packages/*/pyproject.toml

# Ensure ranges have a valid intersection
```

**Member not found:**
```bash
# Verify member in workspace config
grep -A 10 "members" pyproject.toml

# Check member has pyproject.toml
ls packages/my-member/pyproject.toml

# Resync workspace
uv sync --all-packages
```

**Build failures:**
```bash
# Build specific package with verbose output
uv build --package my-core --verbose

# Check build-system configuration
grep -A 3 "\[build-system\]" packages/my-core/pyproject.toml
```

---

## Best Practices

### 1. Consistent Naming

```toml
# Use consistent prefix for all workspace members
[project]
name = "myproject-core"
# name = "myproject-api"
# name = "myproject-cli"
```

### 2. Use --all-packages in CI

```bash
# Ensures consistent environment regardless of working directory
uv sync --all-packages --frozen
uv run --all-packages pytest
```

### 3. Define Sources in Root

```toml
# Root pyproject.toml — single source of truth
[tool.uv.sources]
myproject-core = { workspace = true }
myproject-utils = { workspace = true }
myproject-config = { workspace = true }
```

Members inherit these automatically — only override when truly needed.

### 4. Shared Development Dependencies

```toml
# Root pyproject.toml
[dependency-groups]
dev = [
    "pytest>=7.0",
    "ruff>=0.1.0",
]
```

### 5. Clear Member Organization

```
packages/     # Library packages
apps/         # Applications
tools/        # Development tools
examples/     # Example applications
```

### 6. Commit uv.lock

```bash
# Single source of truth for all workspace deps
git add uv.lock
git commit -m "chore: update dependencies"
```

### 7. Align requires-python

Keep all members at the same `requires-python` to avoid intersection surprises:

```toml
# All members
requires-python = ">=3.11"
```

---

## Related Skills

- **uv-project-management** — Managing individual packages
- **uv-advanced-dependencies** — Path and Git dependencies
- **python-packaging** — Building and publishing packages

---

## References

- **Official Docs**: https://docs.astral.sh/uv/concepts/projects/workspaces/
- **Syncing Docs**: https://docs.astral.sh/uv/concepts/projects/sync/
- **Project Init Docs**: https://docs.astral.sh/uv/concepts/projects/init/
