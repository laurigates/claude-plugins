# Python Development - Detailed Reference

## Complete pyproject.toml Configuration

```toml
[project]
name = "my-awesome-project"
version = "0.1.0"
description = "A modern Python project"
readme = "README.md"
authors = [
    { name = "Your Name", email = "you@example.com" }
]
license = { text = "MIT" }
requires-python = ">=3.10"
keywords = ["python", "modern", "uv"]
classifiers = [
    "Development Status :: 4 - Beta",
    "Programming Language :: Python :: 3",
    "Programming Language :: Python :: 3.10",
    "Programming Language :: Python :: 3.11",
    "Programming Language :: Python :: 3.12",
]

dependencies = [
    "requests>=2.31.0",
    "pydantic>=2.0.0",
]

[dependency-groups]
dev = [
    "pytest>=8.0.0",
    "pytest-cov>=4.0.0",
    "mypy>=1.8.0",
    "ruff>=0.1.0",
]
docs = [
    "sphinx>=7.0.0",
    "sphinx-rtd-theme>=2.0.0",
]
security = [
    "bandit>=1.7.0",
    "safety>=3.0.0",
]

[project.urls]
Homepage = "https://github.com/user/project"
Documentation = "https://project.readthedocs.io"
Repository = "https://github.com/user/project.git"
Issues = "https://github.com/user/project/issues"

[build-system]
requires = ["hatchling"]
build-backend = "hatchling.build"

[tool.hatch.build.targets.wheel]
packages = ["src/my_awesome_project"]
```

## Advanced ruff Configuration

```toml
[tool.ruff]
target-version = "py310"
line-length = 88
fix = true

[tool.ruff.lint]
select = [
    "E",    # pycodestyle errors
    "W",    # pycodestyle warnings
    "F",    # pyflakes
    "I",    # isort
    "B",    # flake8-bugbear
    "C4",   # flake8-comprehensions
    "UP",   # pyupgrade
    "ARG",  # flake8-unused-arguments
    "SIM",  # flake8-simplify
    "TCH",  # flake8-type-checking
    "PTH",  # flake8-use-pathlib
]
ignore = [
    "E501",  # line too long, handled by formatter
    "B008",  # do not perform function calls in argument defaults
]

[tool.ruff.lint.per-file-ignores]
"__init__.py" = ["F401"]  # unused imports in __init__.py
"tests/**/*.py" = ["ARG", "S101"]  # allow assert statements in tests

[tool.ruff.lint.isort]
known-first-party = ["my_awesome_project"]

[tool.ruff.format]
quote-style = "double"
indent-style = "space"
skip-magic-trailing-comma = false
```

## Type Checking Configuration

```toml
[tool.mypy]
python_version = "3.10"
warn_return_any = true
warn_unused_configs = true
disallow_untyped_defs = true
disallow_incomplete_defs = true
check_untyped_defs = true
disallow_untyped_decorators = true
warn_redundant_casts = true
warn_unused_ignores = true
warn_no_return = true
warn_unreachable = true
strict_equality = true

[[tool.mypy.overrides]]
module = ["tests.*"]
disallow_untyped_defs = false
```

## pytest Configuration

```toml
[tool.pytest.ini_options]
minversion = "8.0"
addopts = [
    "--strict-markers",
    "--strict-config",
    "--cov=src",
    "--cov-report=term-missing:skip-covered",
    "--cov-report=html",
    "--cov-report=xml",
    "--cov-fail-under=95",
]
testpaths = ["tests"]
markers = [
    "slow: marks tests as slow",
    "integration: marks tests as integration tests",
]
```

## Advanced Debugging Patterns

```python
# Strategic debugging with pdb
import pdb

def problematic_function(data):
    pdb.set_trace()  # Breakpoint for interactive debugging
    # Or use breakpoint() in Python 3.7+
    result = complex_operation(data)
    return result

# Conditional breakpoints
if suspicious_condition:
    breakpoint()  # Only debug when condition is met

# Post-mortem debugging
import sys
import pdb

try:
    risky_operation()
except Exception:
    pdb.post_mortem()  # Debug at exception point

# Memory leak detection
import tracemalloc
tracemalloc.start()

# ... code to profile ...

current, peak = tracemalloc.get_traced_memory()
print(f"Current memory usage: {current / 10**6:.1f} MB")
tracemalloc.stop()

# Exception context preservation
import traceback

try:
    problematic_code()
except Exception as e:
    tb_str = traceback.format_exc()
    # Log or analyze the complete traceback
```

## Django/Flask Debugging

```python
# Django settings.py for debugging
DEBUG = True
INTERNAL_IPS = ['127.0.0.1']  # For debug toolbar

# Django debug toolbar
INSTALLED_APPS += ['debug_toolbar']
MIDDLEWARE += ['debug_toolbar.middleware.DebugToolbarMiddleware']

# Flask debugging
app = Flask(__name__)
app.debug = True
app.config['PROPAGATE_EXCEPTIONS'] = True

# Werkzeug debugger PIN
import os
os.environ['WERKZEUG_DEBUG_PIN'] = 'off'  # Disable PIN in development
```

## CI/CD Integration

### Pre-commit Configuration

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
    rev: v1.8.0
    hooks:
      - id: mypy
        additional_dependencies: [types-requests]

  - repo: https://github.com/PyCQA/bandit
    rev: 1.7.5
    hooks:
      - id: bandit
        args: ["-c", "pyproject.toml"]
```

### GitHub Actions Workflow

```yaml
# .github/workflows/ci.yml
name: CI

on: [push, pull_request]

jobs:
  test:
    runs-on: ubuntu-latest
    strategy:
      matrix:
        python-version: ["3.10", "3.11", "3.12"]

    steps:
      - uses: actions/checkout@v4

      - name: Install uv
        uses: astral-sh/setup-uv@v3
        with:
          version: "latest"

      - name: Set up Python
        run: uv python install ${{ matrix.python-version }}

      - name: Install dependencies
        run: uv sync --all-extras --dev

      - name: Run ruff
        run: uv run ruff check .

      - name: Run type checking
        run: uv run mypy .

      - name: Run tests
        run: uv run pytest --cov --cov-report=xml

      - name: Upload coverage
        uses: codecov/codecov-action@v3
```

## Migration from Poetry

```bash
# Migrate existing Poetry project
uv init --python $(poetry env info --python)
uv add $(poetry export --dev | sed 's/==.*//')
rm poetry.lock pyproject.toml.bak
```

## Troubleshooting Guide

```bash
# Dependency conflicts
uv lock --resolution=highest           # Prefer newer versions
uv add package --no-sync              # Add without syncing

# Environment issues
uv clean                               # Clean cache
uv python install --force 3.12        # Reinstall Python

# Build issues
uv build --sdist                       # Build source distribution only
uv build --wheel                       # Build wheel only
```
