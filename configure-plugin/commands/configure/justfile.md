---
created: 2025-12-16
modified: 2025-12-16
reviewed: 2025-12-16
description: Check and configure Justfile with standard recipes for FVH standards
allowed-tools: Glob, Grep, Read, Write, Edit, Bash, AskUserQuestion, TodoWrite
argument-hint: "[--check-only] [--fix]"
---

# /configure:justfile

Check and configure project Justfile against FVH (Forum Virium Helsinki) standards.

## Context

This command validates and creates Justfiles with standard recipes for consistent development workflows across projects. Just is a simpler, cross-platform alternative to Make with clearer syntax and better error messages.

**Required Justfile recipes**: `default`, `help`, `test`, `lint`, `build`, `clean`

**Optional recipes**: `format`, `start`, `stop`, `dev`

## Workflow

### Phase 1: Detection

1. Check for `justfile` or `Justfile` in project root
2. If exists, analyze current recipes and settings
3. Detect project type (python, node, rust, go, generic)

### Phase 2: Recipe Analysis

**Required recipes for all projects:**

| Recipe | Purpose | Severity |
|--------|---------|----------|
| `default` | Alias to help (first recipe) | FAIL if missing |
| `help` | Display available recipes | FAIL if missing |
| `test` | Run test suite | FAIL if missing |
| `lint` | Run linters | FAIL if missing |
| `build` | Build project artifacts | WARN if missing |
| `clean` | Remove temporary files | WARN if missing |

**Additional recipes (context-dependent):**

| Recipe | When Required | Severity |
|--------|---------------|----------|
| `format` | If project uses auto-formatters | WARN |
| `start` | If project has runnable service | INFO |
| `stop` | If project has background service | INFO |
| `dev` | If project supports watch mode | INFO |

### Phase 3: Compliance Checks

| Check | Standard | Severity |
|-------|----------|----------|
| File exists | justfile present | FAIL if missing |
| Default recipe | First recipe is `default` | WARN if missing |
| Dotenv loading | `set dotenv-load` present | INFO |
| Help recipe | Lists all recipes | FAIL if missing |
| Language-specific | Commands match project type | FAIL if mismatched |
| Recipe comments | Recipes have descriptions | INFO |

### Phase 4: Report Generation

```
FVH Justfile Compliance Report
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

### Phase 5: Configuration (If Requested)

If `--fix` flag or user confirms:

1. **Missing Justfile**: Create from FVH template based on project type
2. **Missing recipes**: Add recipes with appropriate commands
3. **Missing settings**: Add `set dotenv-load` if `.env` exists
4. **Missing help**: Add help recipe with `just --list`

### Phase 6: Standards Tracking

Update `.fvh-standards.yaml`:

```yaml
components:
  justfile: "2025.1"
```

## FVH Justfile Template

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

**Project type detection (in order):**

1. **Python**: `pyproject.toml` or `requirements.txt` present
2. **Node**: `package.json` present
3. **Rust**: `Cargo.toml` present
4. **Go**: `go.mod` present
5. **Generic**: None of the above

**Service detection (start/stop needed):**

- Has `docker-compose.yml` → Docker Compose service
- Has `Dockerfile` + HTTP server code → Container service
- Has `src/server.*` or `src/main.*` → Application service

**Dev mode detection:**

- Python: Has FastAPI/Flask/Django → uvicorn/flask/manage.py with reload
- Node: Has `dev` script in package.json
- Rust: Has `cargo-watch` in dependencies
- Go: Has `air.toml` or `main.go`

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

## Migration from Makefile

If a Makefile exists but no Justfile:

1. Detect project type from Makefile commands
2. Suggest creating Justfile with equivalent recipes
3. Optionally keep Makefile for backwards compatibility

**Note**: Full `--migrate-from makefile` support planned for future iteration.

## Advantages over Makefile

| Aspect | Justfile | Makefile |
|--------|----------|----------|
| Syntax | Simple, clear | Complex, tabs required |
| Error messages | Clear and helpful | Often cryptic |
| Cross-platform | Excellent | Good (shell differences) |
| Parameters | Full support | Limited |
| Dependencies | Built-in | Built-in |
| Installation | Single binary | Pre-installed |

## See Also

- `/configure:makefile` - Makefile configuration (legacy)
- `/configure:all` - Run all FVH compliance checks
- `/configure:workflows` - GitHub Actions workflows
- `/configure:dockerfile` - Docker configuration
- `justfile-expert` skill - Comprehensive Just expertise
