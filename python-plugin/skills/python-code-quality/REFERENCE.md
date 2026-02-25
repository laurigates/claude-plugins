# Python Code Quality - Comprehensive Reference

Complete guide to Python code quality with ruff and ty.

## Ruff (Linter & Formatter)

Ruff is an extremely fast Python linter and code formatter, written in Rust. It replaces black, isort, flake8, and many plugins.

### Installation

```bash
uv add --dev ruff
```

### Linting

```bash
# Check all files
ruff check .

# Auto-fix
ruff check --fix .

# Watch mode
ruff check --watch .
```

### Formatting

```bash
# Format code
ruff format .

# Check formatting
ruff format --check .
```

### Configuration

```toml
[tool.ruff]
line-length = 88
target-version = "py311"
src = ["src", "tests"]

[tool.ruff.lint]
select = ["E", "F", "I", "N", "UP", "B"]
ignore = ["E501"]

[tool.ruff.format]
quote-style = "double"
indent-style = "space"
```

---

## ty (Type Checking)

Extremely fast Python type checker from Astral (10-100x faster than mypy/Pyright), written in Rust.

### Installation

```bash
uv add --dev ty
```

### Usage

```bash
# Type check project
ty check

# Type check specific directory
ty check src/

# Hide progress (useful for CI)
ty check --hide-progress

# Verbose mode
ty check --verbose
```

### Configuration

```toml
[tool.ty]
python-version = "3.11"
exclude = [
    "**/__pycache__",
    "**/.venv",
]

[tool.ty.rules]
possibly-unbound = "warn"
```

---

## Best Practices

1. Run ruff before committing
2. Enable type hints on all functions
3. Use pre-commit hooks
4. Configure in pyproject.toml
5. Run in CI/CD

---

## References

- **Ruff**: https://docs.astral.sh/ruff/
- **ty**: https://docs.astral.sh/ty/
- **Type Hints**: https://docs.python.org/3/library/typing.html
