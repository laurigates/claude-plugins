---
model: haiku
created: 2025-12-16
modified: 2026-02-11
reviewed: 2025-12-16
description: Check and configure Justfile with standard recipes for project standards
allowed-tools: Glob, Grep, Read, Write, Edit, Bash, AskUserQuestion, TodoWrite
argument-hint: "[--check-only] [--fix]"
name: configure-justfile
---

# /configure:justfile

Check and configure project Justfile against project standards.

## When to Use This Skill

| Use this skill when... | Use another approach when... |
|------------------------|------------------------------|
| Setting up a new Justfile for a project | Project already uses Make exclusively and migration is not desired — use `/configure:makefile` |
| Auditing existing Justfile for missing standard recipes | Writing complex custom recipes — use `justfile-expert` skill |
| Migrating from Makefile to Justfile | Project has no task runner needs (single-file scripts) |
| Ensuring Justfile follows team conventions (groups, comments, settings) | Debugging a specific recipe failure — use direct `just` commands |
| Running CI/CD compliance checks on project task runners | Only need to list available recipes — run `just --list` directly |

## Context

- Project root: !`pwd`
- Justfile: !`find . -maxdepth 1 \( -name 'justfile' -o -name 'Justfile' \) 2>/dev/null`
- Makefile: !`find . -maxdepth 1 -name 'Makefile' 2>/dev/null`
- Package files: !`find . -maxdepth 1 \( -name 'package.json' -o -name 'pyproject.toml' -o -name 'Cargo.toml' -o -name 'go.mod' \) 2>/dev/null`
- Docker files: !`find . -maxdepth 1 \( -name 'Dockerfile' -o -name 'docker-compose.yml' \) 2>/dev/null`
- Env file: !`find . -maxdepth 1 -name '.env' 2>/dev/null`
- Project standards: !`find . -maxdepth 1 -name '.project-standards.yaml' 2>/dev/null`

## Parameters

Parse from command arguments:

- `--check-only`: Report compliance status without modifications (CI/CD mode)
- `--fix`: Apply fixes automatically without prompting

## Execution

Execute this Justfile compliance check:

### Step 1: Detect Justfile and project type

1. Check for `justfile` or `Justfile` in project root
2. If exists, read and analyze current recipes and settings
3. Detect project type from file indicators:

| Indicator | Project Type |
|-----------|--------------|
| `pyproject.toml` or `requirements.txt` | Python |
| `package.json` | Node.js |
| `Cargo.toml` | Rust |
| `go.mod` | Go |
| None of the above | Generic |

### Step 2: Analyze required and optional recipes

Check for required recipes:

| Recipe | Purpose | Severity |
|--------|---------|----------|
| `default` | Alias to help (first recipe) | FAIL if missing |
| `help` | Display available recipes | FAIL if missing |
| `test` | Run test suite | FAIL if missing |
| `lint` | Run linters | FAIL if missing |
| `build` | Build project artifacts | WARN if missing |
| `clean` | Remove temporary files | WARN if missing |

Check for context-dependent recipes:

| Recipe | When Required | Severity |
|--------|---------------|----------|
| `format` | If project uses auto-formatters | WARN |
| `start` | If project has runnable service | INFO |
| `stop` | If project has background service | INFO |
| `dev` | If project supports watch mode | INFO |

### Step 3: Check compliance settings

Validate Justfile settings:

| Check | Standard | Severity |
|-------|----------|----------|
| File exists | justfile present | FAIL if missing |
| Default recipe | First recipe is `default` | WARN if missing |
| Dotenv loading | `set dotenv-load` present | INFO |
| Help recipe | Lists all recipes | FAIL if missing |
| Language-specific | Commands match project type | FAIL if mismatched |
| Recipe comments | Recipes have descriptions | INFO |

### Step 4: Generate compliance report

Print a formatted compliance report:

```
Justfile Compliance Report
==============================
Project Type: python (detected)
Justfile: Found

Recipe Status:
  default ✅ PASS
  help    ✅ PASS (just --list)
  test    ✅ PASS (uv run pytest)
  lint    ✅ PASS (uv run ruff check)
  build   ✅ PASS (docker build)
  clean   ✅ PASS
  format  ✅ PASS (uv run ruff format)
  start   ⚠️  INFO (not applicable)
  stop    ⚠️  INFO (not applicable)
  dev     ✅ PASS (uv run uvicorn --reload)

Settings Status:
  dotenv-load         ✅ PASS
  positional-arguments ℹ️  INFO (not set)

Missing Recipes: none
Issues: 0 found
```

