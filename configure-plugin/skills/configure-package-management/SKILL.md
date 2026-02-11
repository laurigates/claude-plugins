---
model: haiku
created: 2025-12-16
modified: 2026-02-11
reviewed: 2025-12-16
description: Check and configure modern package managers (uv for Python, bun for TypeScript)
allowed-tools: Glob, Grep, Read, Write, Edit, Bash, AskUserQuestion, TodoWrite, WebSearch, WebFetch
argument-hint: "[--check-only] [--fix] [--manager <uv|bun|npm|cargo>]"
name: configure-package-management
---

# /configure:package-management

Check and configure modern package managers for optimal development experience.

## When to Use This Skill

| Use this skill when... | Use another approach when... |
|------------------------|------------------------------|
| Setting up a new project with modern package managers (uv, bun) | Installing a single dependency — run `uv add` or `bun add` directly |
| Migrating from legacy package managers (pip, npm, yarn, poetry) to modern ones | Project uses cargo or go mod (already optimal, no migration needed) |
| Auditing package manager configuration for best practices | Configuring linting or formatting tools — use `/configure:linting` |
| Ensuring lock files, dependency groups, and CI/CD integration are properly configured | Resolving a specific dependency conflict — debug with `uv pip compile` or `bun install --verbose` |
| Detecting and cleaning up conflicting lock files from multiple managers | Only need to install dependencies — run `uv sync` or `bun install` directly |

## Context

- Project root: !`pwd`
- Package files: !`find . -maxdepth 1 \( -name 'package.json' -o -name 'pyproject.toml' -o -name 'Cargo.toml' -o -name 'go.mod' \) 2>/dev/null`
- Lock files: !`find . -maxdepth 1 \( -name 'uv.lock' -o -name 'bun.lockb' -o -name 'package-lock.json' -o -name 'yarn.lock' -o -name 'pnpm-lock.yaml' -o -name 'poetry.lock' -o -name 'Pipfile.lock' \) 2>/dev/null`
- Python venv: !`find . -maxdepth 1 -type d -name '.venv' 2>/dev/null`
- Legacy files: !`find . -maxdepth 1 \( -name 'requirements.txt' -o -name 'Pipfile' \) 2>/dev/null`
- Project standards: !`find . -maxdepth 1 -name '.project-standards.yaml' 2>/dev/null`

## Parameters

Parse from command arguments:

- `--check-only`: Report compliance status without modifications (CI/CD mode)
- `--fix`: Apply fixes automatically without prompting
- `--manager <uv|bun|npm|cargo>`: Override detection (focus on specific manager)

**Modern package manager preferences:**
- **Python**: uv (replaces pip, poetry, pipenv, pyenv) - 10-100x faster
- **JavaScript/TypeScript**: bun (alternative to npm/yarn/pnpm) - significantly faster
- **Rust**: cargo (standard, no alternatives needed)
- **Go**: go mod (standard, no alternatives needed)

## Execution

Execute this package management compliance check:

### Step 1: Detect project languages and current package managers

Check for language and manager indicators:

| Indicator | Language | Current Manager | Recommended |
|-----------|----------|-----------------|-------------|
| `pyproject.toml` | Python | uv / poetry / pip | uv |
| `requirements.txt` | Python | pip | uv |
| `Pipfile` | Python | pipenv | uv |
| `poetry.lock` | Python | poetry | uv |
| `uv.lock` | Python | uv | uv |
| `package.json` + `bun.lockb` | JavaScript/TypeScript | bun | bun |
| `package.json` + `package-lock.json` | JavaScript/TypeScript | npm | bun |
| `package.json` + `yarn.lock` | JavaScript/TypeScript | yarn | bun |
| `package.json` + `pnpm-lock.yaml` | JavaScript/TypeScript | pnpm | bun |
| `Cargo.toml` | Rust | cargo | cargo |
| `go.mod` | Go | go mod | go mod |

Use WebSearch or WebFetch to verify latest versions before configuring.

### Step 2: Analyze current configuration state

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

### Step 3: Generate compliance report

Print a formatted compliance report:

