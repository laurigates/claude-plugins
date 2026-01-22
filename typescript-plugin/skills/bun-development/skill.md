---
model: haiku
name: Bun Development
description: Bun runtime for running scripts, testing, building, and project initialization - optimized flags for fast feedback and minimal output.
allowed-tools: Bash, BashOutput, Read, Write, Edit, Grep, Glob, TodoWrite
created: 2025-12-20
modified: 2025-12-20
reviewed: 2025-12-20
---

# Bun Development

## Core Expertise

Bun is an all-in-one JavaScript runtime:
- ~6ms startup vs npm's ~170ms
- Native TypeScript execution
- Built-in test runner
- Fast bundler with compile-to-exe

## Running Scripts

### Basic Execution

```bash
# Run package.json script
bun run <script>

# Run file directly
bun <file.ts>

# Silent mode (no script echo)
bun run --silent <script>
```

### Watch Mode

```bash
# Auto-restart on changes
bun --watch run dev

# Hot reload (preserve state)
bun --hot run dev
```

### Workspace Scripts

```bash
# Run in matching workspaces
bun run --filter 'package-*' build

# Run in all workspaces
bun run --workspaces test

# Limit output per workspace
bun run --filter '*' --elide-lines=5 build
```

### Execute Packages (bunx)

```bash
# Execute package binary (like npx)
bunx <package>

# Specific version
bunx typescript@5.0 --help

# When binary differs from package
bunx -p @angular/cli ng new app

# Force Bun runtime
bunx --bun vite dev
```

## Testing

### Basic Test Execution

```bash
# Run all tests
bun test

# Run specific file
bun test tests/auth.test.ts

# Filter by name
bun test -t "login"
```

### Compact Output (Agentic)

```bash
# Minimal dots reporter
bun test --dots

# Fail fast
bun test --bail
bun test --bail=3  # Stop after 3 failures

# Combine for quick feedback
bun test --dots --bail=1
```

### CI/CD Output

```bash
# JUnit XML (most CI systems)
bun test --reporter=junit --reporter-outfile=junit.xml

# GitHub Actions (auto-detected in CI)
# Produces annotations automatically
bun test
```

### Coverage

```bash
# Enable coverage
bun test --coverage

# LCOV format for tools
bun test --coverage --coverage-reporter=lcov
```

### Test Configuration

```bash
# Custom timeout
bun test --timeout=10000

# Run concurrently
bun test --concurrent

# Limit concurrency
bun test --max-concurrency=5

# Detect flaky tests
bun test --rerun-each=3
```

## Building

### Bundle JavaScript/TypeScript

```bash
# Basic bundle
bun build ./src/index.ts --outdir=dist

# Production build
bun build ./src/index.ts --outdir=dist --minify --sourcemap=external

# Watch mode
bun build ./src/index.ts --outdir=dist --watch
```

### Build Targets

```bash
# Browser (default)
bun build ./src/index.ts --target=browser

# Bun runtime
bun build ./src/index.ts --target=bun

# Node.js
bun build ./src/index.ts --target=node
```

### Compile to Executable

```bash
# Standalone binary
bun build --compile ./app.ts --outfile myapp

# Minified standalone
bun build --compile --minify ./app.ts --outfile myapp

# Cross-compile
bun build --compile --target=bun-linux-x64 ./app.ts
```

### Code Splitting

```bash
# Enable splitting
bun build ./src/index.ts --outdir=dist --splitting
```

## Project Initialization

### Quick Init

```bash
# Interactive blank project
bun init

# With template
bun init --react my-app
bun init --react=tailwind my-app
```

### Create from Template

```bash
# From npm/GitHub
bun create vite my-project
bun create hono@latest my-api

# From GitHub repo
bun create <user>/<repo> destination
```

## Agentic Optimizations

| Context | Command |
|---------|---------|
| Quick test | `bun test --dots --bail=1` |
| CI test | `bun test --reporter=junit --reporter-outfile=junit.xml` |
| Coverage | `bun test --coverage --coverage-reporter=lcov` |
| Silent run | `bun run --silent <script>` |
| Watch dev | `bun --watch run dev` |
| Prod build | `bun build --minify --sourcemap=external --outdir=dist` |
| Compile | `bun build --compile --minify ./app.ts` |
| Memory save | `bun run --smol <script>` |

## Quick Reference

### bun run

| Flag | Description |
|------|-------------|
| `--watch` | Auto-restart on changes |
| `--hot` | Hot reload |
| `--silent` | Suppress script echo |
| `--filter` | Run in matching workspaces |
| `--smol` | Reduce memory usage |

### bun test

| Flag | Description |
|------|-------------|
| `--dots` | Compact dot reporter |
| `--bail` / `--bail=N` | Stop after N failures |
| `--coverage` | Enable coverage |
| `--timeout=<ms>` | Per-test timeout |
| `--reporter=junit` | JUnit XML output |
| `-t <pattern>` | Filter by test name |
| `--concurrent` | Parallel async tests |

### bun build

| Flag | Description |
|------|-------------|
| `--outdir` | Output directory |
| `--outfile` | Output file (single/compile) |
| `--minify` | Minify output |
| `--sourcemap` | none/inline/external |
| `--target` | browser/bun/node |
| `--compile` | Standalone executable |
| `--splitting` | Enable code splitting |
| `--watch` | Watch mode |

## Environment Variables

| Variable | Description |
|----------|-------------|
| `BUN_OPTIONS` | Global CLI flags |
| `NODE_ENV` | Environment (production/development) |
