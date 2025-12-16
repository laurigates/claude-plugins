---
name: ruff Integration
description: Integrate ruff with editors, pre-commit hooks, and CI/CD pipelines. LSP configuration, GitHub Actions, GitLab CI, and development workflows. Use when setting up ruff tooling or configuring development environments.
allowed-tools: Bash, Read, Edit, Write, Grep, Glob
---

# ruff Integration

Expert knowledge for integrating `ruff` into development workflows, editors, and CI/CD pipelines.

## Core Expertise

**Integration Points**
- Editor integration (VS Code, Neovim, Zed, Helix)
- Pre-commit hooks
- CI/CD pipelines (GitHub Actions, GitLab CI)
- Language Server Protocol (LSP)
- Build systems and task runners

## Editor Integration

### VS Code

**Installation**
```bash
# Install extension
code --install-extension charliermarsh.ruff
```

**Configuration** (`.vscode/settings.json`)
```json
{
  // Python configuration
  "[python]": {
    "editor.formatOnSave": true,
    "editor.codeActionsOnSave": {
      "source.fixAll": "explicit",
      "source.organizeImports": "explicit"
    },
    "editor.defaultFormatter": "charliermarsh.ruff"
  },

  // Ruff-specific settings
  "ruff.lint.args": [
    "--select=E,F,B,I"
  ],
  "ruff.format.args": [
    "--line-length=100"
  ],
  "ruff.importStrategy": "fromEnvironment",
  "ruff.path": ["ruff"],

  // Custom configuration file
  "ruff.configuration": "~/path/to/ruff.toml",

  // Or inline configuration
  "ruff.configuration": {
    "lint": {
      "unfixable": ["F401"],
      "extend-select": ["TID251"]
    },
    "format": {
      "quote-style": "single"
    }
  }
}
```

**Workspace Settings**
```json
// .vscode/settings.json (project-specific)
{
  "[python]": {
    "editor.formatOnSave": true,
    "editor.defaultFormatter": "charliermarsh.ruff"
  },
  "ruff.lint.select": ["E", "F", "B", "I", "UP"],
  "ruff.lint.ignore": ["E501"]
}
```

### Neovim

**Using LSP (nvim-lspconfig)**
```lua
-- Ruff LSP setup
require('lspconfig').ruff.setup {
  init_options = {
    settings = {
      -- Linting configuration
      lint = {
        select = {"E", "F", "B", "I"},
        ignore = {"E501"}
      },
      -- Formatting configuration
      format = {
        ["quote-style"] = "single"
      },
      -- Line length
      lineLength = 88
    }
  }
}
```

**Using conform.nvim (Formatting)**
```lua
require("conform").setup({
  formatters_by_ft = {
    python = { "ruff_format" },
  },
  format_on_save = {
    timeout_ms = 500,
    lsp_fallback = true,
  },
})
```

**Using nvim-lint (Linting)**
```lua
require("lint").linters_by_ft = {
  python = { "ruff" },
}

-- Auto-lint on save
vim.api.nvim_create_autocmd({ "BufWritePost" }, {
  callback = function()
    require("lint").try_lint()
  end,
})
```

**Inline Configuration**
```lua
require('lspconfig').ruff.setup {
  init_options = {
    settings = {
      configuration = {
        lint = {
          unfixable = {"F401"},
          ["extend-select"] = {"TID251"},
          ["flake8-tidy-imports"] = {
            ["banned-api"] = {
              ["typing.TypedDict"] = {
                msg = "Use `typing_extensions.TypedDict` instead"
              }
            }
          }
        },
        format = {
          ["quote-style"] = "single"
        }
      }
    }
  }
}
```

### Zed

**Configuration** (`settings.json`)
```json
{
  "languages": {
    "Python": {
      "language_servers": ["ruff"],
      "format_on_save": "on",
      "formatter": [
        {
          "code_actions": {
            "source.organizeImports.ruff": true,
            "source.fixAll.ruff": true
          }
        },
        {
          "language_server": {
            "name": "ruff"
          }
        }
      ]
    }
  },
  "lsp": {
    "ruff": {
      "initialization_options": {
        "settings": {
          "lineLength": 80,
          "lint": {
            "extendSelect": ["I"]
          },
          "configuration": "~/path/to/ruff.toml"
        }
      }
    }
  }
}
```

