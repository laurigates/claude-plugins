# Makefile Configuration Reference

Universal Makefile template and language-specific command patterns.

## Universal Makefile Template

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

## Language-Specific Templates

### Python (uv-based)

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

### Node.js

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

### Rust

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

### Go

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

## Compliance Report Template

```
Makefile Compliance Report
==============================
Project Type: [detected type]
Makefile: [Found | Missing]

Target Status:
  help    [PASS | FAIL (missing)]
  test    [PASS | FAIL (missing)]
  build   [PASS | FAIL (missing)]
  clean   [PASS | FAIL (missing)]
  lint    [PASS | FAIL (missing)]
  format  [PASS | FAIL (missing)]
  start   [PASS | FAIL (missing) | N/A]
  stop    [PASS | FAIL (missing) | N/A]

Makefile Checks:
  Default goal        [PASS (.DEFAULT_GOAL := help) | FAIL]
  PHONY declarations  [PASS | FAIL]
  Colored output      [PASS | FAIL]
  Help target         [PASS (auto-generated) | FAIL]

Missing Targets: [list]
Issues: [count] found
```
