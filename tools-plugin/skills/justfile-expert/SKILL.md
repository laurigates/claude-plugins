---
created: 2025-12-16
modified: 2025-12-16
reviewed: 2025-12-16
name: justfile-expert
description: |
  Just command runner expertise, Justfile syntax, recipe development, and cross-platform
  task automation. Covers recipe patterns, parameters, modules, settings, and workflow
  integration. Use when user mentions just, justfile, recipes, command runner, task
  automation, project commands, or needs help writing executable project documentation.
allowed-tools: Bash, BashOutput, Grep, Glob, Read, Write, Edit, TodoWrite
---

# Justfile Expert

Expert knowledge for Just command runner, recipe development, and task automation with focus on cross-platform compatibility and project standardization.

## Core Expertise

**Command Runner Mastery**
- Justfile syntax and recipe structure
- Cross-platform task automation (Linux, macOS, Windows)
- Parameter handling and argument forwarding
- Module organization for large projects

**Recipe Development Excellence**
- Recipe patterns for common operations
- Dependency management between recipes
- Shebang recipes for complex logic
- Environment variable integration

**Project Standardization**
- Standard recipes for consistent workflows
- Self-documenting project operations
- Portable patterns across projects
- Integration with CI/CD pipelines

## Key Capabilities

**Recipe Parameters**
- **Required parameters**: `recipe param:` - must be provided
- **Default values**: `recipe param="default":` - optional with fallback
- **Variadic `+`**: `recipe +FILES:` - one or more arguments
- **Variadic `*`**: `recipe *FLAGS:` - zero or more arguments
- **Environment export**: `recipe $VAR:` - parameter as env var

**Settings Configuration**
- **`set dotenv-load`**: Load `.env` file automatically
- **`set positional-arguments`**: Enable `$1`, `$2` syntax
- **`set export`**: Export all variables as env vars
- **`set shell`**: Custom shell interpreter
- **`set quiet`**: Suppress command echoing

**Recipe Attributes**
- **`[private]`**: Hide from `--list` output
- **`[no-cd]`**: Don't change directory
- **`[no-exit-message]`**: Suppress exit messages
- **`[unix]`** / **`[windows]`**: Platform-specific recipes
- **`[positional-arguments]`**: Per-recipe positional args

**Module System**
- **`mod name`**: Declare submodule
- **`mod name 'path'`**: Custom module path
- **Invocation**: `just module::recipe` or `just module recipe`

## Essential Syntax

**Basic Recipe Structure**
```just
# Comment describes the recipe
recipe-name:
    command1
    command2
```

**Recipe with Parameters**
```just
build target:
    @echo "Building {{target}}..."
    cd {{target}} && make

test *args:
    uv run pytest {{args}}
```

**Recipe Dependencies**
```just
default: build test

build: _setup
    cargo build --release

_setup:
    @echo "Setting up..."
```

**Variables and Interpolation**
```just
version := "1.0.0"
project := env('PROJECT_NAME', 'default')

info:
    @echo "Project: {{project}} v{{version}}"
```

**Conditional Recipes**
```just
[unix]
open:
    xdg-open http://localhost:8080

[windows]
open:
    start http://localhost:8080
```

## Standard Recipes

Every project should provide these standard recipes:

```just
# Justfile - Project task runner
# Run `just` or `just help` to see available recipes

set dotenv-load
set positional-arguments

# Default recipe - show help
default:
    @just --list

# Show available recipes with descriptions
help:
    @just --list --unsorted

####################
# Development
####################

# Run linters
lint:
    # Language-specific lint command

# Format code
format:
    # Language-specific format command

# Run tests
test *args:
    # Language-specific test command {{args}}

# Development mode with watch
dev:
    # Start with file watching

####################
# Build & Deploy
####################

# Build project
build:
    # Build command

# Clean build artifacts
clean:
    # Cleanup command

# Start service
start:
    # Start command

# Stop service
stop:
    # Stop command
```

## Common Patterns

**Setup/Bootstrap Recipe**
```just
# Initial project setup
setup:
    #!/usr/bin/env bash
    set -euo pipefail
    echo "Installing dependencies..."
    uv sync
    echo "Setting up pre-commit..."
    pre-commit install
    echo "Done!"
```

**Docker Integration**
```just
# Build container image
docker-build tag="latest":
    docker build -t {{project}}:{{tag}} .

# Run container
docker-run tag="latest" *args:
    docker run --rm -it {{project}}:{{tag}} {{args}}

# Push to registry
docker-push tag="latest":
    docker push {{registry}}/{{project}}:{{tag}}
```

**Database Operations**
```just
# Run database migrations
db-migrate:
    uv run alembic upgrade head

# Create new migration
db-revision message:
    uv run alembic revision --autogenerate -m "{{message}}"

# Reset database
db-reset:
    uv run alembic downgrade base
    uv run alembic upgrade head
```

**CI/CD Recipes**
```just
# Full CI check (lint + test + build)
ci: lint test build
    @echo "CI passed!"

# Release workflow
release version:
    git tag -a "v{{version}}" -m "Release {{version}}"
    git push origin "v{{version}}"
```

## Best Practices

**Recipe Development Workflow**
1. **Name clearly**: Use descriptive, verb-based names (`build`, `test`, `deploy`)
2. **Document always**: Add comment before each recipe
3. **Use defaults**: Provide sensible default parameter values
4. **Group logically**: Organize with section comments
5. **Hide internals**: Mark helper recipes as `[private]`
6. **Test portability**: Verify on all target platforms

**Critical Guidelines**
- Always provide `default` recipe pointing to help
- Use `@` prefix to suppress command echo when appropriate
- Use shebang recipes for multi-line logic
- Prefer `set dotenv-load` for configuration
- Use modules for large projects (>20 recipes)
- Include variadic `*args` for passthrough flexibility
- Quote all variables in shell commands

## Comparison with Alternatives

| Feature | Just | Make | mise tasks |
|---------|------|------|------------|
| Syntax | Simple, clear | Complex, tabs required | YAML |
| Dependencies | Built-in | Built-in | Manual |
| Parameters | Full support | Limited | Full support |
| Cross-platform | Excellent | Good | Excellent |
| Tool versions | No | No | Yes |
| Error messages | Clear | Cryptic | Clear |
| Installation | Single binary | Pre-installed | Requires mise |

**When to use Just:**
- Cross-project standard recipes
- Simple, readable task automation
- No tool version management needed

**When to use mise tasks:**
- Project-specific with tool version pinning
- Already using mise for tool management

**When to use Make:**
- Legacy projects with existing Makefiles
- Build systems requiring incremental compilation

For detailed syntax reference, advanced patterns, and troubleshooting, see REFERENCE.md.
