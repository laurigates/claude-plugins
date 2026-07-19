# ruff Integration Reference

Wiring `ruff` into editors, pre-commit hooks, CI/CD platforms, build systems,
Docker, and migration guides. This is the on-demand companion to the
`ruff-linting` skill — the SKILL.md body covers linting rules and the quick
pre-commit / GitHub Actions form; this file holds the comprehensive
integration material (formerly the standalone `ruff-integration` skill).

## When to reach for this file

| Need | Section |
|------|---------|
| Editor format-on-save (VS Code, Neovim, Zed, Helix) | [Editor Integration](#editor-integration) |
| Pre-commit hook setup | [Pre-commit Integration](#pre-commit-integration) |
| CI on GitHub Actions / GitLab / CircleCI / Jenkins | [CI/CD Integration](#cicd-integration) |
| Make / Just / Task / tox recipes | [Build System Integration](#build-system-integration) |
| Docker / Docker Compose | [Docker Integration](#docker-integration) |
| LSP server settings | [LSP Server Configuration](#lsp-server-configuration) |
| Migrating from Flake8/Black/pylint | [Migration Guides](#migration-guides) |

## Editor Integration

### VS Code

```json
// .vscode/settings.json
{
  "[python]": {
    "editor.formatOnSave": true,
    "editor.codeActionsOnSave": {
      "source.fixAll": "explicit",
      "source.organizeImports": "explicit"
    },
    "editor.defaultFormatter": "charliermarsh.ruff"
  },
  "ruff.lint.args": ["--select=E,F,B,I"],
  "ruff.importStrategy": "fromEnvironment"
}
```

```bash
# Install extension
code --install-extension charliermarsh.ruff
```

### Neovim (nvim-lspconfig)

```lua
require('lspconfig').ruff.setup {
  init_options = {
    settings = {
      lint = {
        select = {"E", "F", "B", "I"},
        ignore = {"E501"}
      },
      format = {
        lineLength = 88,
        quoteStyle = "double"
      }
    }
  }
}
```

**Using none-ls.nvim:**
```lua
local null_ls = require("null-ls")
null_ls.setup {
  sources = {
    null_ls.builtins.formatting.ruff,
    null_ls.builtins.diagnostics.ruff,
  }
}
```

### Zed

```json
// settings.json
{
  "languages": {
    "Python": {
      "language_servers": ["ruff"],
      "formatter": "language_server",
      "format_on_save": "on"
    }
  },
  "lsp": {
    "ruff": {
      "initialization_options": {
        "settings": {
          "lint": { "select": ["E", "F", "B", "I"] }
        }
      }
    }
  }
}
```

### Helix

```toml
# ~/.config/helix/languages.toml
[[language]]
name = "python"
language-servers = ["ruff"]
auto-format = true
formatter = { command = "ruff", args = ["format", "-"] }

[language-server.ruff]
command = "ruff"
args = ["server"]
```

## Pre-commit Integration

```yaml
# .pre-commit-config.yaml
repos:
  - repo: https://github.com/astral-sh/ruff-pre-commit
    rev: v0.15.22
    hooks:
      - id: ruff-check
        args: [--fix]
      - id: ruff-format
```

**Advanced hook configuration** (explicit config + rule selection, Jupyter):
```yaml
repos:
  - repo: https://github.com/astral-sh/ruff-pre-commit
    rev: v0.15.22
    hooks:
      - id: ruff-check
        name: Ruff linter
        args:
          - --fix
          - --config=pyproject.toml
          - --select=E,F,B,I
        types_or: [python, pyi, jupyter]
      - id: ruff-format
```

```bash
pre-commit install           # Install hooks
pre-commit run --all-files   # Run manually
pre-commit autoupdate        # Update versions
```

Run `ruff-check --fix` before `ruff-format` so import/lint fixes land before
the formatter normalizes layout.

## CI/CD Integration

### GitHub Actions

```yaml
# .github/workflows/lint.yml
name: Lint
on: [push, pull_request]

jobs:
  ruff:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4.3.1
      - uses: astral-sh/ruff-action@v3.6.1
        with:
          args: 'check --output-format github'
          changed-files: 'true'   # lint only changed files
```

**Separate lint + format checks:**
```yaml
jobs:
  ruff-check:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4.3.1
      - run: pip install ruff
      - run: ruff check --output-format github

  ruff-format:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4.3.1
      - run: pip install ruff
      - run: ruff format --check --diff
```

### GitLab CI

```yaml
.base_ruff:
  stage: build
  image:
    name: ghcr.io/astral-sh/ruff:0.14.0-alpine

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
```

### CircleCI

```yaml
version: 2.1
jobs:
  lint:
    docker:
      - image: cimg/python:3.14
    steps:
      - checkout
      - run: pip install ruff
      - run: ruff check
      - run: ruff format --check

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
        stage('Lint') {
            steps {
                sh 'pip install ruff'
                sh 'ruff check --output-format json > ruff-report.json'
            }
        }
        stage('Format Check') {
            steps { sh 'ruff format --check' }
        }
    }
    post {
        always { archiveArtifacts artifacts: 'ruff-report.json' }
    }
}
```

## Build System Integration

### Make

```makefile
.PHONY: lint format check fix

lint:
	ruff check

format:
	ruff format

check: lint
	ruff format --check

fix:
	ruff check --fix
	ruff format
```

### Just

```just
lint:
    ruff check

format:
    ruff format

fix:
    ruff check --fix
    ruff format

ci: lint
    ruff format --check
```

### Task (go-task)

```yaml
version: '3'
tasks:
  lint:
    cmds: [ruff check]
  format:
    cmds: [ruff format]
  fix:
    cmds:
      - ruff check --fix
      - ruff format
  ci:
    deps: [lint]
    cmds: [ruff format --check]
```

### tox

```ini
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
FROM python:3.13-slim as development
RUN pip install --no-cache-dir ruff
COPY . /app
WORKDIR /app
RUN ruff check && ruff format --check

FROM python:3.13-slim as production
# ... production setup
```

### Docker Compose

```yaml
services:
  lint:
    image: ghcr.io/astral-sh/ruff:0.14.0-alpine
    volumes: [".:/app"]
    working_dir: /app
    command: ruff check

  format:
    image: ghcr.io/astral-sh/ruff:0.14.0-alpine
    volumes: [".:/app"]
    working_dir: /app
    command: ruff format --check
```

## Configuration Hierarchy

1. Command-line arguments (highest priority)
2. Editor LSP settings
3. `ruff.toml` in current directory
4. `pyproject.toml` in current directory
5. Parent directory configs (recursive)
6. User config: `~/.config/ruff/ruff.toml`
7. Ruff defaults (lowest priority)

## LSP Server Configuration

### Server Settings

```json
{
  "settings": {
    "lineLength": 88,
    "lint": {
      "select": ["E", "F", "B", "I"],
      "ignore": ["E501"],
      "preview": false
    },
    "format": {
      "preview": false,
      "quote-style": "double"
    },
    "configuration": "~/path/to/ruff.toml"
  }
}
```

### Code Actions

```json
{
  "codeActionsOnSave": {
    "source.fixAll": "explicit",
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

# 4. Update pre-commit hooks (replace black, flake8, isort with ruff)

# 5. Test
ruff check --diff
ruff format --diff
```

### From pylint

```toml
# Map pylint rules to ruff's PLxxx rules
[tool.ruff.lint]
select = ["E", "F", "B", "I", "UP", "PL"]

[tool.ruff.lint.pylint]
max-args = 10
max-branches = 15
```

```bash
ruff check --select PL  # Test pylint-compatible rules
```

## Best Practices

- **Editor**: Enable format-on-save, use project-specific `.vscode/settings.json`
- **Pre-commit**: Run `ruff-check --fix` first, then `ruff-format`
- **CI/CD**: Use `--output-format github` for PR annotations
- **Performance**: Cache ruff in CI, run on changed files only in pre-commit
- **Team**: Commit editor/pre-commit configs to version control
