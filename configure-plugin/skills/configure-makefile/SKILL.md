---
model: haiku
created: 2025-12-16
modified: 2026-02-10
reviewed: 2025-12-16
description: Check and configure Makefile with standard targets for project standards
allowed-tools: Glob, Grep, Read, Write, Edit, AskUserQuestion, TodoWrite
argument-hint: "[--check-only] [--fix]"
name: configure-makefile
---

# /configure:makefile

Check and configure project Makefile against project standards.

## When to Use This Skill

| Use this skill when... | Use another approach when... |
|------------------------|------------------------------|
| Setting up a new Makefile for a project that requires Make | Project can use Just instead — use `/configure:justfile` (preferred) |
| Auditing existing Makefile for missing standard targets | Writing complex build rules with dependencies — consult GNU Make documentation |
| Ensuring Makefile follows team conventions (help target, PHONY, colors) | Project uses a language-native build system (cargo, go build) exclusively |
| Running CI/CD compliance checks on Makefile structure | Migrating from Makefile to Justfile — use `/configure:justfile` which handles migration |
| Adding language-specific build/test/lint targets to existing Makefile | Debugging a specific Make target — run `make -n <target>` directly |

## Context

- Project root: !`pwd`
- Makefile exists: !`find . -maxdepth 1 -name 'Makefile' 2>/dev/null`
- Makefile targets: !`grep -E '^[a-zA-Z_-]+:' Makefile 2>/dev/null`
- Package files: !`find . -maxdepth 1 \( -name 'package.json' -o -name 'pyproject.toml' -o -name 'Cargo.toml' -o -name 'go.mod' \) 2>/dev/null`
- Docker files: !`find . -maxdepth 1 \( -name 'Dockerfile' -o -name 'docker-compose.yml' -o -name 'compose.yml' \) 2>/dev/null`
- Server files: !`find src -maxdepth 1 \( -name 'server.*' -o -name 'main.*' \) 2>/dev/null`

## Parameters

Parse from `$ARGUMENTS`:

- `--check-only`: Report Makefile compliance status without modifications
- `--fix`: Apply fixes automatically without prompting

**Required Makefile targets**: `help`, `test`, `build`, `clean`, `lint`

## Execution

Execute this Makefile compliance check:

### Step 1: Detect project type

Read the context values and determine project type (in order):

1. **Python**: `pyproject.toml` or `requirements.txt` present
2. **Node**: `package.json` present
3. **Rust**: `Cargo.toml` present
4. **Go**: `go.mod` present
5. **Generic**: None of the above

Check for service indicators (start/stop needed):
- Has `docker-compose.yml` or `compose.yml` -> Docker Compose service
- Has `Dockerfile` + HTTP server code -> Container service
- Has `src/server.*` or `src/main.*` -> Application service

### Step 2: Analyze existing Makefile targets

If Makefile exists, check against required targets:

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

### Step 3: Run compliance checks

| Check | Standard | Severity |
|-------|----------|----------|
| File exists | Makefile present | FAIL if missing |
| Default goal | `.DEFAULT_GOAL := help` | WARN if missing |
| PHONY declarations | All targets marked `.PHONY` | WARN if missing |
| Colored output | Color variables defined | INFO |
| Help target | Auto-generated from comments | WARN if missing |
| Language-specific | Commands match project type | FAIL if mismatched |

### Step 4: Generate compliance report

Print a report showing:
- Project type (detected)
- Each target with PASS/FAIL status and the command used
- Makefile structural checks (default goal, PHONY, colors, help)
- Missing targets list
- Issue count

If `--check-only` is set, stop here.

### Step 5: Create or update Makefile (if --fix or user confirms)

1. **Missing Makefile**: Create from standard template using the detected project type
2. **Missing targets**: Add targets with appropriate language-specific commands
3. **Missing defaults**: Add `.DEFAULT_GOAL`, `.PHONY`, color variables
4. **Missing help**: Add auto-generated help target using awk comment parsing

Use the language-specific commands below:

**Python (uv-based):**
- `lint`: `@uv run ruff check .`
- `format`: `@uv run ruff format .`
- `test`: `@uv run pytest`
- `build`: `@docker build -t {{PROJECT_NAME}} .`
- `clean`: `@find . -type f -name "*.pyc" -delete` + remove cache dirs

**Node.js:**
- `lint`: `@npm run lint`
- `format`: `@npm run format`
- `test`: `@npm test`
- `build`: `@npm run build`
- `clean`: `@rm -rf node_modules/ dist/ .next/ .turbo/`

**Rust:**
- `lint`: `@cargo clippy -- -D warnings`
- `format`: `@cargo fmt`
- `test`: `@cargo nextest run`
- `build`: `@cargo build --release`
- `clean`: `@cargo clean`

**Go:**
- `lint`: `@golangci-lint run`
- `format`: `@gofmt -s -w .`
- `test`: `@go test ./...`
- `build`: `@go build -o bin/{{PROJECT_NAME}}`
- `clean`: `@rm -rf bin/ dist/` + `@go clean`

### Step 6: Update standards tracking

Update `.project-standards.yaml`:

```yaml
components:
  makefile: "2025.1"
```

### Step 7: Print final report

Print a summary of changes applied, targets added, and suggest running `make help` to verify.

For the universal Makefile template structure, see [REFERENCE.md](REFERENCE.md).

## Agentic Optimizations

| Context | Command |
|---------|---------|
| Quick compliance check | `/configure:makefile --check-only` |
| Auto-fix all issues | `/configure:makefile --fix` |
| List existing targets | `grep -E '^[a-zA-Z_-]+:' Makefile` |
| Dry-run a target | `make -n <target>` |
| Show default goal | `make -p \| grep '.DEFAULT_GOAL'` |

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

- `/configure:all` - Run all compliance checks
- `/configure:workflows` - GitHub Actions workflows
- `/configure:dockerfile` - Docker configuration