### Helix

**Configuration** (`languages.toml`)
```toml
# LSP configuration
[language-server.ruff]
command = "ruff"
args = ["server"]

# Language-specific settings
[language-server.ruff.config.settings]
lineLength = 80

[language-server.ruff.config.settings.lint]
select = ["E4", "E7"]
preview = false

[language-server.ruff.config.settings.format]
preview = true

# Python language configuration
[[language]]
name = "python"
language-servers = ["ruff", "pyright"]
formatter = { command = "ruff", args = ["format", "-"] }
auto-format = true
```

### EFM Language Server

**Configuration** (`efm-langserver` config)
```yaml
tools:
  python-ruff:
    lint-command: "ruff check --stdin-filename ${INPUT} --output-format concise --quiet -"
    lint-stdin: true
    lint-formats:
      - "%f:%l:%c: %m"
    format-command: "ruff format --stdin-filename ${INPUT} --quiet -"
    format-stdin: true
```

## Pre-commit Integration

### Basic Setup
```yaml
# .pre-commit-config.yaml
repos:
  - repo: https://github.com/astral-sh/ruff-pre-commit
    rev: v0.14.0
    hooks:
      # Linter with auto-fix
      - id: ruff-check
        args: [--fix]

      # Formatter
      - id: ruff-format
```

### Advanced Configuration
```yaml
repos:
  - repo: https://github.com/astral-sh/ruff-pre-commit
    rev: v0.14.0
    hooks:
      # Advanced linting
      - id: ruff-check
        name: Ruff linter
        args:
          - --fix
          - --config=pyproject.toml
          - --select=E,F,B,I
        types_or: [python, pyi, jupyter]

      # Formatting with specific config
      - id: ruff-format
        name: Ruff formatter
        args:
          - --config=pyproject.toml
        types_or: [python, pyi]
```

### Installation
```bash
# Install pre-commit
pip install pre-commit

# Install hooks
pre-commit install

# Run manually
pre-commit run --all-files

# Run on specific files
pre-commit run --files src/main.py

# Update hooks
pre-commit autoupdate
```

### Multiple Python Versions
```yaml
repos:
  - repo: https://github.com/astral-sh/ruff-pre-commit
    rev: v0.14.0
    hooks:
      - id: ruff-check
        args: [--fix, --target-version=py39]
      - id: ruff-format
```

## CI/CD Integration

### GitHub Actions

**Basic Workflow**
```yaml
# .github/workflows/lint.yml
name: Lint

on: [push, pull_request]

jobs:
  ruff:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: astral-sh/ruff-action@v3
```

**Advanced Workflow**
```yaml
name: Code Quality

on: [push, pull_request]

jobs:
  lint:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - uses: astral-sh/ruff-action@v3
        with:
          args: 'check --output-format github'
          changed-files: 'true'

      - name: Commit fixes
        if: failure()
        run: |
          git config user.name "github-actions"
          git config user.email "github-actions@github.com"
          git add .
          git commit -m "Auto-fix linting issues"
          git push

  format:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Check formatting
        run: |
          pip install ruff
          ruff format --check
```

**With Multiple Python Versions**
```yaml
jobs:
  lint:
    strategy:
      matrix:
        python-version: ['3.9', '3.10', '3.11', '3.12']
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-python@v5
        with:
          python-version: ${{ matrix.python-version }}
      - run: pip install ruff
      - run: ruff check --target-version=py${{ matrix.python-version }}
```

**Separated Linting and Formatting**
```yaml
jobs:
  ruff-check:
    name: Lint with Ruff
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - run: pip install ruff
      - run: ruff check --output-format github

  ruff-format:
    name: Check Formatting
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - run: pip install ruff
      - run: ruff format --check --diff
```

