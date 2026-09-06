# configure-justfile - Reference

Full Justfile templates, language-specific recipe bodies, project-type detection heuristics, and Makefile migration guidance.

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
