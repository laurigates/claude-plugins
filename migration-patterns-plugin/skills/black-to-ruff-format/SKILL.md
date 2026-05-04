---
name: black-to-ruff-format
description: |
  Migrate a Python project from black to ruff format (ruff's formatter).
  Use when .pre-commit-config.yaml contains psf/black, or when [tool.black]
  config exists in pyproject.toml. Replaces the black pre-commit hook with
  ruff-format, migrates config, and removes black from dependencies.
allowed-tools: Read, Write, Edit, Glob, Grep, Bash(find *), Bash(test *), Bash(pre-commit *), Bash(uvx *), AskUserQuestion, TodoWrite
model: sonnet
args: "[--check-only] [--fix]"
argument-hint: "[--check-only] [--fix]"
created: 2026-04-14
modified: 2026-05-04
reviewed: 2026-04-14
---

# /migration-patterns:black-to-ruff-format

Migrate from [black](https://github.com/psf/black) to [ruff format](https://docs.astral.sh/ruff/formatter/) — Ruff's drop-in Black-compatible formatter written in Rust (~35x faster). Replaces the `psf/black` pre-commit hook, migrates `[tool.black]` configuration, and removes black from dev dependencies.

## When to Use This Skill

| Use this skill when... | Keep black when... |
|------------------------|-------------------|
| `.pre-commit-config.yaml` contains `psf/black` | Team has strong preference for black's exact output |
| `[tool.black]` exists in pyproject.toml | CI uses `black --check` specifically by name |
| Repo already uses ruff for linting | Project uses black's API in build scripts |
| Wanting to consolidate formatting under ruff | |

## Context

- Pre-commit config: !`find . -maxdepth 1 -name '.pre-commit-config.yaml'`
- pyproject.toml: !`find . -maxdepth 1 -name 'pyproject.toml'`
- ruff already present: !`find . -maxdepth 1 -name 'ruff.toml'`

## Parameters

| Parameter | Description |
|-----------|-------------|
| `--check-only` | Report what would change without modifying files |
| `--fix` | Apply migration automatically |

## Execution

Execute this black-to-ruff-format migration:

### Step 1: Audit current black configuration

1. Read `.pre-commit-config.yaml` and locate `psf/black` entries.
2. Read `pyproject.toml` and extract the `[tool.black]` section.
3. Report findings:
   ```
   black → ruff-format migration audit
   =====================================
   pre-commit hook:  psf/black found at rev <rev>
   pyproject.toml:   [tool.black] section found (line-length=<N>, target-version=<X>)
   ruff already:     EXISTS / NOT PRESENT
   ```
   If `--check-only`, stop here.

### Step 2: Update .pre-commit-config.yaml

Remove the `psf/black` repo block. If `ruff-pre-commit` is already present, add the `ruff-format` hook ID. Otherwise add the full ruff-pre-commit repo block with both `ruff` and `ruff-format` hooks:

```yaml
- repo: https://github.com/astral-sh/ruff-pre-commit
  rev: v0.9.1  # use latest stable ruff version
  hooks:
    - id: ruff
      args: [--fix]
    - id: ruff-format
```

If `ruff-pre-commit` already exists but only has the `ruff` linter hook, add the `ruff-format` hook ID under the same repo block.

### Step 3: Migrate [tool.black] → [tool.ruff.format] in pyproject.toml

Convert black configuration to ruff format config:

| black key | ruff equivalent | Notes |
|-----------|----------------|-------|
| `line-length` | `[tool.ruff] line-length` | Shared with linter |
| `target-version` | `[tool.ruff] target-version` | Shared with linter |
| `skip-string-normalization` | `[tool.ruff.format] quote-style = "preserve"` | |
| `skip-magic-trailing-comma` | `[tool.ruff.format] skip-magic-trailing-comma = true` | |
| `preview` | `[tool.ruff.format] preview = true` | |

Remove the `[tool.black]` section. Merge settings into `[tool.ruff]` and `[tool.ruff.format]` sections (create if absent, merge if existing).

### Step 4: Remove black from dependencies

Remove `black` from dev/lint dependencies:

```bash
# With uv
uvx --from uv uv remove --dev black 2>/dev/null || true
```

If not using uv, note it for manual removal.

### Step 5: Verify migration

Run the new hook to confirm it works:

```bash
pre-commit run ruff-format --all-files
```

If it exits 0, the migration is complete. If it produces diffs, this is expected on first run (ruff format may reformat some files differently from black). Commit the reformatted files as part of the migration.

### Step 6: Report

Print a summary of changes:

```
black → ruff-format migration complete
=======================================
.pre-commit-config.yaml   UPDATED (removed psf/black, added ruff-format hook)
pyproject.toml            UPDATED ([tool.black] → [tool.ruff.format])

Note: ruff-format is Black-compatible (same defaults), but may reformat a small
number of files. Review the diff and include these reformatted files in the
migration commit.

Files to stage:
  git add .pre-commit-config.yaml pyproject.toml
  git add <any reformatted .py files>
```

## Agentic Optimizations

| Context | Command |
|---------|---------|
| Audit only | `/migration-patterns:black-to-ruff-format --check-only` |
| Apply migration | `/migration-patterns:black-to-ruff-format --fix` |
| Verify after migration | `pre-commit run ruff-format --all-files` |
| Check format directly | `uvx ruff format --check .` |

## Quick Reference

| Item | Value |
|------|-------|
| ruff format docs | https://docs.astral.sh/ruff/formatter/ |
| Black compatibility | ruff format is designed as a Black drop-in with ~99.9% compatible output |
| Config section | `[tool.ruff.format]` in pyproject.toml |
| Pre-commit hook | `ruff-format` in `astral-sh/ruff-pre-commit` |

## See Also

- `/migration-patterns:flake8-to-ruff` — Migrate flake8/isort linting to ruff
- `/migration-patterns:mypy-to-ty` — Migrate mypy to ty
- `/configure:repo` — End-to-end repo config driver
