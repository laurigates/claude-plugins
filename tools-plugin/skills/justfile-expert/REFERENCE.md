# Justfile Expert - Detailed Reference

## Complete Syntax Reference

### Settings

```just
# Load .env file automatically
set dotenv-load

# Load specific .env filename (searches in working dir and parents)
set dotenv-filename := ".env.local"

# Load .env from specific path (absolute or relative to working dir)
# Takes precedence over dotenv-filename; can override with -E flag
set dotenv-path := "config/.env"

# Override existing env vars with .env values (default: false)
set dotenv-override

# Required .env file (fail if missing, default: false)
set dotenv-required

# Export all variables as environment variables
set export

# Enable $1, $2 positional argument syntax
set positional-arguments

# Suppress command echoing globally
set quiet

# Set custom shell
set shell := ["bash", "-euo", "pipefail", "-c"]

# Windows-specific shell
set windows-shell := ["powershell.exe", "-NoLogo", "-Command"]

# Allow duplicate recipe names (last wins)
set allow-duplicate-recipes

# Allow duplicate variables (last wins)
set allow-duplicate-variables

# Fail on first error in recipe
set fallback

# Use working directory for imports
set working-directory := "subdir"
```

### Attributes

```just
# Hide recipe from --list
[private]
_helper:
    echo "Internal use only"

# Don't change to justfile directory
[no-cd]
anywhere:
    pwd

# Suppress exit code message
[no-exit-message]
may-fail:
    exit 1

# Unix-only recipe
[unix]
open:
    xdg-open .

# Windows-only recipe
[windows]
open:
    start .

# macOS-only recipe
[macos]
open:
    open .

# Linux-only recipe
[linux]
open:
    xdg-open .

# Enable positional arguments for this recipe
[positional-arguments]
run:
    echo $1 $2

# Confirm before running
[confirm]
dangerous:
    rm -rf ./data

# Custom confirmation message
[confirm("Are you sure you want to deploy?")]
deploy:
    ./deploy.sh

# Run in specific directory
[working-directory: "frontend"]
build-ui:
    npm run build

# Group recipes in --list output
[group: "database"]
db-migrate:
    alembic upgrade head
```

### Built-in Functions

```just
# Architecture detection
arch := arch()                    # "x86_64", "aarch64", etc.

# OS detection
os := os()                        # "linux", "macos", "windows"
os_family := os_family()          # "unix", "windows"

# Environment variables
home := env('HOME')               # Get or fail
port := env('PORT', '8080')       # Get with default

# Path operations
parent := parent_directory('a/b') # "a"
stem := file_stem('foo.txt')      # "foo"
name := file_name('a/b/foo.txt')  # "foo.txt"
ext := extension('foo.tar.gz')    # "gz"
base := without_extension('f.txt') # "f"

# Directory functions
home_dir := home_directory()      # User's home
cache := cache_directory()        # Cache dir
config := config_directory()      # Config dir
data := data_directory()          # Data dir

# String operations
upper := uppercase('hello')              # "HELLO"
lower := lowercase('HELLO')              # "hello"
trim := trim('  hi  ')                   # "hi"
trim_start := trim_start('  hi  ')       # "hi  "
trim_end := trim_end('  hi  ')           # "  hi"
replace := replace('ab', 'a', 'x')       # "xb"
replace_re := replace_regex('a1b2', '\d', 'X')  # "aXbX"

# Case conversion
snake := snakecase('fooBar')             # "foo_bar"
kebab := kebabcase('fooBar')             # "foo-bar"
title := titlecase('hello world')        # "Hello World"

# String building
prefixed := prepend('prefix_', 'name')   # "prefix_name"
suffixed := append('name', '_suffix')    # "name_suffix"
quoted := quote("it's")                  # "'it'\"'\"'s'" (shell-safe)

# Path joining
full := join('a', 'b', 'c')       # "a/b/c"
clean := clean('a//b/../c')       # "a/c"

# Conditionals
val := if os() == "linux" { "apt" } else { "brew" }

# UUID generation
id := uuid()                      # Random UUID

# SHA256 hash
hash := sha256('content')
hash_file := sha256_file('path')

# Blake3 hash (faster alternative)
b3_hash := blake3('content')
b3_file := blake3_file('path')

# Justfile location
just_dir := justfile_directory()
just_path := justfile()

# External command execution
output := shell('echo hello')           # Execute and capture output
output := shell('echo', 'hello')        # With separate args

# Executable discovery
bin_path := which('python3')            # Find in PATH, empty if not found
required_bin := require('python3')      # Find in PATH, error if missing

# File operations
exists := path_exists('config.json')    # Boolean check
contents := read('VERSION')             # Read file contents

# System info
cpus := num_cpus()                      # Number of CPUs

# Error handling
error('message')                        # Abort with error message

# Datetime
now := datetime('%Y-%m-%d')             # Current date/time formatted

# Semantic version matching
matches := semver_matches('1.2.3', '>=1.0.0')

# Random selection
pick := choose('a', 'b', 'c')           # Random item from list
```

### Parameter Patterns

