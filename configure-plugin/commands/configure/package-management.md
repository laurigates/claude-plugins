---
description: Check and configure modern package managers (uv for Python, bun for TypeScript)
allowed-tools: Glob, Grep, Read, Write, Edit, Bash, AskUserQuestion, TodoWrite, WebSearch, WebFetch
argument-hint: "[--check-only] [--fix] [--manager <uv|bun|npm|cargo>]"
---

# /configure:package-management

Check and configure modern package managers for optimal development experience.

## Context

This command validates package manager configuration and migrates to modern tools.

**Modern package manager preferences:**
- **Python**: uv (replaces pip, poetry, pipenv, pyenv) - 10-100x faster
- **JavaScript/TypeScript**: bun (alternative to npm/yarn/pnpm) - significantly faster
- **Rust**: cargo (standard, no alternatives needed)
- **Go**: go mod (standard, no alternatives needed)

## Version Checking

**CRITICAL**: Before configuring package managers, verify latest versions:

1. **uv**: Check [docs.astral.sh/uv](https://docs.astral.sh/uv/) or [GitHub releases](https://github.com/astral-sh/uv/releases)
2. **bun**: Check [bun.sh](https://bun.sh/) or [GitHub releases](https://github.com/oven-sh/bun/releases)
3. **npm**: Check [npm docs](https://docs.npmjs.com/) for latest version
4. **Rust/cargo**: Check [Rust releases](https://releases.rs/)

Use WebSearch or WebFetch to verify current versions before configuring package managers.

## Workflow

### Phase 1: Language Detection

Detect project languages and current package managers:

| Indicator | Language | Current Manager | Recommended |
|-----------|----------|-----------------|-------------|
| `pyproject.toml` | Python | uv / poetry / pip | uv |
| `requirements.txt` | Python | pip | uv |
| `Pipfile` | Python | pipenv | uv |
| `poetry.lock` | Python | poetry | uv |
| `uv.lock` | Python | uv ✓ | uv |
| `package.json` + `bun.lockb` | JavaScript/TypeScript | bun ✓ | bun |
| `package.json` + `package-lock.json` | JavaScript/TypeScript | npm | bun |
| `package.json` + `yarn.lock` | JavaScript/TypeScript | yarn | bun |
| `package.json` + `pnpm-lock.yaml` | JavaScript/TypeScript | pnpm | bun |
| `Cargo.toml` | Rust | cargo ✓ | cargo |
| `go.mod` | Go | go mod ✓ | go mod |

### Phase 2: Current State Analysis

For each detected language, check configuration:

**Python (uv):**
- [ ] `uv` installed and on PATH
- [ ] `pyproject.toml` exists with `[project]` section
- [ ] `uv.lock` exists (lock file)
- [ ] Virtual environment in `.venv/`
- [ ] Python version pinned in `pyproject.toml`
- [ ] Dependency groups configured (dev, test, docs)
- [ ] Build system specified (`hatchling`, `setuptools`, etc.)

**JavaScript/TypeScript (bun):**
- [ ] `bun` installed and on PATH
- [ ] `package.json` exists
- [ ] `bun.lockb` exists (lock file)
- [ ] `node_modules/` exists
- [ ] Scripts defined (`dev`, `build`, `test`, `lint`)
- [ ] Type definitions configured (TypeScript)
- [ ] Workspaces configured (if monorepo)

### Phase 3: Compliance Report

```
Package Management Configuration Report
=======================================
Project: [name]
Languages: Python, TypeScript

Python:
  Package manager           uv 0.5.x                   [✅ MODERN | ⚠️ LEGACY pip]
  pyproject.toml            exists                     [✅ EXISTS | ❌ MISSING]
  Lock file                 uv.lock                    [✅ EXISTS | ⚠️ OUTDATED | ❌ MISSING]
  Virtual environment       .venv/                     [✅ EXISTS | ❌ MISSING]
  Python version            3.12                       [✅ PINNED | ⚠️ NOT PINNED]
  Dependency groups         dev, test, docs            [✅ CONFIGURED | ⚠️ MINIMAL]
  Build backend             hatchling                  [✅ CONFIGURED | ⚠️ MISSING]

JavaScript/TypeScript:
  Package manager           bun 1.1.x                  [✅ MODERN | ⚠️ npm | ⚠️ yarn]
  package.json              exists                     [✅ EXISTS | ❌ MISSING]
  Lock file                 bun.lockb                  [✅ EXISTS | ❌ MISSING]
  Scripts                   dev, build, test, lint     [✅ COMPLETE | ⚠️ INCOMPLETE]
  Type definitions          tsconfig.json              [✅ CONFIGURED | ⚠️ MISSING]
  Engine constraints        package.json engines       [✅ PINNED | ⚠️ NOT PINNED]

Overall: [X issues found]

Recommendations:
  - Migrate from pip to uv for faster installs
  - Add uv.lock to version control
  - Configure dependency groups in pyproject.toml
  - Migrate from npm to bun for better performance
```

### Phase 4: Configuration (if --fix or user confirms)

#### Python with uv

**Install uv:**
```bash
# Via mise (recommended)
mise use uv@latest

# Or via curl
curl -LsSf https://astral.sh/uv/install.sh | sh

# Or via homebrew
brew install uv
```

**Initialize project:**
```bash
# New project
uv init my-project
cd my-project

# Existing project with requirements.txt
uv init
uv add -r requirements.txt
rm requirements.txt

# Existing project with poetry
uv init
# Copy dependencies from pyproject.toml [tool.poetry.dependencies]
# Then: uv add <deps>
```

**Create `pyproject.toml`:**
```toml
[project]
name = "my-project"
version = "0.1.0"
description = "Project description"
readme = "README.md"
requires-python = ">=3.12"
license = { text = "MIT" }
authors = [
    { name = "Your Name", email = "you@example.com" }
]
dependencies = [
    # Production dependencies
]

[project.optional-dependencies]
dev = [
    "ruff>=0.8.0",
    "basedpyright>=1.22.0",
]
test = [
    "pytest>=8.0",
    "pytest-cov>=6.0",
    "pytest-asyncio>=0.24",
]
docs = [
    "mkdocs>=1.6",
    "mkdocs-material>=9.5",
]

[build-system]
requires = ["hatchling"]
build-backend = "hatchling.build"

[tool.uv]
dev-dependencies = [
    # Dev dependencies installed with `uv sync`
    "ruff>=0.8.0",
    "basedpyright>=1.22.0",
    "pytest>=8.0",
]

[tool.hatch.build.targets.wheel]
packages = ["src/my_project"]
```

**Common uv commands:**
```bash
# Install dependencies
uv sync

# Add production dependency
uv add httpx

# Add dev dependency
uv add --group dev pytest

# Run script
uv run python script.py
uv run pytest

# Create virtual environment
uv venv

# Pin Python version
uv python pin 3.12

# Update dependencies
uv lock --upgrade
uv sync
```

**Add to `.gitignore`:**
```gitignore
# Python
.venv/
__pycache__/
*.pyc
.pytest_cache/
.ruff_cache/
dist/
*.egg-info/
```

#### JavaScript/TypeScript with bun

**Install bun:**
```bash
# Via mise (recommended)
mise use bun@latest

# Or via curl
curl -fsSL https://bun.sh/install | bash

# Or via homebrew
brew install bun
```

**Initialize project:**
```bash
# New project
bun init

# Existing project - migrate from npm
rm -rf node_modules package-lock.json
bun install

# Existing project - migrate from yarn
rm -rf node_modules yarn.lock
bun install

# Existing project - migrate from pnpm
rm -rf node_modules pnpm-lock.yaml
bun install
```

**Create/update `package.json`:**
```json
{
  "name": "my-project",
  "version": "0.1.0",
  "type": "module",
  "scripts": {
    "dev": "bun run --watch src/index.ts",
    "build": "bun build src/index.ts --outdir dist",
    "test": "bun test",
    "lint": "biome check .",
    "lint:fix": "biome check --write .",
    "typecheck": "tsc --noEmit"
  },
  "dependencies": {},
  "devDependencies": {
    "@biomejs/biome": "^1.9.0",
    "@types/bun": "latest",
    "typescript": "^5.7.0"
  },
  "engines": {
    "bun": ">=1.1.0"
  }
}
```

**TypeScript configuration (`tsconfig.json`):**
```json
{
  "compilerOptions": {
    "target": "ESNext",
    "module": "ESNext",
    "moduleResolution": "bundler",
    "strict": true,
    "skipLibCheck": true,
    "noEmit": true,
    "esModuleInterop": true,
    "allowSyntheticDefaultImports": true,
    "resolveJsonModule": true,
    "isolatedModules": true,
    "types": ["bun-types"]
  },
  "include": ["src/**/*"],
  "exclude": ["node_modules", "dist"]
}
```

**Common bun commands:**
```bash
# Install dependencies
bun install

# Add dependency
bun add zod

# Add dev dependency
bun add --dev @types/node

# Run script
bun run dev
bun run build

# Run TypeScript directly
bun src/index.ts

# Run tests
bun test

# Update dependencies
bun update
```

**Add to `.gitignore`:**
```gitignore
# JavaScript/TypeScript
node_modules/
dist/
.turbo/
*.tsbuildinfo
```

### Phase 5: Migration Guides

#### pip/poetry → uv Migration

**Step 1: Install uv**
```bash
mise use uv@latest
```

**Step 2: Initialize uv project**
```bash
uv init
```

**Step 3: Migrate dependencies**

From `requirements.txt`:
```bash
uv add -r requirements.txt
rm requirements.txt
```

From `poetry` (`pyproject.toml`):
```bash
# Extract dependencies from [tool.poetry.dependencies]
# Add them with uv add
uv add httpx fastapi pydantic
uv add --group dev pytest ruff
```

**Step 4: Remove old files**
```bash
rm -f requirements.txt requirements-dev.txt
rm -f Pipfile Pipfile.lock
rm -f poetry.lock
# Update pyproject.toml to remove [tool.poetry] section
```

**Step 5: Update CI/CD**
```yaml
# GitHub Actions
- name: Install uv
  uses: astral-sh/setup-uv@v4

- name: Install dependencies
  run: uv sync

- name: Run tests
  run: uv run pytest
```

#### npm/yarn/pnpm → bun Migration

**Step 1: Install bun**
```bash
mise use bun@latest
```

**Step 2: Remove old lock files**
```bash
rm -rf node_modules
rm -f package-lock.json yarn.lock pnpm-lock.yaml
```

**Step 3: Install with bun**
```bash
bun install
```

**Step 4: Update scripts**
Replace npm/yarn/pnpm scripts with bun equivalents:
```json
{
  "scripts": {
    "dev": "bun run --watch src/index.ts",
    "build": "bun build src/index.ts --outdir dist",
    "test": "bun test"
  }
}
```

**Step 5: Update CI/CD**
```yaml
# GitHub Actions
- name: Setup Bun
  uses: oven-sh/setup-bun@v2

- name: Install dependencies
  run: bun install

- name: Run tests
  run: bun test
```

### Phase 6: CI/CD Integration

**GitHub Actions - uv:**
```yaml
- name: Install uv
  uses: astral-sh/setup-uv@v4
  with:
    enable-cache: true

- name: Set up Python
  run: uv python install

- name: Install dependencies
  run: uv sync --all-extras

- name: Run tests
  run: uv run pytest
```

**GitHub Actions - bun:**
```yaml
- name: Setup Bun
  uses: oven-sh/setup-bun@v2
  with:
    bun-version: latest

- name: Install dependencies
  run: bun install --frozen-lockfile

- name: Run tests
  run: bun test
```

### Phase 7: Standards Tracking

Update `.fvh-standards.yaml`:

```yaml
standards_version: "2025.1"
last_configured: "[timestamp]"
components:
  package_management: "2025.1"
  python_package_manager: "uv"
  javascript_package_manager: "bun"
  lock_files_committed: true
```

### Phase 8: Final Report

```
Package Management Configuration Complete
==========================================

Python:
  ✅ uv installed (0.5.x)
  ✅ pyproject.toml configured
  ✅ uv.lock created
  ✅ Dependency groups: dev, test, docs
  ✅ Python 3.12 pinned

JavaScript/TypeScript:
  ✅ bun installed (1.1.x)
  ✅ package.json updated
  ✅ bun.lockb created
  ✅ Scripts configured

Migration:
  ✅ poetry.lock removed
  ✅ package-lock.json removed
  ✅ CI/CD workflows updated

Next Steps:
  1. Verify dependencies install correctly:
     uv sync && bun install

  2. Run tests to ensure nothing broke:
     uv run pytest && bun test

  3. Commit lock files:
     git add uv.lock bun.lockb

Documentation: docs/PACKAGE_MANAGEMENT.md
```

## Flags

| Flag | Description |
|------|-------------|
| `--check-only` | Report status without offering migrations |
| `--fix` | Apply all migrations automatically without prompting |
| `--manager <manager>` | Override detection (uv, bun, npm, cargo) |

## Examples

```bash
# Check compliance and offer migrations
/configure:package-management

# Check only, no modifications
/configure:package-management --check-only

# Auto-migrate Python to uv
/configure:package-management --fix --manager uv

# Auto-migrate JavaScript to bun
/configure:package-management --fix --manager bun
```

## Error Handling

- **Multiple Python managers detected**: Warn about conflict, suggest single source of truth
- **Missing package manager**: Offer to install via mise
- **Invalid pyproject.toml**: Report parse error, offer template
- **Lock file conflicts**: Warn about multiple lock files, suggest cleanup
- **Workspace/monorepo**: Detect and configure workspace settings

## See Also

- `/configure:linting` - Configure linting tools (ruff, biome)
- `/configure:formatting` - Configure formatters
- `/deps:install` - Universal dependency installer
- `/configure:all` - Run all FVH compliance checks
- **uv documentation**: https://docs.astral.sh/uv
- **bun documentation**: https://bun.sh/docs
