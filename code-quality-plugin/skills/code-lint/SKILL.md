---
created: 2025-12-16
modified: 2026-05-04
reviewed: 2026-04-25
allowed-tools: Bash(ruff *), Bash(eslint *), Bash(rustfmt *), Bash(gofmt *), Bash(prettier *), Read, SlashCommand
model: sonnet
args: "[path] [--fix] [--format]"
argument-hint: [path] [--fix] [--format]
description: |
  Universal linter that auto-detects and runs the appropriate linting tools
  for the project's language. Use when the user asks to lint the code, run
  ruff/eslint/clippy/gofmt, auto-fix lint errors with --fix, format code,
  or run pre-commit checks across a polyglot repository.
name: code-lint
---

## When to Use This Skill

| Use this skill when... | Use something else instead when... |
|------------------------|------------------------------------|
| Auto-detecting and running the correct linter for a polyglot repo | Looking up autofix patterns and exact commands → `code-lint-fix` |
| Running ruff/eslint/clippy/gofmt with optional `--fix` and `--format` | Detecting structural anti-patterns linters miss → `code-antipatterns` |
| Driving a one-shot lint pass before commit | Reviewing broader code quality and architecture → `code-review` |
| Running language-aware lint over a path argument | Scanning specifically for swallowed errors → `code-error-swallowing` |

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
1. Ruff check: `uv run ruff check ${1:-.} --output-format=concise ${2:+--fix}`
2. Type checking: `uv run ty check ${1:-.} --hide-progress`
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
1. Clippy: `cargo clippy --message-format=short -- -D warnings`
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
4. Suggest configuring project linting standards via /configure:linting

## Post-lint Actions

After linting:
1. Summary of issues found/fixed
2. If unfixable issues exist, suggest `/code:refactor` command
3. If all clean, ready for `/git:smartcommit`
