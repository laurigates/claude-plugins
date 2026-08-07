---
created: 2025-12-16
modified: 2026-08-07
reviewed: 2026-08-07
allowed-tools: Bash, Read, Write
model: sonnet
args: "[package-names] [--dev] [--global]"
argument-hint: "[package-names] [--dev] [--global]"
description: "Deps install: auto-detect package manager (uv, bun, npm, yarn, pnpm, cargo, go) and run the right install. Use when installing deps or syncing lockfiles."
name: deps-install
---

## When to Use This Skill

| Use this skill when... | Use justfile-expert instead when... |
|---|---|
| Installing packages without picking a manager up front | Defining a project-local `just install` recipe |
| One-off `--global` or `--dev` installs across mixed projects | Standardising `just deps` / `just sync` for a team |
| Auto-detecting between uv, bun, npm, cargo, and go | The repo already exposes installation as a recipe |

| Use this skill when... | Use shell-expert instead when... |
|---|---|
| The user just wants the install command run | Writing a custom installer script with retries or branching |
| Syncing the lockfile via the right native subcommand | Composing multi-package-manager bootstrap logic in shell |

## Context

- Package files: !`find . -maxdepth 1 \( -name "package.json" -o -name "pyproject.toml" -o -name "requirements.txt" -o -name "Cargo.toml" -o -name "go.mod" -o -name "Gemfile" \) -type f`
- Lock files: !`find . -maxdepth 1 \( -name "uv.lock" -o -name "package-lock.json" -o -name "yarn.lock" -o -name "pnpm-lock.yaml" -o -name "Cargo.lock" -o -name "go.sum" \) -type f`

## Parameters

Parse `$ARGUMENTS` and bind these before running anything. They are supplied by
the **caller**; nothing substitutes them for you.

| Token in `$ARGUMENTS` | Binds | Default when absent |
|---|---|---|
| Non-flag tokens | `PACKAGES` — space-separated package names | empty → install everything from the manifest |
| `--dev` | `DEV` — add to development dependencies | off |
| `--global` | `GLOBAL` — install globally rather than into the project | off |

Every command below is written with a literal `PACKAGES` placeholder — substitute
the bound value when you run it.

## Execution

Run this install:

### Step 1: Detect the package manager

Read the `Lock files` and `Package files` lines from Context above. **Lock files
win** — they name the manager that actually produced the current install; a
manifest alone only narrows the ecosystem.

| Signal (repo root) | PACKAGE_MANAGER |
|---|---|
| `uv.lock`, or `pyproject.toml` with a `[tool.uv]` section | `uv` |
| `bun.lock` / `bun.lockb` | `bun` |
| `pnpm-lock.yaml` | `pnpm` |
| `yarn.lock` | `yarn` |
| `package-lock.json` | `npm` |
| `Cargo.lock` / `Cargo.toml` | `cargo` |
| `go.sum` / `go.mod` | `go` |
| `pyproject.toml` / `requirements.txt` with no lock file | `uv` |
| `package.json` with no lock file | `bun` (this portfolio's default — see `bun-package-manager`) |

- **Several matches** in one repo (a polyglot monorepo) → run the matching row for
  each ecosystem, then report them together.
- **No match** → report that no manifest was found and stop; do not guess.

### Step 2: Run the row for the detected manager

| PACKAGE_MANAGER | Install all (no `PACKAGES`) | Add `PACKAGES` | With `--dev` | With `--global` |
|---|---|---|---|---|
| `uv` | `uv sync` | `uv add PACKAGES` | `uv add --dev PACKAGES` | `uv tool install PACKAGES` |
| `bun` | `bun install` | `bun add PACKAGES` | `bun add -d PACKAGES` | `bun add -g PACKAGES` |
| `npm` | `npm ci` (lock present) else `npm install` | `npm install PACKAGES` | `npm install -D PACKAGES` | `npm install -g PACKAGES` |
| `yarn` | `yarn install --frozen-lockfile` | `yarn add PACKAGES` | `yarn add -D PACKAGES` | `yarn global add PACKAGES` |
| `pnpm` | `pnpm install --frozen-lockfile` | `pnpm add PACKAGES` | `pnpm add -D PACKAGES` | `pnpm add -g PACKAGES` |
| `cargo` | `cargo build` | `cargo add PACKAGES` | `cargo add --dev PACKAGES` | `cargo install PACKAGES` |
| `go` | `go mod download` | `go get PACKAGES` | (Go has no dev-dependency tier) | `go install PACKAGES@latest` |

For Python without uv, `uv pip install -r requirements.txt` installs a legacy
requirements file without migrating the project.

## System Dependencies

Check for system-level dependencies:
- macOS: Use Homebrew if Brewfile exists
- Linux: Detect package manager (apt, yum, dnf, pacman)

## Lock File Management

After installation:
1. Verify lock file is updated
2. If new lock file created, remind to commit it
3. Check for security vulnerabilities

## Post-install Actions

1. Display installed packages and versions
2. Run `/lint:check` to ensure code quality
3. Run `/test:run` to verify nothing broke
4. Suggest `/git:smartcommit` if lock files changed
