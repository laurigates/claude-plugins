---
name: mypy-to-ty
description: |
  Migrate a Python project from mypy to ty (Astral's type checker). Use when
  .pre-commit-config.yaml contains mirrors-mypy, or when [tool.mypy] config
  exists in pyproject.toml, and you want to switch to the faster ty checker.
  Swaps the pre-commit hook to a local repo running uvx ty check, converts
  [tool.mypy] to [tool.ty], and removes mypy.ini.
allowed-tools: Read, Write, Edit, Glob, Grep, Bash(find *), Bash(test *), Bash(pre-commit *), Bash(uvx *), AskUserQuestion, TodoWrite
model: sonnet
args: "[--check-only] [--fix]"
argument-hint: "[--check-only] [--fix]"
created: 2026-04-14
modified: 2026-05-04
reviewed: 2026-04-14
---

# /migration-patterns:mypy-to-ty

Migrate from mypy to [ty](https://github.com/astral-sh/ty) — Astral's new fast Python type checker. Replaces the `mirrors-mypy` pre-commit hook with a local `repo: local` hook using `uvx ty check`, migrates config from `[tool.mypy]` to `[tool.ty]`, and removes `mypy.ini`.

## When to Use This Skill

| Use this skill when... | Keep mypy when... |
|------------------------|-------------------|
| `.pre-commit-config.yaml` contains `mirrors-mypy` | ty does not yet support a specific mypy plugin you rely on |
| `[tool.mypy]` section exists in `pyproject.toml` | CI pipeline depends on mypy-specific exit codes or plugins |
| You want faster type checking (ty is written in Rust) | Project uses mypy daemon (`dmypy`) for incremental checks |
| Repo uses uv and the astral stack already | Team prefers mypy's error message format |

## Context

- Pre-commit config: !`find . -maxdepth 1 -name '.pre-commit-config.yaml'`
- pyproject.toml: !`find . -maxdepth 1 -name 'pyproject.toml'`
- mypy.ini: !`find . -maxdepth 1 -name 'mypy.ini'`
- uv available: !`find . -maxdepth 1 -name 'uv.lock'`

## Parameters

| Parameter | Description |
|-----------|-------------|
| `--check-only` | Report what would change without modifying files |
| `--fix` | Apply migration automatically |

## Execution

Execute this mypy-to-ty migration:

### Step 1: Audit current mypy configuration

1. Read `.pre-commit-config.yaml` and locate any `mirrors-mypy` or `mypy` entries.
2. Read `pyproject.toml` and extract the `[tool.mypy]` section.
3. Check for `mypy.ini`.
4. Report findings:
   ```
   mypy → ty migration audit
   ==========================
   pre-commit hook:   mirrors-mypy found at rev <rev>
   pyproject.toml:    [tool.mypy] section found (N lines)
   mypy.ini:          FOUND / NOT FOUND
   uv.lock:           EXISTS (uv available) / MISSING
   ```
   If `--check-only`, stop here.

### Step 2: Update .pre-commit-config.yaml

Remove the `mirrors-mypy` repo block. Add a `repo: local` hook for ty:

```yaml
- repo: local
  hooks:
    - id: ty
      name: ty type check
      entry: uvx ty check
      language: system
      types: [python]
      pass_filenames: false
```

**Note:** `astral-sh/ty-pre-commit` does not yet exist as a hosted pre-commit repo. The `repo: local` pattern with `uvx ty check` is the correct approach until an official mirror is published.

If an `entry: mypy` hook in a non-mirrors-mypy repo exists, replace it similarly.

### Step 3: Migrate [tool.mypy] → [tool.ty] in pyproject.toml

Read the `[tool.mypy]` section and convert each key to the ty equivalent:

| mypy key | ty equivalent | Notes |
|----------|--------------|-------|
| `python_version` | `python-version` | Rename only |
| `strict` | `strict` | Same |
| `warn_return_any` | `warn-return-any` | Kebab-case |
| `disallow_untyped_defs` | `disallow-untyped-defs` | Kebab-case |
| `ignore_missing_imports` | Not needed | ty resolves stubs natively |
| `exclude` | `exclude` | Same |
| Per-module `[[tool.mypy.overrides]]` | Drop or convert manually | Note for manual review |

Remove the `[tool.mypy]` section (and any `[[tool.mypy.overrides]]` sections). Add `[tool.ty]` with converted keys. Annotate any options that need manual review.

### Step 4: Remove mypy.ini

If `mypy.ini` exists, delete it. Its content should already be in `[tool.ty]` after Step 3.

### Step 5: Remove mypy from dependencies

If `mypy` appears in `pyproject.toml` dev/lint dependencies, remove it:

```bash
# With uv
uvx --from uv uv remove --dev mypy 2>/dev/null || true
```

If not using uv, note it for manual removal.

### Step 6: Verify migration

Run the new hook to confirm it works:

```bash
pre-commit run ty --all-files
```

If it exits 0, the migration is complete. If it exits non-zero:
- Summarize ty errors
- Suggest addressing them before committing

### Step 7: Report

Print a summary of all changes made and list files to commit:

```
mypy → ty migration complete
=============================
.pre-commit-config.yaml   UPDATED (removed mirrors-mypy, added local ty hook)
pyproject.toml            UPDATED ([tool.mypy] → [tool.ty])
mypy.ini                  DELETED / NOT FOUND

Manual review needed:
  - [[tool.mypy.overrides]] sections were dropped — verify ty handles them
  - Check ty docs for any unsupported mypy options

Files to stage:
  git add .pre-commit-config.yaml pyproject.toml
```

## Agentic Optimizations

| Context | Command |
|---------|---------|
| Audit only | `/migration-patterns:mypy-to-ty --check-only` |
| Apply migration | `/migration-patterns:mypy-to-ty --fix` |
| Verify after migration | `pre-commit run ty --all-files` |
| Test ty directly | `uvx ty check .` |

## Quick Reference

| Item | Value |
|------|-------|
| ty docs | https://github.com/astral-sh/ty |
| Pre-commit hook type | `repo: local`, `entry: uvx ty check` |
| Config section | `[tool.ty]` in pyproject.toml |
| Key difference | ty uses kebab-case keys; mypy uses underscore |

## See Also

- `/migration-patterns:black-to-ruff-format` — Migrate from black to ruff format
- `/migration-patterns:flake8-to-ruff` — Migrate flake8/isort to ruff
- `/configure:repo` — End-to-end repo config driver
