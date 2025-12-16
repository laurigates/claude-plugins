---
name: python-code-quality
description: |
  Python code quality with ruff (linting & formatting) and mypy (type checking).
  Covers pyproject.toml configuration, pre-commit hooks, and type hints.
  Use when user mentions ruff, mypy, linting, formatting, type checking,
  code style, or Python code quality.
---

# Python Code Quality

Quick reference for Python code quality tools: ruff (linting & formatting), mypy (type checking).

## When This Skill Applies

- Linting Python code
- Code formatting
- Type checking
- Pre-commit hooks
- CI/CD quality gates
- Code style enforcement

## Quick Reference

### Ruff (Linter & Formatter)

```bash
# Lint code
uv run ruff check .

# Auto-fix issues
uv run ruff check --fix .

# Format code
uv run ruff format .

# Check and format
uv run ruff check --fix . && uv run ruff format .

# Show specific rule
uv run ruff check --select E501  # Line too long

# Ignore specific rule
uv run ruff check --ignore E501
```

### Mypy (Type Checking)

```bash
# Type check project
uv run mypy .

# Type check specific file
uv run mypy src/module.py

# Strict mode
uv run mypy --strict .

# Show error codes
uv run mypy --show-error-codes .
```

## pyproject.toml Configuration

```toml
[tool.ruff]
line-length = 88
target-version = "py311"

[tool.ruff.lint]
select = [
    "E",   # pycodestyle errors
    "W",   # pycodestyle warnings
    "F",   # pyflakes
    "I",   # isort
    "N",   # pep8-naming
    "UP",  # pyupgrade
    "B",   # flake8-bugbear
]
ignore = [
    "E501",  # line too long (handled by formatter)
]

[tool.ruff.lint.isort]
known-first-party = ["myproject"]

[tool.mypy]
python_version = "3.11"
warn_return_any = true
warn_unused_configs = true
disallow_untyped_defs = true
exclude = ["tests"]
```

## Type Hints

```python
# Modern type hints (Python 3.10+)
def process_data(
    items: list[str],                    # Not List[str]
    config: dict[str, int],              # Not Dict[str, int]
    optional: str | None = None,         # Not Optional[str]
) -> tuple[bool, str]:                   # Not Tuple[bool, str]
    return True, "success"

# Type aliases
from typing import TypeAlias

UserId: TypeAlias = int
UserDict: TypeAlias = dict[str, str | int]

def get_user(user_id: UserId) -> UserDict:
    return {"id": user_id, "name": "Alice"}
```

## Pre-commit Configuration

```yaml
# .pre-commit-config.yaml
repos:
  - repo: https://github.com/astral-sh/ruff-pre-commit
    rev: v0.1.9
    hooks:
      - id: ruff
        args: [--fix]
      - id: ruff-format

  - repo: https://github.com/pre-commit/mirrors-mypy
    rev: v1.7.1
    hooks:
      - id: mypy
        additional_dependencies: [types-requests]
```

## Common Ruff Rules

- **E501**: Line too long
- **F401**: Unused import
- **F841**: Unused variable
- **I001**: Import not sorted
- **N806**: Variable should be lowercase
- **B008**: Function call in argument defaults

## See Also

- `python-testing` - Testing code quality
- `uv-project-management` - Adding quality tools to projects
- `python-development` - Core Python patterns

## References

- Ruff: https://docs.astral.sh/ruff/
- Mypy: https://mypy.readthedocs.io/
- Detailed guide: See REFERENCE.md
