---
model: haiku
name: bun-package-manager
description: Fast JavaScript package management with Bun - install, add, remove, update dependencies with optimized CLI flags for agentic workflows.
allowed-tools: Bash, Read, Grep, Glob, TodoWrite
created: 2025-12-20
modified: 2025-12-20
reviewed: 2025-12-20
---

# Bun Package Manager

## Core Expertise

Bun's package manager is significantly faster than npm/yarn/pnpm:
- ~7x faster than npm
- ~4x faster than pnpm
- Native workspace support
- Compatible with npm registry

## Essential Commands

### Install Dependencies

```bash
# Standard install
bun install

# CI/reproducible (frozen lockfile)
bun install --frozen-lockfile

# Production only (no devDependencies)
bun install --production

# Force reinstall
bun install --force

# Dry run (preview)
bun install --dry-run
```

### Add Packages

```bash
# Add dependency
bun add <package>

# Add dev dependency
bun add --dev <package>
bun add -d <package>

# Pin exact version (no ^)
bun add --exact <package>
bun add -E <package>

# Global install
bun add --global <package>
bun add -g <package>

# Add to specific workspace
bun add <package> --cwd packages/mylib
```

### Remove Packages

```bash
# Remove dependency
bun remove <package>

# Remove from devDependencies
bun remove --dev <package>

# Dry run
bun remove --dry-run <package>
```

### Update Packages

```bash
# Update within semver ranges
bun update

# Update to latest (ignore ranges)
bun update --latest

# Interactive selection
bun update --interactive

# Update across workspaces
bun update --recursive
```

### Inspect Dependencies

```bash
# Check outdated packages
bun outdated

# Why is package installed?
bun why <package>

# List installed packages
bun pm ls

# View package cache
bun pm cache
```

## Workspace Management

### Configuration

```json
{
  "name": "monorepo",
  "private": true,
  "workspaces": ["packages/*", "apps/*"]
}
```

### Workspace Operations

```bash
# Install all workspace deps
bun install

# Add to specific workspace
bun add express --cwd apps/api

# Run in matching workspaces
bun run --filter 'package-*' build

# Run in all workspaces
bun run --workspaces test
```

### Inter-workspace Dependencies

```json
{
  "dependencies": {
    "shared-utils": "workspace:*"
  }
}
```

## Agentic Optimizations

| Context | Command |
|---------|---------|
| CI install | `bun install --frozen-lockfile` |
| Prod deploy | `bun install --production` |
| Preview changes | `bun add --dry-run <pkg>` |
| Exact versions | `bun add --exact <pkg>` |
| Workspace target | `bun add <pkg> --cwd <path>` |
| Force refresh | `bun install --force` |

## Quick Reference

| Flag | Short | Description |
|------|-------|-------------|
| `--frozen-lockfile` | | Fail if lockfile changes |
| `--production` | `-p` | Skip devDependencies |
| `--dev` | `-d` | Add to devDependencies |
| `--exact` | `-E` | Pin exact version |
| `--global` | `-g` | Global install |
| `--dry-run` | | Preview without executing |
| `--force` | `-f` | Force reinstall all |
| `--cwd <path>` | | Target directory |
| `--latest` | | Update to latest version |
| `--recursive` | | Apply across workspaces |

## Error Handling

### Common Issues

**Lockfile mismatch in CI:**
```bash
# Use frozen lockfile
bun install --frozen-lockfile
```

**Peer dependency conflicts:**
```bash
# Force install anyway
bun install --force
```

**Package not found:**
```bash
# Check if package exists
bun why <package>
```

## Environment Variables

| Variable | Description |
|----------|-------------|
| `BUN_OPTIONS` | Global CLI flags |
| `BUN_INSTALL` | Bun installation directory |
