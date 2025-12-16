# Python Code Quality - Comprehensive Reference

Complete guide to Python code quality with ruff and mypy.

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

## Mypy (Type Checking)

Static type checker for Python.

### Installation

```bash
uv add --dev mypy
```

### Usage

```bash
# Type check project
mypy .

# Strict mode
mypy --strict .

# Incremental mode
mypy --incremental .
```

### Configuration

```toml
[tool.mypy]
python_version = "3.11"
warn_return_any = true
warn_unused_configs = true
disallow_untyped_defs = true
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
- **Mypy**: https://mypy.readthedocs.io/
- **Type Hints**: https://docs.python.org/3/library/typing.html
