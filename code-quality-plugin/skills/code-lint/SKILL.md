---
created: 2025-12-16
modified: 2026-05-23
reviewed: 2026-04-25
allowed-tools: Bash(ruff *), Bash(eslint *), Bash(rustfmt *), Bash(gofmt *), Bash(prettier *), Bash(bash *), Read, SlashCommand
model: sonnet
args: "[path] [--fix] [--format]"
argument-hint: "[path] [--fix] [--format]"
description: Universal linter that auto-detects ruff/eslint/clippy/gofmt for the project language. Use when linting code, auto-fixing, formatting, or running pre-commit checks.
name: code-lint
---

## When to Use This Skill

| Use this skill when... | Use something else instead when... |
|------------------------|------------------------------------|
| Auto-detecting and running the correct linter for a polyglot repo | Detecting structural anti-patterns linters miss → `code-antipatterns` |
| Running ruff/eslint/clippy/gofmt with optional `--fix` and `--format` | Reviewing broader code quality and architecture → `code-review` |
| Driving a one-shot lint pass before commit | Scanning specifically for swallowed errors → `code-error-swallowing` |
| Looking up autofix commands or common fix patterns per language | (use this skill — autofix reference is now here) |

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

## Auto-fixing

### Autofix Command Reference

| Language | Linter | Autofix Command |
|----------|--------|-----------------|
| TypeScript/JS | biome | `npx @biomejs/biome check --write .` |
| TypeScript/JS | biome format | `npx @biomejs/biome format --write .` |
| Python | ruff | `ruff check --fix .` |
| Python | ruff format | `ruff format .` |
| Rust | clippy | `cargo clippy --fix --allow-dirty` |
| Rust | rustfmt | `cargo fmt` |
| Go | gofmt | `gofmt -w .` |
| Go | go mod | `go mod tidy` |
| Shell | shellcheck | No autofix (manual only) |

### Detect-and-Fix Script

Auto-detect project linters and run all appropriate fixers in one command:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/skills/code-lint/scripts/detect-and-fix.sh"
bash "${CLAUDE_PLUGIN_ROOT}/skills/code-lint/scripts/detect-and-fix.sh" --check-only
```

Detects biome, eslint, prettier, ruff, black, clippy, rustfmt, gofmt, golangci-lint, shellcheck. Reports which linters were found and shows modified files.

### Common Fix Patterns

**JavaScript/TypeScript (Biome)**: unused imports, prefer-const (`let x = 5` → `const x = 5`).

**Python (Ruff)**: import sorting (I001), unused imports (F401), long lines auto-wrapped.

**Rust (Clippy)**: redundant clone, `match` → `if let` for single-arm patterns.

**Shell (ShellCheck — manual fixes)**: quote variables (`$var` → `"$var"`), use `$()` instead of backticks.

### When to Escalate from Autofix

Stop autofix and use a different approach when:
- Fix requires understanding business logic
- Multiple files need coordinated changes
- Warning indicates a potential bug (not just style)
- Security-related linter rule
- Type error requires interface/API changes

## Post-lint Actions

After linting:
1. Summary of issues found/fixed
2. If unfixable issues exist, suggest `/code:refactor` command
3. If all clean, ready for `/git:smartcommit`
