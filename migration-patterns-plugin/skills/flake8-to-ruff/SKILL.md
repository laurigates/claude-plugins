---
name: flake8-to-ruff
description: |
  Migrate a Python project from flake8 and/or isort to ruff linting.
  Use when .pre-commit-config.yaml contains pycqa/flake8 or PyCQA/isort
  hooks, or when [tool.flake8] or [tool.isort] config exists. Replaces both
  hooks with a single ruff hook, migrates rule selections, and removes the
  old tools from dependencies.
allowed-tools: Read, Write, Edit, Glob, Grep, Bash(find *), Bash(test *), Bash(pre-commit *), Bash(uvx *), AskUserQuestion, TodoWrite
model: sonnet
args: "[--check-only] [--fix]"
argument-hint: "[--check-only] [--fix]"
created: 2026-04-14
modified: 2026-05-04
reviewed: 2026-04-14
---

# /migration-patterns:flake8-to-ruff

Migrate from [flake8](https://flake8.pycqa.org/) and/or [isort](https://pycqa.github.io/isort/) to [ruff](https://docs.astral.sh/ruff/) — consolidating linting and import sorting into a single, fast Rust-based tool. Replaces pre-commit hooks, migrates rule configuration, and removes old dependencies.

## When to Use This Skill

| Use this skill when... | Keep flake8/isort when... |
|------------------------|--------------------------|
| `.pre-commit-config.yaml` contains `pycqa/flake8` or `PyCQA/isort` | You rely on a flake8 plugin with no ruff equivalent |
| `[tool.flake8]` or `[tool.isort]` config exists | Team uses flake8 API in custom scripts |
| Looking to consolidate linting tooling | CI requires specific flake8 exit codes |
| Using ruff format and wanting a unified tool | |

## Context

- Pre-commit config: !`find . -maxdepth 1 -name '.pre-commit-config.yaml'`
- pyproject.toml: !`find . -maxdepth 1 -name 'pyproject.toml'`
- setup.cfg: !`find . -maxdepth 1 -name 'setup.cfg'`
- .flake8: !`find . -maxdepth 1 -name '.flake8'`
- ruff already present: !`find . -maxdepth 1 -name 'ruff.toml'`

## Parameters

| Parameter | Description |
|-----------|-------------|
| `--check-only` | Report what would change without modifying files |
| `--fix` | Apply migration automatically |

## Execution

Execute this flake8/isort-to-ruff migration:

### Step 1: Audit current configuration

1. Read `.pre-commit-config.yaml` and locate `pycqa/flake8`, `PyCQA/isort`, and `pycqa/pep8-naming` entries.
2. Read all config sources: `pyproject.toml` (`[tool.flake8]`, `[tool.isort]`), `setup.cfg` (`[flake8]`, `[isort]`), `.flake8`.
3. Report findings:
   ```
   flake8/isort → ruff migration audit
   =====================================
   pre-commit hooks:  pycqa/flake8 v<rev>, PyCQA/isort v<rev>
   flake8 config:     [tool.flake8] max-line-length=<N>, extend-ignore=[E501,W503], per-file-ignores=<...>
   isort config:      [tool.isort] profile=black, known-first-party=[...]
   ruff already:      EXISTS / NOT PRESENT
   ```
   If `--check-only`, stop here.

### Step 2: Build ruff rule selection

Map flake8 plugins and ignore rules to ruff equivalents:

| flake8 config | ruff equivalent |
|---------------|----------------|
| `max-line-length = N` | `[tool.ruff] line-length = N` |
| `extend-ignore = E501` | `[tool.ruff.lint] ignore = ["E501"]` |
| `per-file-ignores = path:E501` | `[tool.ruff.lint.per-file-ignores] "path" = ["E501"]` |
| `pep8-naming` plugin | add `"N"` to `select` |
| `flake8-bugbear` plugin | add `"B"` to `select` |
| `flake8-annotations` plugin | add `"ANN"` to `select` |

For isort config:

| isort config | ruff equivalent |
|--------------|----------------|
| `profile = black` | `[tool.ruff.lint.isort] force-single-line = false` |
| `known-first-party = [...]` | `[tool.ruff.lint.isort] known-first-party = [...]` |
| `multi-line-output = 3` | Handled by ruff's Black-compatible default |
| `force-sort-within-sections` | `[tool.ruff.lint.isort] force-sort-within-sections = true` |

Baseline ruff rule selection (add to existing if present):

```toml
[tool.ruff.lint]
select = ["E", "W", "F", "I", "N", "B"]
# E/W = pycodestyle, F = pyflakes, I = isort, N = pep8-naming, B = bugbear
```

Preserve any existing ignores from flake8 config.

### Step 3: Update .pre-commit-config.yaml

Remove `pycqa/flake8`, `PyCQA/isort`, and any flake8 plugin repos. Add or extend the ruff pre-commit block:

```yaml
- repo: https://github.com/astral-sh/ruff-pre-commit
  rev: v0.9.1  # use latest stable ruff version
  hooks:
    - id: ruff
      args: [--fix]
    - id: ruff-format  # include if also migrating from black
```

### Step 4: Update pyproject.toml

1. Remove `[tool.flake8]` and `[tool.isort]` sections.
2. Add/merge `[tool.ruff]`, `[tool.ruff.lint]`, and `[tool.ruff.lint.isort]` sections with converted config.
3. Remove `flake8*` and `isort` from dev/lint dependencies:
   ```bash
   uvx --from uv uv remove --dev flake8 isort 2>/dev/null || true
   ```

### Step 5: Remove other config files

If standalone config files exist, delete them:
- `.flake8` → delete (config is now in `pyproject.toml`)
- `setup.cfg` `[flake8]`/`[isort]` sections → remove those sections

### Step 6: Verify migration

Run the new hook to confirm it works:

```bash
pre-commit run ruff --all-files
```

Note any new lint errors introduced by ruff's stricter defaults. Decide whether to:
- Fix them immediately
- Add temporary ignore rules in `[tool.ruff.lint] ignore`
- Accept them as a follow-up

### Step 7: Report

Print a summary:

```
flake8/isort → ruff migration complete
========================================
.pre-commit-config.yaml   UPDATED (removed flake8/isort hooks, added ruff hook)
pyproject.toml            UPDATED ([tool.flake8]+[tool.isort] → [tool.ruff.lint])
.flake8                   DELETED / NOT FOUND
setup.cfg                 UPDATED (removed [flake8]/[isort] sections) / NOT FOUND

Note: Ruff may surface new lint errors not caught by flake8. Review with:
  uvx ruff check . --select E,W,F,I,N,B

Files to stage:
  git add .pre-commit-config.yaml pyproject.toml .flake8 setup.cfg
```

## Agentic Optimizations

| Context | Command |
|---------|---------|
| Audit only | `/migration-patterns:flake8-to-ruff --check-only` |
| Apply migration | `/migration-patterns:flake8-to-ruff --fix` |
| Verify after migration | `pre-commit run ruff --all-files` |
| Check with specific rules | `uvx ruff check . --select E,W,F,I` |

## Quick Reference

| Item | Value |
|------|-------|
| ruff rule docs | https://docs.astral.sh/ruff/rules/ |
| isort equivalent | select `"I"` in ruff |
| pep8-naming equivalent | select `"N"` in ruff |
| Config section | `[tool.ruff.lint]` and `[tool.ruff.lint.isort]` |

## See Also

- `/migration-patterns:black-to-ruff-format` — Migrate black to ruff format
- `/migration-patterns:mypy-to-ty` — Migrate mypy to ty
- `/configure:repo` — End-to-end repo config driver
