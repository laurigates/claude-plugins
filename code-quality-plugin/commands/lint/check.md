---
allowed-tools: Bash(ruff:*), Bash(eslint:*), Bash(rustfmt:*), Bash(gofmt:*), Bash(prettier:*), Read, SlashCommand
argument-hint: [path] [--fix] [--format]
description: Universal linter that automatically detects and runs the appropriate linting tools
---

## Context

- Package files: !`find . -maxdepth 1 \( -name "package.json" -o -name "pyproject.toml" -o -name "setup.py" -o -name "Cargo.toml" -o -name "go.mod" \) -type f`
- Pre-commit config: !`find . -maxdepth 1 -name ".pre-commit-config.yaml" -type f`

## Parameters

- `$1`: Path to lint (defaults to current directory)
- `$2`: --fix flag to automatically fix issues
- `$3`: --format flag to also run formatters

## Linting Execution

### Python
{{ if PROJECT_TYPE == "python" }}
Run Python linters:
1. Ruff check: `uv run ruff check ${1:-.} ${2:+--fix}`
2. Type checking: `uv run mypy ${1:-.}`
3. Format check: `uv run ruff format ${1:-.} ${3:+--check}`
4. Security: `uv run bandit -r ${1:-.}`
{{ endif }}

### JavaScript/TypeScript
{{ if PROJECT_TYPE == "node" }}
Run JavaScript/TypeScript linters:
1. ESLint: `npm run lint ${1:-.} ${2:+-- --fix}`
2. Prettier: `npx prettier ${3:+--write} ${3:---check} ${1:-.}`
3. TypeScript: `npx tsc --noEmit`
{{ endif }}

### Rust
{{ if PROJECT_TYPE == "rust" }}
Run Rust linters:
1. Clippy: `cargo clippy -- -D warnings`
2. Format: `cargo fmt ${3:+} ${3:--- --check}`
3. Check: `cargo check`
{{ endif }}

### Go
{{ if PROJECT_TYPE == "go" }}
Run Go linters:
1. Go fmt: `gofmt ${3:+-w} ${3:+-l} ${1:-.}`
2. Go vet: `go vet ./...`
3. Staticcheck: `staticcheck ./...` (if available)
{{ endif }}

## Pre-commit Integration

If pre-commit is configured:
```bash
pre-commit run --all-files ${2:+--show-diff-on-failure}
```

## Multi-Language Projects

For projects with multiple languages:
1. Detect all language files
2. Run appropriate linters for each language
3. Aggregate results

## Fallback Strategy

If no specific linters found:
1. Check for Makefile: `make lint`
2. Check for npm scripts: `npm run lint`
3. Suggest installing appropriate linters via `/deps:install --dev`

## Post-lint Actions

After linting:
1. Summary of issues found/fixed
2. If unfixable issues exist, suggest `/refactor` command
3. If all clean, ready for `/git:smartcommit`
