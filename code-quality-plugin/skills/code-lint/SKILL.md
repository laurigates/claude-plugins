---
created: 2025-12-16
modified: 2026-08-07
reviewed: 2026-08-07
allowed-tools: Bash, Read, SlashCommand
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
| Driving a one-shot lint pass before commit | Scanning specifically for swallowed errors → `code-hidden-failures --track errors` |
| Looking up autofix commands or common fix patterns per language | (use this skill — autofix reference is now here) |

## Context

- Package files: !`find . -maxdepth 1 \( -name "package.json" -o -name "pyproject.toml" -o -name "setup.py" -o -name "requirements.txt" -o -name "Cargo.toml" -o -name "go.mod" \) -type f`
- Pre-commit config: !`find . -maxdepth 1 -name ".pre-commit-config.yaml" -type f`

## Parameters

Parse `$ARGUMENTS` and bind three values before running anything. These are
supplied by the **caller**; nothing substitutes them for you.

| Token in `$ARGUMENTS` | Binds | Default when absent |
|---|---|---|
| First non-flag token | `PATH` — the file or directory to lint | `.` (repo root) |
| `--fix` | `FIX` — apply autofixes | off; check only |
| `--format` | `FORMAT` — run formatters in write mode | off; formatters run in `--check` mode |

Every command in Step 2 is written with a literal `PATH` placeholder. Substitute
the bound value when you run it — e.g. with `$ARGUMENTS` empty, `ruff check PATH`
is run as `ruff check .`.

## Execution

Run this lint pass:

### Step 0: One-shot path (preferred when no `PATH` is given)

When the caller passed no path (or passed `.`), the bundled detector already does
detection, tool discovery, and fixing in a single call:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/skills/code-lint/scripts/detect-and-fix.sh"
bash "${CLAUDE_PLUGIN_ROOT}/skills/code-lint/scripts/detect-and-fix.sh" --check-only
```

Pass `--check-only` unless `FIX` is set. It detects biome, eslint, prettier,
ruff, black, clippy, rustfmt, gofmt, golangci-lint, and shellcheck, reports which
were found, and shows modified files. Report its output and stop.

Continue to Step 1 when the caller scoped the run to a specific `PATH`, or when
the detector reports no linters found.

### Step 1: Detect the project language

Read the `Package files` line from Context above (or `ls` the target directory)
and map each marker file to a language. **The signals are the marker files — do
not guess from file extensions or the repo name.**

| Marker file present in the repo root | Language |
|---|---|
| `pyproject.toml`, `setup.py`, `requirements.txt` | Python |
| `package.json` | JavaScript / TypeScript |
| `Cargo.toml` | Rust |
| `go.mod` | Go |

- **Exactly one match** → run that row of Step 2.
- **Several matches** (polyglot repo) → run each matching row, then aggregate the
  results into one summary. Do not pick one arbitrarily.
- **No match** → skip to Step 3.

### Step 2: Run the row for each detected language

Run the **Lint** and **Format** commands for every detected language. Swap in the
`--fix` / `--format` variants only when the caller set those flags.

| Language | Lint (always) | Lint with `--fix` | Format check (default) | Format with `--format` |
|---|---|---|---|---|
| Python | `uv run ruff check PATH --output-format=concise` | `uv run ruff check PATH --output-format=concise --fix` | `uv run ruff format --check PATH` | `uv run ruff format PATH` |
| JavaScript / TypeScript | `npx eslint PATH` | `npx eslint PATH --fix` | `npx prettier --check PATH` | `npx prettier --write PATH` |
| Rust | `cargo clippy --message-format=short -- -D warnings` | `cargo clippy --fix --allow-dirty` | `cargo fmt -- --check` | `cargo fmt` |
| Go | `go vet ./...` | (no autofix — fix by hand) | `gofmt -l PATH` | `gofmt -w PATH` |

Then run each detected language's extra checks:

| Language | Extra checks |
|---|---|
| Python | `uv run ty check PATH --hide-progress`, `uv run bandit -q -r PATH` |
| JavaScript / TypeScript | `npx tsc --noEmit` |
| Rust | `cargo check` |
| Go | `staticcheck ./...` (only if installed) |

When the repo defines its own lint script (`npm run lint`, a `just lint` recipe),
prefer it over the raw command above — it encodes the project's own flags.

### Step 3: Fallback when no language was detected

In order, stopping at the first that applies:

1. `Makefile` present → `make lint`
2. `package.json` with a `lint` script → `npm run lint`
3. Otherwise report that no linters were found, and suggest `/deps:install --dev`
   and `/configure:linting`.

### Step 4: Pre-commit integration

If the `Pre-commit config` line in Context is non-empty:

| Caller flags | Command |
|---|---|
| default | `pre-commit run --all-files` |
| `--fix` | `pre-commit run --all-files --show-diff-on-failure` |

## Autofix Command Reference

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
