---
allowed-tools: Write, Bash(mkdir:*), Bash(git init:*), Bash(gh repo create:*), Bash(pwd:*), Bash(git config:*), Bash(which:*), SlashCommand, TodoWrite
argument-hint: <project-name> [project-type] [--github] [--private]
description: Base project initialization that other commands can extend for language-specific setup
---

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
      - uses: actions/checkout@v4
      - name: Run linters
        run: echo "Linting step - configure based on project type"

  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
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

Based on project type, delegate to specialized setup:

{{ if $2 == "python" }}
Use SlashCommand: `/setup:new-project python`
{{ elif $2 == "node" }}
Use SlashCommand: `/setup:new-project node`
{{ elif $2 == "rust" }}
Use SlashCommand: `/setup:new-project rust`
{{ elif $2 == "go" }}
Use SlashCommand: `/setup:new-project go`
{{ else }}
# Generic project - base structure only
{{ endif }}

## GitHub Repository Creation

{{ if $3 == "--github" }}
Create GitHub repository:
```bash
gh repo create $1 ${4:+--private} --public --clone
git remote add origin https://github.com/$(gh api user -q .login)/$1.git
```
{{ endif }}

## Final Steps

1. Initialize git hooks: `pre-commit install`
2. Make initial commit: Use SlashCommand: `/git:smartcommit "Initial project structure"`
3. Set up CI/CD: Configure based on project type
4. Install dependencies: Use SlashCommand: `/deps:install`

## Next Steps Suggestions

Suggest relevant commands based on project type:
- `/test:setup` - Set up testing infrastructure
- `/docs:docs` - Generate documentation
- `/lint:check` - Verify code quality
- `/github:quickpr` - Create first PR
