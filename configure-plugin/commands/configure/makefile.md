---
description: Check and configure Makefile with standard targets for FVH standards
allowed-tools: Glob, Grep, Read, Write, Edit, AskUserQuestion, TodoWrite
argument-hint: "[--check-only] [--fix]"
---

# /configure:makefile

Check and configure project Makefile against FVH (Forum Virium Helsinki) standards.

## Context

This command validates and creates Makefiles with standard targets for consistent development workflows across projects.

**Required Makefile targets**: `help`, `test`, `build`, `clean`, `start`, `stop`, `lint`

## Workflow

### Phase 1: Detection

1. Check for `Makefile` in project root
2. If exists, analyze current targets and structure
3. Detect project type (python, node, rust, go, generic)

### Phase 2: Target Analysis

**Required targets for all projects:**

| Target | Purpose |
|--------|---------|
| `help` | Display available targets (default goal) |
| `test` | Run test suite |
| `build` | Build project artifacts |
| `clean` | Remove temporary files and build artifacts |
| `lint` | Run linters |

**Additional targets (context-dependent):**

| Target | When Required |
|--------|---------------|
| `start` | If project has runnable service |
| `stop` | If project has background service |
| `format` | If project uses auto-formatters |

### Phase 3: Compliance Checks

| Check | Standard | Severity |
|-------|----------|----------|
| File exists | Makefile present | FAIL if missing |
| Default goal | `.DEFAULT_GOAL := help` | WARN if missing |
| PHONY declarations | All targets marked `.PHONY` | WARN if missing |
| Colored output | Color variables defined | INFO |
| Help target | Auto-generated from comments | WARN if missing |
| Language-specific | Commands match project type | FAIL if mismatched |

### Phase 4: Report Generation

```
FVH Makefile Compliance Report
==============================
Project Type: python (detected)
Makefile: Found

Target Status:
  help    ✅ PASS
  test    ✅ PASS (uv run pytest)
  build   ✅ PASS (docker build)
  clean   ✅ PASS
  lint    ✅ PASS (uv run ruff check)
  format  ✅ PASS (uv run ruff format)
  start   ❌ FAIL (missing)
  stop    ❌ FAIL (missing)

Makefile Checks:
  Default goal        ✅ PASS (.DEFAULT_GOAL := help)
  PHONY declarations  ✅ PASS
  Colored output      ✅ PASS
  Help target         ✅ PASS (auto-generated)

Missing Targets: start, stop
Issues: 2 found
```

### Phase 5: Configuration (If Requested)

If `--fix` flag or user confirms:

1. **Missing Makefile**: Create from FVH template based on project type
2. **Missing targets**: Add targets with appropriate commands
3. **Missing defaults**: Add `.DEFAULT_GOAL`, `.PHONY`, colors
4. **Missing help**: Add auto-generated help target

### Phase 6: Standards Tracking

Update `.fvh-standards.yaml`:

```yaml
components:
  makefile: "2025.1"
```

## FVH Makefile Template

### Universal Structure

```makefile
# Makefile for {{PROJECT_NAME}}
# Provides common commands for development, testing, and building.

# Colors for console output
BLUE := \033[0;34m
GREEN := \033[0;32m
YELLOW := \033[1;33m
RED := \033[0;31m
NC := \033[0m # No Color

.DEFAULT_GOAL := help
.PHONY: help test build clean lint format start stop

##@ Help

help: ## Display this help message
	@awk 'BEGIN {FS = ":.*##"; printf "\n$(BLUE)Usage:$(NC)\n  make $(GREEN)<target>$(NC)\n"} \
		/^[a-zA-Z_0-9-]+:.*?##/ { printf "  $(BLUE)%-15s$(NC) %s\n", $$1, $$2 } \
		/^##@/ { printf "\n$(YELLOW)%s$(NC)\n", substr($$0, 5) } ' $(MAKEFILE_LIST)
	@echo ""

##@ Development

lint: ## Run linters
	@echo "$(BLUE)Running linters...$(NC)"
{{LINT_COMMAND}}

format: ## Format code
	@echo "$(BLUE)Formatting code...$(NC)"
{{FORMAT_COMMAND}}

test: ## Run tests
	@echo "$(BLUE)Running tests...$(NC)"
{{TEST_COMMAND}}

##@ Build & Deploy

build: ## Build project
	@echo "$(BLUE)Building project...$(NC)"
{{BUILD_COMMAND}}

clean: ## Clean up temporary files and build artifacts
	@echo "$(BLUE)Cleaning up...$(NC)"
{{CLEAN_COMMAND}}

start: ## Start service
	@echo "$(BLUE)Starting service...$(NC)"
{{START_COMMAND}}

stop: ## Stop service
	@echo "$(BLUE)Stopping service...$(NC)"
{{STOP_COMMAND}}
```

### Language-Specific Commands

**Python (uv-based):**
```makefile
lint:
	@uv run ruff check .

format:
	@uv run ruff format .

test:
	@uv run pytest

build:
	@docker build -t {{PROJECT_NAME}} .

clean:
	@find . -type f -name "*.pyc" -delete
	@find . -type d -name "__pycache__" -delete
	@rm -rf .pytest_cache .ruff_cache dist/ build/
```

**Node.js:**
```makefile
lint:
	@npm run lint

format:
	@npm run format

test:
	@npm test

build:
	@npm run build
	@docker build -t {{PROJECT_NAME}} .

clean:
	@rm -rf node_modules/ dist/ .next/ .turbo/
```

**Rust:**
```makefile
lint:
	@cargo clippy -- -D warnings

format:
	@cargo fmt

test:
	@cargo nextest run

build:
	@cargo build --release
	@docker build -t {{PROJECT_NAME}} .

clean:
	@cargo clean
```

**Go:**
```makefile
lint:
	@golangci-lint run

format:
	@gofmt -s -w .

test:
	@go test ./...

build:
	@go build -o bin/{{PROJECT_NAME}}
	@docker build -t {{PROJECT_NAME}} .

clean:
	@rm -rf bin/ dist/
	@go clean
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

## Flags

| Flag | Description |
|------|-------------|
| `--check-only` | Report status without offering fixes |
| `--fix` | Apply fixes automatically |

## Examples

```bash
# Check current Makefile compliance
/configure:makefile --check-only

# Create/update Makefile for Python project
/configure:makefile --fix

# Check compliance and prompt for fixes
/configure:makefile
```

## See Also

- `/configure:all` - Run all FVH compliance checks
- `/configure:workflows` - GitHub Actions workflows
- `/configure:dockerfile` - Docker configuration