### GitLab CI

**Basic Pipeline**
```yaml
# .gitlab-ci.yml
stages:
  - lint

ruff-check:
  stage: lint
  image: ghcr.io/astral-sh/ruff:0.14.0-alpine
  script:
    - ruff check

ruff-format:
  stage: lint
  image: ghcr.io/astral-sh/ruff:0.14.0-alpine
  script:
    - ruff format --check
```

**Advanced Pipeline**
```yaml
.base_ruff:
  stage: build
  interruptible: true
  image:
    name: ghcr.io/astral-sh/ruff:0.14.0-alpine
  before_script:
    - cd $CI_PROJECT_DIR
    - ruff --version

Ruff Check:
  extends: .base_ruff
  script:
    - ruff check --output-format=gitlab > code-quality-report.json
  artifacts:
    reports:
      codequality: $CI_PROJECT_DIR/code-quality-report.json

Ruff Format:
  extends: .base_ruff
  script:
    - ruff format --check --diff
  allow_failure: false
```

### CircleCI
```yaml
# .circleci/config.yml
version: 2.1

jobs:
  lint:
    docker:
      - image: cimg/python:3.11
    steps:
      - checkout
      - run:
          name: Install ruff
          command: pip install ruff
      - run:
          name: Run linter
          command: ruff check
      - run:
          name: Check formatting
          command: ruff format --check

workflows:
  main:
    jobs:
      - lint
```

### Jenkins
```groovy
pipeline {
    agent any

    stages {
        stage('Setup') {
            steps {
                sh 'pip install ruff'
            }
        }

        stage('Lint') {
            steps {
                sh 'ruff check --output-format json > ruff-report.json'
            }
        }

        stage('Format Check') {
            steps {
                sh 'ruff format --check'
            }
        }
    }

    post {
        always {
            archiveArtifacts artifacts: 'ruff-report.json', fingerprint: true
        }
    }
}
```

## Build System Integration

### Make
```makefile
# Makefile
.PHONY: lint format check

# Lint with ruff
lint:
	ruff check

# Format with ruff
format:
	ruff format

# Check both
check: lint
	ruff format --check

# Fix issues
fix:
	ruff check --fix
	ruff format

# CI target
ci: check
	@echo "All checks passed!"
```

### Just
```just
# justfile
# Lint Python code
lint:
    ruff check

# Format Python code
format:
    ruff format

# Check formatting
format-check:
    ruff format --check

# Fix all issues
fix:
    ruff check --fix
    ruff format

# Run all checks (CI)
ci: lint format-check
```

### Task (go-task)
```yaml
# Taskfile.yml
version: '3'

tasks:
  lint:
    desc: Lint Python code
    cmds:
      - ruff check

  format:
    desc: Format Python code
    cmds:
      - ruff format

  format-check:
    desc: Check formatting
    cmds:
      - ruff format --check

  fix:
    desc: Auto-fix issues
    cmds:
      - ruff check --fix
      - ruff format

  ci:
    desc: Run CI checks
    deps:
      - lint
      - format-check
```

### Poetry Scripts
```toml
# pyproject.toml
[tool.poetry.scripts]
lint = "ruff check"
format = "ruff format"
check = "ruff format --check && ruff check"
```

### tox
```ini
# tox.ini
[tox]
envlist = py39,py310,py311,lint

[testenv]
deps = pytest
commands = pytest

[testenv:lint]
deps = ruff
commands =
    ruff check
    ruff format --check

[testenv:format]
deps = ruff
commands = ruff format
```

## Docker Integration

### Dockerfile
```dockerfile
# Development stage with ruff
FROM python:3.11-slim as development

# Install ruff
RUN pip install --no-cache-dir ruff

# Copy source code
COPY . /app
WORKDIR /app

# Run checks
RUN ruff check && ruff format --check

# Production stage
FROM python:3.11-slim as production
# ... production setup
```

