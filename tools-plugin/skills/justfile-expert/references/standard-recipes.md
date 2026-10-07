# Justfile Expert — Standard and Workflow Recipes

The recipe set and layout every project justfile should carry, for [SKILL.md](../SKILL.md). The full golden template lives in [REFERENCE.md](../REFERENCE.md).

## Semantic Workflow Recipes

Standard composite recipes with defined meanings:

| Recipe | Composition | Purpose |
|--------|-------------|---------|
| `check` | `format-check` + `lint` + `typecheck` | Code quality only, no tests |
| `pre-commit` | `format-check` + `lint` + `typecheck` + `test-unit` | Fast, non-mutating validation |
| `ci` | `check` + `test-coverage` + `build` | Full CI simulation |
| `clean` | Remove build artifacts | Partial cleanup |
| `clean-all` | `clean` + remove deps/caches | Full cleanup |

```just
# Composite: code quality only (no tests)
check: format-check lint typecheck

# Pre-commit checks (fast, non-mutating)
pre-commit: format-check lint typecheck test-unit
    @echo "Pre-commit checks passed"

# Full CI simulation
ci: check test-coverage build
    @echo "CI simulation passed"

# Clean build artifacts
clean:
    rm -rf dist build .next

# Clean everything including deps
clean-all: clean
    rm -rf node_modules .venv __pycache__
```

## Standard Recipes

Every project should provide these standard recipes, organized by section:

```just
# Justfile - Project task runner
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

# Start development environment
dev:
    # bun run dev / uv run uvicorn app:app --reload / skaffold dev

# Build for production
build:
    # bun run build / cargo build --release / docker build

# Clean build artifacts
clean:
    # rm -rf dist build .next

####################
# Code Quality
####################

# Run linter (read-only)
lint *args:
    # bun run lint / uv run ruff check {{args}}

# Auto-fix lint issues
lint-fix:
    # bun run lint:fix / uv run ruff check --fix .

# Format code (mutating)
format *args:
    # bun run format / uv run ruff format {{args}}

# Check formatting without modifying (non-mutating)
format-check *args:
    # bun run format:check / uv run ruff format --check {{args}}

# Type checking
typecheck:
    # bunx tsc --noEmit / uv run basedpyright

####################
# Testing
####################

# Run all tests
test *args:
    # bun test {{args}} / uv run pytest {{args}}

# Run unit tests only
test-unit *args:
    # bun test --grep unit {{args}} / uv run pytest -m unit {{args}}

####################
# Workflows
####################

# Composite: code quality (no tests)
check: format-check lint typecheck

# Pre-commit checks (fast, non-mutating)
pre-commit: format-check lint typecheck test-unit
    @echo "Pre-commit checks passed"

# Full CI simulation
ci: check test-coverage build
    @echo "CI simulation passed"
```

### Section Structure

Organize recipes into these standard sections:

| Section | Recipes | Purpose |
|---------|---------|---------|
| **Metadata** | `default`, `help` | Discovery and navigation |
| **Development** | `dev`, `build`, `clean`, `start`, `stop` | Core dev cycle |
| **Code Quality** | `lint`, `lint-fix`, `format`, `format-check`, `typecheck` | Code standards |
| **Testing** | `test`, `test-unit`, `test-integration`, `test-e2e`, `test-watch` | Test tiers |
| **Workflows** | `check`, `pre-commit`, `ci` | Composite operations |
| **Dependencies** | `install`, `update` | Package management |
| **Database** | `db-migrate`, `db-seed`, `db-reset` | Data operations |
| **Kubernetes** | `skaffold`, `dev-k8s` | Container orchestration |
| **Documentation** | `docs`, `docs-serve` | Project docs |

Use `####################` comment blocks as section dividers for readability.