```just
# Required parameter
build target:
    cargo build --package {{target}}

# Parameter with default
test mode="debug":
    cargo test --profile {{mode}}

# Multiple parameters
deploy env tag:
    kubectl set image deployment/app app={{tag}} -n {{env}}

# Variadic + (one or more)
backup +files:
    tar -czf backup.tar.gz {{files}}

# Variadic * (zero or more)
test *args:
    cargo test {{args}}

# Default for variadic
lint *flags="-q":
    ruff check {{flags}} .

# Export as environment variable
run $PORT="8080":
    ./server --port $PORT

# Positional arguments (with attribute)
[positional-arguments]
exec *args:
    "$@"
```

## Advanced Patterns

### Shebang Recipes

Recipes starting with `#!` execute as scripts, saved to a temp file and run with the specified interpreter.

**Platform Behavior:**
- **Unix/macOS**: OS handles shebang natively
- **Windows**: Just manually parses the shebang and invokes the interpreter (no native shebang support)

**Using `-S` flag for arguments:**
```just
# When interpreter needs arguments, use -S to split them
process:
    #!/usr/bin/env -S python3 -u
    import sys
    print("Unbuffered output", flush=True)

strict-bash:
    #!/usr/bin/env -S bash -euo pipefail
    echo "Running with strict mode"
```

```just
# Python script
analyze:
    #!/usr/bin/env python3
    import json
    import sys

    with open('data.json') as f:
        data = json.load(f)
    print(f"Found {len(data)} items")

# Bash with strict mode
setup:
    #!/usr/bin/env bash
    set -euo pipefail

    echo "Installing dependencies..."
    pip install -r requirements.txt

    echo "Running migrations..."
    python manage.py migrate

    echo "Done!"

# Ruby script
generate:
    #!/usr/bin/env ruby
    require 'erb'

    template = ERB.new(File.read('template.erb'))
    puts template.result(binding)

# Node.js script
process:
    #!/usr/bin/env node
    const fs = require('fs');
    const data = JSON.parse(fs.readFileSync('config.json'));
    console.log(`Processing ${data.name}...`);
```

### Dependency Chains

```just
# Simple dependency
deploy: build test
    ./deploy.sh

# Dependency with arguments
release version: (build version) (tag version)
    echo "Released {{version}}"

build version:
    cargo build --release

tag version:
    git tag -a "v{{version}}" -m "Release {{version}}"

# Conditional dependency execution
ci:
    just lint
    just test
    just build
```

### Recipe Aliases

```just
# Simple alias
alias t := test
alias b := build

# Alias to module recipe
mod backend

alias api := backend::serve
```

### Dynamic Recipes

```just
# Recipe selection based on OS
install-deps:
    just _install-deps-{{os()}}

[private]
_install-deps-linux:
    sudo apt install build-essential

[private]
_install-deps-macos:
    brew install gcc

[private]
_install-deps-windows:
    choco install mingw
```

## Module System

### Basic Modules

```just
# justfile
mod database
mod frontend 'ui/justfile'

# Invoke: just database::migrate
# Or:     just database migrate
```

```just
# database.just (or database/mod.just)
migrate:
    alembic upgrade head

seed:
    python seed.py
```

### Module Organization

```
project/
├── justfile              # Main justfile
├── database.just         # Database module
├── frontend/
│   └── mod.just          # Frontend module
└── backend/
    ├── mod.just          # Backend module
    └── api.just          # Nested submodule
```

```just
# justfile
mod database
mod frontend 'frontend/mod.just'
mod backend 'backend/mod.just'

# Default shows all modules
default:
    @just --list
    @echo ""
    @echo "Modules: database, frontend, backend"
```

### Private Modules

```just
# Module with private recipes
mod _internal  # Hidden from --list

# Or mark recipes private within module
[private]
helper:
    echo "Internal"
```

## Integration Examples

### Docker Compose Integration

```just
set dotenv-load

project := env('COMPOSE_PROJECT_NAME', 'myapp')

# Start all services
up *args:
    docker compose up -d {{args}}

# Stop all services
down:
    docker compose down

# View logs
logs *services:
    docker compose logs -f {{services}}

# Execute command in container
exec service *cmd:
    docker compose exec {{service}} {{cmd}}

# Rebuild and restart
rebuild service:
    docker compose build {{service}}
    docker compose up -d {{service}}

# Full reset
reset:
    docker compose down -v
    docker compose build
    docker compose up -d
```

### GitHub Actions CI

```yaml
# .github/workflows/ci.yml
name: CI
on: [push, pull_request]
jobs:
  ci:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: extractions/setup-just@v2
      - run: just ci
```

```just
# justfile
ci: lint test build
    @echo "CI passed!"

lint:
    ruff check .
    ruff format --check .

test:
    pytest --cov

build:
    docker build -t app .
```

### Pre-commit Hook Integration

```yaml
# .pre-commit-config.yaml
repos:
  - repo: local
    hooks:
      - id: just-lint
        name: Lint with just
        entry: just lint
        language: system
        pass_filenames: false
```

### IDE Configuration (VS Code)

