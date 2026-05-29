---
created: 2025-12-16
modified: 2026-05-29
reviewed: 2026-05-29
name: python-code-quality
description: Python code quality with ruff and ty. Use when the user mentions ruff, ty, linting, formatting, type checking, or Python code style.
user-invocable: false
allowed-tools: Bash, Read, Grep, Glob
---

# Python Code Quality

Orchestration index for the Python quality stack. This skill **routes** to
the focused skills that own each tool — it does not restate their commands.
Reach for it when setting up or reasoning about the whole stack (lint +
format + type-check + tests) at once; reach for a focused skill when tuning
one tool.

## When to Use This Skill

| Use this skill when... | Use a focused sibling instead when... |
|---|---|
| Standing up a complete quality stack for a new project | Tuning only ruff lint rule selection — use `ruff-linting` |
| Reasoning about how the tools fit together / comparing them | Configuring only ruff formatter quirks — use `ruff-formatting` |
| Wiring lint + type-check into pre-commit and CI together | Configuring strict type-checker rules — use `ty-type-checking` or `basedpyright-type-checking` |

## Routing Table

| Concern | Focused skill |
|---------|---------------|
| Lint rules, rule selection, auto-fix | `python-plugin:ruff-linting` |
| Code formatting (quote style, line length) | `python-plugin:ruff-formatting` |
| Editor / pre-commit / CI / Docker wiring for ruff | `python-plugin:ruff-linting` → its `REFERENCE.md` |
| Type checking with ty | `python-plugin:ty-type-checking` |
| Type checking with basedpyright | `python-plugin:basedpyright-type-checking` |
| Dead-code detection | `python-plugin:vulture-dead-code` |
| Test quality / coverage | `python-plugin:python-testing`, `python-plugin:pytest-advanced` |
| Modern type-hint syntax and idioms | `python-plugin:python-development` |
| Adding the tools to a project | `python-plugin:uv-project-management` |

## Full Stack at a Glance

The one thing this index owns: the tools running **together** in pre-commit.
For each tool's flags and config, follow the routing table above.

```yaml
# .pre-commit-config.yaml — ruff (lint + format) and ty together
repos:
  - repo: https://github.com/astral-sh/ruff-pre-commit
    rev: v0.14.0
    hooks:
      - id: ruff-check
        args: [--fix]
      - id: ruff-format
  - repo: https://github.com/astral-sh/ty
    rev: v0.0.10
    hooks:
      - id: ty
```

A typical CI quality gate runs the same three steps: `ruff check`,
`ruff format --check`, `ty check`. See `ruff-linting` § CI/CD Integration and
`ty-type-checking` for the runnable forms.

## References

- Ruff: <https://docs.astral.sh/ruff/>
- ty: <https://docs.astral.sh/ty/>