### Docker Compose
```yaml
# docker-compose.yml
version: '3.8'

services:
  lint:
    image: ghcr.io/astral-sh/ruff:0.14.0-alpine
    volumes:
      - .:/app
    working_dir: /app
    command: ruff check

  format:
    image: ghcr.io/astral-sh/ruff:0.14.0-alpine
    volumes:
      - .:/app
    working_dir: /app
    command: ruff format --check
```

## LSP Server Configuration

### Ruff Server Features
- Real-time linting
- Auto-fixing on save
- Import organization
- Code actions
- Hover documentation
- Configuration reloading

### Server Settings
```json
{
  "settings": {
    // Line length
    "lineLength": 88,

    // Linting
    "lint": {
      "select": ["E", "F", "B", "I"],
      "ignore": ["E501"],
      "preview": false
    },

    // Formatting
    "format": {
      "preview": false,
      "quote-style": "double"
    },

    // Configuration file
    "configuration": "~/path/to/ruff.toml"
  }
}
```

### Code Actions
```json
{
  "codeActionsOnSave": {
    // Fix all auto-fixable issues
    "source.fixAll": "explicit",

    // Organize imports
    "source.organizeImports": "explicit"
  }
}
```

## Migration Guides

### From Flake8 + Black
```bash
# 1. Remove old tools
pip uninstall flake8 black isort

# 2. Install ruff
pip install ruff

# 3. Migrate configuration
# Convert .flake8 + pyproject.toml[black] → pyproject.toml[ruff]

# 4. Update pre-commit
# Replace black, flake8, isort hooks with ruff

# 5. Update CI/CD
# Replace black/flake8 commands with ruff

# 6. Test
ruff check --diff
ruff format --diff
```

### From pylint
```bash
# 1. Map pylint rules to ruff equivalents
# Use ruff's PLxxx rules (pylint compatibility)

# 2. Update configuration
[tool.ruff.lint]
select = ["E", "F", "B", "I", "UP", "PL"]

[tool.ruff.lint.pylint]
max-args = 10
max-branches = 15

# 3. Test
ruff check --select PL
```

## Best Practices

**Editor Setup**
- Enable format-on-save for consistency
- Configure code actions for auto-fixing
- Use project-specific settings (`.vscode/settings.json`)
- Sync settings across team via version control

**Pre-commit Strategy**
- Run both `ruff-check --fix` and `ruff-format`
- Order: check first, then format
- Include Jupyter notebooks if needed
- Use `types_or` for file filtering

**CI/CD Strategy**
- Run checks on every PR
- Use `--output-format github` for annotations
- Check formatting with `--check --diff`
- Consider auto-fixing with bot commits

**Performance**
- Use ruff's built-in parallelism (default)
- Cache ruff in CI (pip cache, Docker layers)
- Run on changed files only in pre-commit
- Use separate jobs for linting and formatting

**Common Mistakes to Avoid**
- Mixing multiple formatters (choose one)
- Not syncing editor config with project config
- Ignoring LSP server errors
- Not testing CI changes locally
- Forgetting to update documentation

## Quick Reference

### Editor Setup Commands

```bash
# VS Code
code --install-extension charliermarsh.ruff

# Neovim (using lazy.nvim)
# Add to plugins: 'neovim/nvim-lspconfig'

# Check LSP status
:LspInfo
```

### Pre-commit Commands

```bash
# Setup
pre-commit install
pre-commit run --all-files

# Update
pre-commit autoupdate

# Skip hooks (emergency)
git commit --no-verify
```

### CI/CD Quick Start

**GitHub Actions**
```yaml
- uses: astral-sh/ruff-action@v3
```

**GitLab CI**
```yaml
ruff-check:
  image: ghcr.io/astral-sh/ruff:0.14.0-alpine
  script: ruff check
```

### Configuration Hierarchy

1. Command-line arguments (highest priority)
2. Editor LSP settings
3. `ruff.toml` in current directory
4. `pyproject.toml` in current directory
5. Parent directory configs (recursive)
6. User config: `~/.config/ruff/ruff.toml`
7. Ruff defaults (lowest priority)

This makes ruff integration seamless across development tools and CI/CD pipelines.
