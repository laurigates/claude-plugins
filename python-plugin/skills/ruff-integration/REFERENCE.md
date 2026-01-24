# ruff Integration Reference

Detailed configurations for editors, CI/CD platforms, build systems, Docker, and migration guides.

## Editor Integration

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

## CI/CD Integration

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
      - image: cimg/python:3.11
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
FROM python:3.11-slim as development
RUN pip install --no-cache-dir ruff
COPY . /app
WORKDIR /app
RUN ruff check && ruff format --check

FROM python:3.11-slim as production
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