If `--check-only`, stop here.

### Step 5: Create or update Justfile (if --fix or user confirms)

If `--fix` flag or user confirms:

1. **Missing Justfile**: Create from standard template based on project type
2. **Missing recipes**: Add recipes with appropriate commands
3. **Missing settings**: Add `set dotenv-load` if `.env` exists
4. **Missing help**: Add help recipe with `just --list`

Use language-specific commands from the template section below.

### Step 6: Update standards tracking

Update `.project-standards.yaml`:

```yaml
components:
  justfile: "2025.1"
```

## Justfile Template

### Universal Structure

```just
# Justfile for {{PROJECT_NAME}}
# Run `just` or `just help` to see available recipes

set dotenv-load
set positional-arguments

# Default recipe - show help
default:
    @just --list

# Show available recipes with descriptions
help:
    @just --list --unsorted

####################
# Development
####################

# Run linters
lint:
    {{LINT_COMMAND}}

# Format code
format:
    {{FORMAT_COMMAND}}

# Run tests
test *args:
    {{TEST_COMMAND}} {{args}}

# Development mode with watch
dev:
    {{DEV_COMMAND}}

####################
# Build & Deploy
####################

# Build project
build:
    {{BUILD_COMMAND}}

# Clean build artifacts
clean:
    {{CLEAN_COMMAND}}

# Start service
start:
    {{START_COMMAND}}

# Stop service
stop:
    {{STOP_COMMAND}}
```

### Language-Specific Commands

**Python (uv-based):**
```just
lint:
    uv run ruff check .

format:
    uv run ruff format .
    uv run ruff check --fix .

test *args:
    uv run pytest {{args}}

dev:
    uv run uvicorn app:app --reload

build:
    docker build -t {{PROJECT_NAME}} .

clean:
    find . -type f -name "*.pyc" -delete
    find . -type d -name "__pycache__" -exec rm -rf {} + 2>/dev/null || true
    rm -rf .pytest_cache .ruff_cache .coverage htmlcov dist build *.egg-info
```

**Node.js (Bun-based):**
```just
lint:
    bun run lint

format:
    bun run format

test *args:
    bun test {{args}}

dev:
    bun run dev

build:
    bun run build

clean:
    rm -rf node_modules dist .next .turbo .cache
```

**Rust:**
```just
lint:
    cargo clippy -- -D warnings

format:
    cargo fmt

test *args:
    cargo nextest run {{args}}

dev:
    cargo watch -x run

build:
    cargo build --release

clean:
    cargo clean
```

**Go:**
```just
lint:
    golangci-lint run

format:
    gofmt -s -w .
    goimports -w .

test *args:
    go test ./... {{args}}

dev:
    air

build:
    go build -o bin/{{PROJECT_NAME}} ./cmd/{{PROJECT_NAME}}

clean:
    rm -rf bin dist
    go clean -cache
```

## Detection Logic

**Service detection (start/stop needed):**
- Has `docker-compose.yml` -> Docker Compose service
- Has `Dockerfile` + HTTP server code -> Container service
- Has `src/server.*` or `src/main.*` -> Application service

**Dev mode detection:**
- Python: Has FastAPI/Flask/Django -> uvicorn/flask/manage.py with reload
- Node: Has `dev` script in package.json
- Rust: Has `cargo-watch` in dependencies
- Go: Has `air.toml` or `main.go`

## Migration from Makefile

If a Makefile exists but no Justfile:
1. Detect project type from Makefile commands
2. Suggest creating Justfile with equivalent recipes
3. Optionally keep Makefile for backwards compatibility

## Agentic Optimizations

| Context | Command |
|---------|---------|
| Quick compliance check | `/configure:justfile --check-only` |
| Auto-fix all issues | `/configure:justfile --fix` |
| List existing recipes | `just --list` |
| Verify specific recipe exists | `just --summary` |
| Check Justfile syntax | `just --evaluate 2>&1` |

## Flags

| Flag | Description |
|------|-------------|
| `--check-only` | Report status without offering fixes |
| `--fix` | Apply fixes automatically |

## Examples

```bash
# Check current Justfile compliance
/configure:justfile --check-only

# Create/update Justfile for Python project
/configure:justfile --fix

# Check compliance and prompt for fixes
/configure:justfile
```

## See Also

- `/configure:makefile` - Makefile configuration (legacy)
- `/configure:all` - Run all compliance checks
- `/configure:workflows` - GitHub Actions workflows
- `/configure:dockerfile` - Docker configuration
- `justfile-expert` skill - Comprehensive Just expertise
