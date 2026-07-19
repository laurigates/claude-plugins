---
created: 2025-12-16
modified: 2026-06-05
reviewed: 2026-06-05
allowed-tools: Write, Bash(mkdir *), Bash(git init *), Bash(gh repo create *), Bash(pwd *), Bash(git config *), Bash(which *), SlashCommand, TodoWrite
args: <project-name> [project-type] [--github] [--private]
argument-hint: <project-name> [project-type] [--github] [--private]
disable-model-invocation: true
description: Scaffold a new project with base structure (git, README, LICENSE, CI, pre-commit). Use when starting a new project, initializing a repo, or bootstrapping Python/Node/Rust/Go.
name: project-init
---

# /project:init

## When to Use This Skill

| Use this skill when... | Use project-discovery instead when... |
|---|---|
| Scaffolding a brand-new project from scratch (src/tests/docs, README, CI) | Working in an existing repo that already has structure |
| Bootstrapping a Python/Node/Rust/Go codebase with universal base layout | Use project-continue instead when picking up work in an established project |
| Creating a matching GitHub repository alongside the local skeleton | Use project-distill instead when extracting patterns from existing work |

## Context

- Current directory: !`pwd`
- Git user: !`git config user.name`
- GitHub CLI: !`which gh`

## Parameters

- `$1`: Project name (required)
- `$2`: Project type (python|node|rust|go|generic) - defaults to generic
- `$3`: --github flag to create GitHub repository
- `$4`: --private flag for private repository

## Base Project Structure

Create universal project structure that all projects need:

### 1. Core Directories
```bash
mkdir -p $1/{src,tests,docs,.github/workflows}
cd $1
```

### 2. Git Setup
```bash
git init
```

### 3. Base Documentation

**README.md:**
```markdown
# $1

## Description
[Project description]

## Installation
See [Installation Guide](docs/installation.md)

## Usage
See [Usage Guide](docs/usage.md)

## Development
See [Development Guide](docs/development.md)

## License
MIT
```

**LICENSE:**
Create standard MIT license file

**.gitignore:**
Create with common patterns for all languages

### 4. EditorConfig
**.editorconfig:**
```ini
root = true

[*]
indent_style = space
indent_size = 2
end_of_line = lf
charset = utf-8
trim_trailing_whitespace = true
insert_final_newline = true

[*.{py,rs,go}]
indent_size = 4

[*.md]
trim_trailing_whitespace = false
```

### 5. Pre-commit Base Config
**.pre-commit-config.yaml:**
```yaml
repos:
  - repo: https://github.com/pre-commit/pre-commit-hooks
    rev: v4.6.0
    hooks:
      - id: trailing-whitespace
      - id: end-of-file-fixer
      - id: check-yaml
      - id: check-json
      - id: check-merge-conflict
      - id: detect-private-key
```

### 6. GitHub Actions Base

**.github/workflows/ci.yml:**
```yaml
name: CI

on:
  push:
    branches: [main, develop]
  pull_request:
    branches: [main]

jobs:
  lint:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4.3.1
      - name: Run linters
        run: echo "Linting step - configure based on project type"

  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4.3.1
      - name: Run tests
        run: echo "Testing step - configure based on project type"
```

### 7. Makefile Base

Create universal Makefile with colored output:
```makefile
.PHONY: help install test lint format clean

help:
	@echo "Available commands:"
	@echo "  make install - Install dependencies"
	@echo "  make test    - Run tests"
	@echo "  make lint    - Run linters"
	@echo "  make format  - Format code"
	@echo "  make clean   - Clean build artifacts"

install:
	@echo "Installing dependencies..."

test:
	@echo "Running tests..."

lint:
	@echo "Running linters..."

format:
	@echo "Formatting code..."

clean:
	@echo "Cleaning..."
```

## Language-Specific Setup

Base init creates the universal structure only. Language-specific tooling
(package manager, linters/formatters, test framework, Dockerfile) is applied
afterwards with the `configure-plugin` skills — see that plugin's README for the
current skill list. Do not rely on a single bootstrap command; layer the
configure skills you actually need.

## GitHub Repository Creation

{{ if $3 == "--github" }}
Create GitHub repository. `${4:---public}` expands to `--private` when `$4` is
`--private`, otherwise to `--public` — so exactly one visibility flag is passed
(never both):
```bash
gh repo create $1 "${4:---public}" --clone
git remote add origin https://github.com/$(gh api user -q .login)/$1.git
```
{{ endif }}

## Final Steps

1. Initialize git hooks: `pre-commit install`
2. Make initial commit: Use SlashCommand: `/git:commit "Initial project structure"`
3. Set up CI/CD: Configure based on project type
4. Install dependencies: Use SlashCommand: `/deps:install`

## Next Steps Suggestions

Suggest relevant commands based on project type:
- `/test:setup` - Set up testing infrastructure
- `/git:pr` - Create first PR
