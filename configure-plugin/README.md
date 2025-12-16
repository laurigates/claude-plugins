# Configure Plugin

FVH (Forum Virium Helsinki) infrastructure standards enforcement for Claude Code projects.

## Overview

This plugin provides comprehensive project configuration commands that check and enforce infrastructure standards across multiple domains: CI/CD, testing, code quality, containers, and more.

All commands support two modes:
- `--check-only` - Audit current state without making changes
- `--fix` - Automatically configure to meet standards

## Commands

### Core

| Command | Description |
|---------|-------------|
| `/configure:all` | Run all infrastructure standards checks |
| `/configure:status` | Show compliance status (read-only) |

### CI/CD & Version Control

| Command | Description |
|---------|-------------|
| `/configure:pre-commit` | Pre-commit hooks for FVH standards |
| `/configure:release-please` | Release-please workflow configuration |
| `/configure:workflows` | GitHub Actions CI/CD workflows |
| `/configure:github-pages` | GitHub Pages deployment |

### Container & Deployment

| Command | Description |
|---------|-------------|
| `/configure:dockerfile` | Dockerfile for FVH standards (minimal Alpine/slim, non-root, multi-stage) |
| `/configure:skaffold` | Skaffold configuration |
| `/configure:container` | Container infrastructure (builds, registry, scanning, devcontainer) |

### Testing

| Command | Description |
|---------|-------------|
| `/configure:tests` | Testing frameworks and infrastructure |
| `/configure:coverage` | Code coverage thresholds and reporting |
| `/configure:api-tests` | API testing configuration |
| `/configure:integration-tests` | Integration test configuration |
| `/configure:load-tests` | Load/performance test configuration |
| `/configure:ux-testing` | UX testing (Playwright, accessibility, visual regression) |

### Code Quality

| Command | Description |
|---------|-------------|
| `/configure:linting` | Linting tools (Biome, Ruff, Clippy) |
| `/configure:formatting` | Code formatting (Biome, Prettier, Ruff, rustfmt) |
| `/configure:dead-code` | Dead code detection (Knip, Vulture, cargo-machete) |
| `/configure:docs` | Documentation standards and generators |
| `/configure:security` | Security scanning (dependency audits, SAST, secrets) |

### Infrastructure

| Command | Description |
|---------|-------------|
| `/configure:editor` | EditorConfig and VS Code workspace settings |
| `/configure:mcp` | MCP servers for project integration |
| `/configure:cache-busting` | Cache-busting strategies for Next.js and Vite |
| `/configure:feature-flags` | Feature flag infrastructure (OpenFeature + providers) |
| `/configure:sentry` | Sentry error tracking |
| `/configure:makefile` | Makefile with standard targets |
| `/configure:package-management` | Modern package managers (uv for Python, bun for TypeScript) |

## Skills

| Skill | Description |
|-------|-------------|
| `fvh-ci-workflows` | FVH CI/CD workflow standards |
| `fvh-pre-commit` | FVH pre-commit hook standards |
| `fvh-release-please` | FVH release-please standards |
| `fvh-skaffold` | FVH Skaffold configuration standards |

## Usage

### Check All Standards

```bash
/configure:status
```

Shows compliance status for all configured standards without making changes.

### Fix All Standards

```bash
/configure:all --fix
```

Automatically configures the project to meet all FVH standards.

### Check Specific Domain

```bash
/configure:tests --check-only
/configure:linting --check-only
```

### Fix Specific Domain

```bash
/configure:pre-commit --fix
/configure:dockerfile --fix
```

## FVH Standards Summary

- **Pre-commit**: Standardized hooks for linting, formatting, security checks
- **CI/CD**: GitHub Actions workflows for testing, building, releasing
- **Containers**: Minimal base images, non-root users, multi-stage builds
- **Testing**: Framework detection, coverage thresholds, tiered execution
- **Code Quality**: Consistent linting/formatting across languages
- **Security**: Dependency audits, SAST scanning, secrets detection

## Installation

```bash
/plugin install configure-plugin@lgates-claude-plugins
```

## License

MIT
