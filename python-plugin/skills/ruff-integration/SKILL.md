---
model: haiku
created: 2025-12-16
modified: 2026-01-24
reviewed: 2026-01-24
name: ruff Integration
description: |
  Integrate ruff into development workflows: editor setup, pre-commit hooks, and CI/CD pipelines.
  Use when configuring ruff in VS Code, setting up pre-commit hooks, or adding ruff to GitHub Actions.
  For ruff rules/linting config see ruff-linting skill; for formatting see ruff-formatting skill.
allowed-tools: Bash(ruff *), Bash(python *), Bash(uv *), Read, Edit, Write, Grep, Glob
---

# ruff Integration

Integrate `ruff` into editors, pre-commit hooks, and CI/CD pipelines.

## When to Use This Skill

| Use this skill when... | Use ruff-linting instead when... | Use ruff-formatting instead when... |
|------------------------|----------------------------------|-------------------------------------|
| Setting up VS Code / editor | Configuring lint rules | Configuring format options |
| Adding pre-commit hooks | Selecting/ignoring rules | Quote style, line length |
| Adding ruff to CI/CD | Understanding rule categories | Format differences |
| Docker/build integration | Fixing lint violations | Checking format compliance |

## VS Code Setup

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

## Pre-commit Integration

```yaml
# .pre-commit-config.yaml
repos:
  - repo: https://github.com/astral-sh/ruff-pre-commit
    rev: v0.14.0
    hooks:
      - id: ruff-check
        args: [--fix]
      - id: ruff-format
```

```bash
pre-commit install           # Install hooks
pre-commit run --all-files   # Run manually
pre-commit autoupdate        # Update versions
```

## GitHub Actions CI

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
        with:
          args: 'check --output-format github'
```

**Separate lint + format checks:**
```yaml
jobs:
  ruff-check:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - run: pip install ruff
      - run: ruff check --output-format github

  ruff-format:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - run: pip install ruff
      - run: ruff format --check --diff
```

## Configuration Hierarchy

1. Command-line arguments (highest priority)
2. Editor LSP settings
3. `ruff.toml` in current directory
4. `pyproject.toml` in current directory
5. Parent directory configs (recursive)
6. User config: `~/.config/ruff/ruff.toml`
7. Ruff defaults (lowest priority)

## Best Practices

- **Editor**: Enable format-on-save, use project-specific `.vscode/settings.json`
- **Pre-commit**: Run `ruff-check --fix` first, then `ruff-format`
- **CI/CD**: Use `--output-format github` for PR annotations
- **Performance**: Cache ruff in CI, run on changed files only in pre-commit
- **Team**: Commit editor/pre-commit configs to version control

## Agentic Optimizations

| Context | Command |
|---------|---------|
| Quick lint check | `ruff check --output-format github` |
| Format check | `ruff format --check --diff` |
| Auto-fix all | `ruff check --fix && ruff format` |
| Errors only | `ruff check --select E` |
| CI annotations | `ruff check --output-format github` |
| JSON output | `ruff check --output-format json` |
| Specific files | `ruff check --diff path/to/file.py` |

## Quick Reference

```bash
# Editor
code --install-extension charliermarsh.ruff

# Pre-commit
pre-commit install && pre-commit run --all-files

# CI (GitHub Actions)
uses: astral-sh/ruff-action@v3

# Docker
docker run -v .:/app ghcr.io/astral-sh/ruff:0.14.0-alpine check /app
```

For editor configs (Neovim, Zed, Helix), GitLab/CircleCI/Jenkins CI, build system integration, Docker setup, LSP configuration, and migration guides, see [REFERENCE.md](REFERENCE.md).
