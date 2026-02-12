---
model: haiku
created: 2025-12-16
modified: 2026-02-12
reviewed: 2026-02-12
name: uv-workspaces
description: |
  Manage monorepo and multi-package Python projects with uv workspaces. Covers
  workspace configuration, virtual workspaces, member dependencies, shared lockfiles,
  source inheritance, and building. Use when user mentions uv workspaces, Python
  monorepo, multi-package projects, workspace members, or shared dependencies across
  packages.
allowed-tools: Bash, Read, Grep, Glob
---

# UV Workspaces

Quick reference for managing monorepo and multi-package projects with UV workspaces.

## When to Use This Skill

| Use this skill when... | Use another skill instead when... |
|------------------------|-----------------------------------|
| Setting up a Python monorepo with shared deps | Managing a single package (`uv-project-management`) |
| Configuring workspace members and inter-package deps | Adding git/URL dependencies (`uv-advanced-dependencies`) |
| Using `--package` or `--all-packages` flags | Building/publishing to PyPI (`python-packaging`) |
| Creating virtual workspaces (root with no project) | Managing Python versions (`uv-python-versions`) |
| Debugging workspace dependency resolution | Running standalone scripts (`uv-run`) |

## Quick Reference

### Workspace Structure

```
my-workspace/
├── pyproject.toml          # Root workspace config
├── uv.lock                 # Shared lockfile (all members)
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
[project]
name = "my-workspace"
version = "0.1.0"
requires-python = ">=3.11"

[tool.uv.workspace]
members = ["packages/*"]

# Optional: exclude specific members
exclude = ["packages/experimental"]
```

### Virtual Workspace (No Root Package)

When the root is purely organizational and not a package itself, omit the `[project]` table:

```toml
# Root pyproject.toml — virtual workspace (no [project] table)
[tool.uv.workspace]
members = ["packages/*"]
```

- The root is **not** a workspace member
- All members live in subdirectories
- `uv run` and `uv sync` require `--package` or `--all-packages`

### Member pyproject.toml

```toml
[project]
name = "my-api"
version = "0.1.0"
requires-python = ">=3.11"
dependencies = [
    "my-core",       # Workspace member
    "fastapi",       # External (PyPI)
]

[tool.uv.sources]
my-core = { workspace = true }
```

## Common Commands

| Operation | Command |
|-----------|---------|
| Sync workspace root | `uv sync` |
| Sync all members | `uv sync --all-packages` |
| Sync specific member | `uv sync --package my-api` |
| Run in member context | `uv run --package my-api python script.py` |
| Lock entire workspace | `uv lock` |
| Upgrade a dependency | `uv lock --upgrade-package requests` |
| Build specific package | `uv build --package my-core` |
| Add dep to member | `cd packages/api && uv add requests` |
| Add workspace dep | `cd packages/api && uv add ../core` |

## Key Behaviors

### Source Inheritance

Root `tool.uv.sources` apply to **all members** unless overridden:

```toml
# Root pyproject.toml
[tool.uv.sources]
my-utils = { workspace = true }

# Member overrides root source entirely for that dependency
# packages/special/pyproject.toml
[tool.uv.sources]
my-utils = { path = "../custom-utils" }
```

Override is **per-dependency and total** — if a member defines a source for a dependency, the root source for that dependency is ignored completely.

### requires-python Resolution

The workspace enforces the **intersection** of all members' `requires-python`:

```toml
# packages/core: requires-python = ">=3.10"
# packages/api:  requires-python = ">=3.11"
# Effective:     requires-python = ">=3.11"
```

All members must have compatible Python version requirements.

### Editable Installations

Workspace member dependencies are **always editable** — source changes are immediately available without reinstallation.

### Default Scope

| Command | Default scope | Override |
|---------|---------------|----------|
| `uv lock` | Entire workspace | — |
| `uv sync` | Workspace root only | `--package`, `--all-packages` |
| `uv run` | Workspace root only | `--package`, `--all-packages` |
| `uv build` | All members | `--package` |

## Workspace vs Path Dependencies

| Feature | `{ workspace = true }` | `{ path = "../pkg" }` |
|---------|------------------------|------------------------|
| Shared lockfile | Yes | No |
| Always editable | Yes | Optional |
| Must be workspace member | Yes | No |
| `--package` flag works | Yes | No |
| Conflicting deps allowed | No | Yes |

Use path dependencies when members need conflicting requirements or separate virtual environments.

## Docker Layer Caching

```dockerfile
# Install deps first (cached layer)
COPY pyproject.toml uv.lock packages/*/pyproject.toml ./
RUN uv sync --frozen --no-install-workspace

# Then install project (changes frequently)
COPY . .
RUN uv sync --frozen
```

| Flag | Effect |
|------|--------|
| `--no-install-project` | Skip current project, install deps only |
| `--no-install-workspace` | Skip all workspace members, install deps only |
| `--no-install-package <name>` | Skip specific package(s) |
| `--frozen` | Skip lockfile freshness check |

## Agentic Optimizations

| Context | Command |
|---------|---------|
| Sync all members | `uv sync --all-packages` |
| CI sync (frozen) | `uv sync --all-packages --frozen` |
| Test specific member | `uv run --package my-core pytest --dots --bail=1` |
| Test all members | `uv run --all-packages pytest --dots --bail=1` |
| Lock with upgrade | `uv lock --upgrade-package <dep>` |
| Build one package | `uv build --package my-core` |
| Docker deps layer | `uv sync --frozen --no-install-workspace` |

## See Also

- `uv-project-management` — Managing individual packages
- `uv-advanced-dependencies` — Path and Git dependencies
- `python-packaging` — Building and publishing workspace packages

For detailed workspace patterns, CI/CD examples, and troubleshooting, see [REFERENCE.md](REFERENCE.md).
