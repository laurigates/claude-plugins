# Configure Plugin

Infrastructure standards enforcement for Claude Code projects.

## Flow

See [`docs/flow.md`](docs/flow.md) for a diagram of how the skills fit together.

## Overview

This plugin provides comprehensive project configuration commands that check and enforce infrastructure standards across multiple domains: CI/CD, testing, code quality, containers, and more.

All commands support two modes:
- `--check-only` - Audit current state without making changes
- `--fix` - Automatically configure to meet standards

## Skills

The domain grouping below mirrors the authoritative manifest
[`skills/configure-all/components.yaml`](skills/configure-all/components.yaml);
`scripts/check-configure-components.sh` (repo root) fails CI when they drift.

### Orchestration

| Skill | Description |
|-------|-------------|
| `configure-repo` | **End-to-end driver** — onboard any repo to Claude Code with marketplace enrollment, permissions, SessionStart hook, and health validation |
| `configure-all` | Run every component check from the manifest roster |
| `configure-select` | Interactively select which manifest domains to configure |
| `configure-status` | Show compliance status (read-only), rolling up component detection scripts |
| `config-sync` | Extract, compare, and propagate tooling improvements across repos |
| `multi-repo-discipline` | Advisory discipline for multi-repo workspaces — read-only fixtures, upstream/downstream pairs, and when sibling-repo commits need user confirmation |

### Reference Skills (loaded by other skills, not user-invoked)

| Skill | Description |
|-------|-------------|
| `ci-workflows` | CI/CD workflow standards |
| `pre-commit-standards` | Pre-commit hook standards |
| `release-please-standards` | Release-please single-repo standards + compliance (monorepo strategy lives in git-plugin) |
| `skaffold-standards` | Skaffold configuration standards |
| `readme-standards` | README templates and section standards |
| `claude-security-settings` | Claude Code security settings and wildcard permissions |
| `openfeature` | OpenFeature vendor-agnostic feature-flag SDK reference |
| `go-feature-flag` | GO Feature Flag (GOFF) provider reference |

### CI/CD & Version Control

| Skill | Description |
|-------|-------------|
| `configure-workflows` | GitHub Actions CI/CD workflows |
| `configure-reusable-workflows` | Install Claude-powered reusable workflows (security, quality, a11y) |
| `configure-release-please` | Release-please workflow configuration |
| `configure-pre-commit` | Pre-commit hooks for project standards |
| `configure-github-pages` | GitHub Pages deployment |
| `configure-argocd-automerge` | Auto-merge workflow for ArgoCD Image Updater branches |
| `configure-claude-plugins` | Configure Claude Code plugin marketplace and GitHub Actions workflows |

### Git Metadata

| Skill | Description |
|-------|-------------|
| `configure-gitattributes` | `.gitattributes`: union-merge append-only tables, linguist-generated build output, LF normalization |
| `configure-gitignore` | `.gitignore`: append a managed Claude Code runtime-state block (worktrees, scheduled-task lock, local settings) |
| `configure-worktreeinclude` | `.worktreeinclude`: copy gitignored env/secret/config inputs into new worktrees, built from the repo's actual ignored files |

### Containers & Deploy

| Skill | Description |
|-------|-------------|
| `configure-dockerfile` | Dockerfile for project standards (minimal Alpine/slim, non-root, multi-stage) |
| `configure-container` | Container infrastructure (builds, registry, scanning, devcontainer) |
| `configure-skaffold` | Skaffold configuration |

### Testing

| Skill | Description |
|-------|-------------|
| `configure-tests` | Testing frameworks and infrastructure |
| `configure-coverage` | Code coverage thresholds and reporting |
| `configure-api-tests` | API testing configuration |
| `configure-integration-tests` | Integration test configuration |
| `configure-load-tests` | Load/performance test configuration |
| `configure-memory-profiling` | Memory profiling with pytest-memray for Python |
| `configure-ux-testing` | UX testing (Playwright, accessibility, visual regression) |

### Code Quality

| Skill | Description |
|-------|-------------|
| `configure-linting` | Linting tools (Biome, Ruff, Clippy) |
| `configure-formatting` | Code formatting (Biome, Prettier, Ruff, rustfmt) |
| `configure-dead-code` | Dead code detection (Knip, Vulture, cargo-machete) |

### Security

| Skill | Description |
|-------|-------------|
| `configure-security` | Security scanning (dependency audits, SAST, secrets) |

### Documentation

| Skill | Description |
|-------|-------------|
| `configure-docs` | Documentation standards and generators |
| `configure-readme` | README.md with logo, badges, features, tech stack sections |
| `configure-surface` | Surface doc↔code drift gate (deterministic, SHA-pinned) |

### Feature Flags

| Skill | Description |
|-------|-------------|
| `configure-feature-flags` | Feature flag infrastructure (OpenFeature + providers) |

### Package Management

| Skill | Description |
|-------|-------------|
| `configure-package-management` | Modern package managers (uv for Python, bun for TypeScript) |
| `configure-mise` | mise tool/runtime version manager — mise.toml, backends, tasks, env, lockfile, migrations |
| `configure-cache-busting` | Cache-busting strategies for Next.js and Vite |

### Editor & Dev Environment

| Skill | Description |
|-------|-------------|
| `configure-editor` | EditorConfig and VS Code workspace settings |
| `configure-mcp` | MCP servers for project integration |
| `configure-makefile` | Makefile with standard targets |
| `configure-justfile` | Justfile with standard recipes (simpler alternative to Make) |
| `configure-web-session` | SessionStart hook + install script for Claude Code on the web |
| `configure-sentry` | Sentry error tracking |

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

Automatically configures the project to meet all project standards.

### Select Components Interactively

```bash
/configure:select
```

Presents multi-select menus to choose which components to check/fix.

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

### Onboard a Repo to Claude Code (end-to-end)

```bash
/configure:repo
```

The recommended starting point for any new repo. Runs the full onboarding workflow:
1. Detects project stack
2. Configures plugins, permissions, and marketplace enrollment in `.claude/settings.json`
3. Creates `scripts/install_pkgs.sh` + `SessionStart` hook for web sessions
4. Optionally offers tooling migrations (mypy→ty, black→ruff-format, etc.)
5. Validates with `/health:check`
6. Stages all files for commit

The `extraKnownMarketplaces` enrollment in `.claude/settings.json` is critical for
ephemeral web sessions (claude.ai/code) — without it, plugins are lost on every new session.

### Set Up Claude Code on the Web

```bash
/configure:web-session --fix
```

Creates `scripts/install_pkgs.sh` and configures a `SessionStart` hook in
`.claude/settings.json` so remote sessions auto-install infrastructure tools
(helm, terraform, tflint, actionlint, gitleaks, just, pre-commit) that are
absent from the base image.

## Standards Summary

- **Pre-commit**: Standardized hooks for linting, formatting, security checks
- **CI/CD**: GitHub Actions workflows for testing, building, releasing
- **Containers**: Minimal base images, non-root users, multi-stage builds
- **Testing**: Framework detection, coverage thresholds, tiered execution
- **Code Quality**: Consistent linting/formatting across languages
- **Security**: Dependency audits, SAST scanning, secrets detection

## Installation

```bash
/plugin install configure-plugin@laurigates-claude-plugins
```

## License

MIT