```
Package Management Configuration Report
=======================================
Project: [name]
Languages: Python, TypeScript

Python:
  Package manager           uv 0.5.x                   [MODERN | LEGACY pip]
  pyproject.toml            exists                     [EXISTS | MISSING]
  Lock file                 uv.lock                    [EXISTS | OUTDATED | MISSING]
  Virtual environment       .venv/                     [EXISTS | MISSING]
  Python version            3.12                       [PINNED | NOT PINNED]
  Dependency groups         dev, test, docs            [CONFIGURED | MINIMAL]
  Build backend             hatchling                  [CONFIGURED | MISSING]

JavaScript/TypeScript:
  Package manager           bun 1.1.x                  [MODERN | npm | yarn]
  package.json              exists                     [EXISTS | MISSING]
  Lock file                 bun.lockb                  [EXISTS | MISSING]
  Scripts                   dev, build, test, lint     [COMPLETE | INCOMPLETE]
  Type definitions          tsconfig.json              [CONFIGURED | MISSING]
  Engine constraints        package.json engines       [PINNED | NOT PINNED]

Overall: [X issues found]

Recommendations:
  - Migrate from pip to uv for faster installs
  - Add uv.lock to version control
  - Configure dependency groups in pyproject.toml
  - Migrate from npm to bun for better performance
```

If `--check-only`, stop here.

### Step 4: Configure package managers (if --fix or user confirms)

Apply configuration based on detected languages. Use templates from [REFERENCE.md](REFERENCE.md):

#### Python with uv
1. Install uv (via mise, curl, or homebrew)
2. Initialize project with `uv init` or migrate from existing manager
3. Create/update `pyproject.toml` with project metadata and dependency groups
4. Generate `uv.lock`
5. Update `.gitignore`

#### JavaScript/TypeScript with bun
1. Install bun (via mise, curl, or homebrew)
2. Remove old lock files (`package-lock.json`, `yarn.lock`, `pnpm-lock.yaml`)
3. Run `bun install` to generate `bun.lockb`
4. Update scripts in `package.json`
5. Update `.gitignore`

### Step 5: Handle migrations

If migrating from a legacy manager:

**pip/poetry to uv:**
1. Install uv
2. Run `uv init`
3. Migrate dependencies: `uv add -r requirements.txt` or copy from poetry
4. Remove old files (`requirements.txt`, `Pipfile`, `poetry.lock`)
5. Update CI/CD workflows

**npm/yarn/pnpm to bun:**
1. Install bun
2. Remove old lock files and `node_modules`
3. Run `bun install`
4. Update scripts to use bun equivalents
5. Update CI/CD workflows

Use migration templates from [REFERENCE.md](REFERENCE.md).

### Step 6: Configure CI/CD integration

Update GitHub Actions workflows to use modern package managers:

- **Python**: Replace `pip install` with `astral-sh/setup-uv@v4` + `uv sync`
- **JavaScript**: Replace `actions/setup-node` with `oven-sh/setup-bun@v2`

Use CI workflow templates from [REFERENCE.md](REFERENCE.md).

### Step 7: Update standards tracking

Update `.project-standards.yaml`:

```yaml
standards_version: "2025.1"
last_configured: "[timestamp]"
components:
  package_management: "2025.1"
  python_package_manager: "uv"
  javascript_package_manager: "bun"
  lock_files_committed: true
```

### Step 8: Print final report

Print a summary of changes applied, migrations performed, and next steps for verifying the configuration.

For detailed configuration templates and migration guides, see [REFERENCE.md](REFERENCE.md).

## Agentic Optimizations

| Context | Command |
|---------|---------|
| Quick compliance check | `/configure:package-management --check-only` |
| Auto-fix all issues | `/configure:package-management --fix` |
| Check uv version | `uv --version` |
| Check bun version | `bun --version` |
| List Python deps | `uv pip list --format json` |
| List JS deps | `bun pm ls --json` |

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
- `/configure:all` - Run all compliance checks
- **uv documentation**: https://docs.astral.sh/uv
- **bun documentation**: https://bun.sh/docs