```json
// .vscode/tasks.json
{
  "version": "2.0.0",
  "tasks": [
    {
      "label": "just: test",
      "type": "shell",
      "command": "just test",
      "group": "test",
      "problemMatcher": []
    },
    {
      "label": "just: build",
      "type": "shell",
      "command": "just build",
      "group": "build",
      "problemMatcher": []
    }
  ]
}
```

## Language-Specific Templates

### Python (uv)

```just
set dotenv-load

# Run linters
lint:
    uv run ruff check .
    uv run ruff format --check .

# Format code
format:
    uv run ruff format .
    uv run ruff check --fix .

# Run tests
test *args:
    uv run pytest {{args}}

# Run tests with coverage
test-cov:
    uv run pytest --cov --cov-report=html

# Type checking
typecheck:
    uv run pyright

# Build package
build:
    uv build

# Development server
dev:
    uv run uvicorn app:app --reload

# Clean artifacts
clean:
    find . -type f -name "*.pyc" -delete
    find . -type d -name "__pycache__" -exec rm -rf {} + 2>/dev/null || true
    rm -rf .pytest_cache .ruff_cache .coverage htmlcov dist build *.egg-info
```

### Node.js (Bun)

```just
set dotenv-load

# Run linters
lint:
    bun run lint

# Format code
format:
    bun run format

# Run tests
test *args:
    bun test {{args}}

# Development server
dev:
    bun run dev

# Build for production
build:
    bun run build

# Clean artifacts
clean:
    rm -rf node_modules dist .next .turbo .cache

# Install dependencies
install:
    bun install
```

### Rust

```just
# Run linters
lint:
    cargo clippy -- -D warnings

# Format code
format:
    cargo fmt

# Run tests
test *args:
    cargo nextest run {{args}}

# Build release
build:
    cargo build --release

# Run with arguments
run *args:
    cargo run -- {{args}}

# Clean artifacts
clean:
    cargo clean

# Check without building
check:
    cargo check

# Documentation
doc:
    cargo doc --open
```

### Go

```just
# Run linters
lint:
    golangci-lint run

# Format code
format:
    gofmt -s -w .
    goimports -w .

# Run tests
test *args:
    go test ./... {{args}}

# Build binary
build:
    go build -o bin/app ./cmd/app

# Run application
run *args:
    go run ./cmd/app {{args}}

# Clean artifacts
clean:
    rm -rf bin dist
    go clean -cache

# Update dependencies
deps:
    go mod tidy
    go mod download
```

## Troubleshooting

### Common Errors and Solutions

**"Recipe requires at least one argument"**
```just
# Wrong - missing argument
just test

# Fix - provide required argument or add default
test target="all":
    pytest {{target}}
```

**"Unknown recipe"**
```bash
# Check available recipes
just --list

# Check for typos in recipe name
just --list | grep "partial-name"
```

**"No justfile found"**
```bash
# Justfile must be named: justfile, Justfile, .justfile
# Or specify explicitly
just --justfile path/to/justfile recipe
```

**"Recipe line failed"**
```just
# Each line runs in separate shell
wrong:
    cd subdir
    pwd  # Still in original directory!

# Fix - use single line or shebang
right:
    cd subdir && pwd

right-alt:
    #!/usr/bin/env bash
    cd subdir
    pwd
```

**"Variable not found"**
```just
# Wrong - undefined variable
foo:
    echo {{undefined}}

# Fix - define or use default
var := env('VAR', 'default')
foo:
    echo {{var}}
```

### Debugging Recipes

```bash
# Show recipe without running
just --dry-run recipe

# Show all variables
just --evaluate

# Show parsed justfile
just --dump

# Verbose execution
just --verbose recipe

# Show justfile search path
just --list --justfile
```

### Cross-Platform Gotchas

```just
# Problem: Different path separators
# Solution: Use / always (just handles it)

# Problem: Different line endings
# Solution: Add to .gitattributes
# justfile text eol=lf

# Problem: Different shells
# Solution: Explicit shell setting
set shell := ["bash", "-euo", "pipefail", "-c"]

# Or use shebang for complex recipes
complex:
    #!/usr/bin/env bash
    set -euo pipefail
    # Script content
```

### Performance Tips

1. **Use `@` prefix** to suppress command echo (faster output)
2. **Avoid unnecessary dependencies** - only depend on what's needed
3. **Use shebang recipes** for multi-command operations (single process)
4. **Cache expensive operations** - use variables for repeated values
5. **Parallelize independent work** - run tasks concurrently with `&`

```just
# Parallel execution
all: (build "frontend") (build "backend")
    wait

build target:
    cd {{target}} && npm run build &
```

## Quick Reference

| Command | Description |
|---------|-------------|
| `just` | Run default recipe |
| `just recipe` | Run specific recipe |
| `just --list` | List available recipes |
| `just --dry-run recipe` | Show without running |
| `just --evaluate` | Show all variables |
| `just --dump` | Show parsed justfile |
| `just --choose` | Interactive recipe selection |
| `just --completions bash` | Generate shell completions |
| `just mod::recipe` | Run recipe in module |
