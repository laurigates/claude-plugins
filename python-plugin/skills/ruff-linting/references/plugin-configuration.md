# ruff check — Plugin Configuration

Open this when configuring a specific ruff plugin's options (isort,
flake8-quotes, pydocstyle, pylint) in `pyproject.toml`.

## Plugin Configuration

### isort (Import Sorting)
```toml
[tool.ruff.lint.isort]
combine-as-imports = true
known-first-party = ["myapp"]
section-order = ["future", "standard-library", "third-party", "first-party", "local-folder"]
```

### flake8-quotes
```toml
[tool.ruff.lint.flake8-quotes]
docstring-quotes = "double"
inline-quotes = "single"
multiline-quotes = "double"
```

### pydocstyle
```toml
[tool.ruff.lint.pydocstyle]
convention = "google"  # or "numpy", "pep257"
```

### pylint
```toml
[tool.ruff.lint.pylint]
max-args = 10
max-branches = 15
max-returns = 8
max-statements = 60
```
