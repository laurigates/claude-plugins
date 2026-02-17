# Documentation Standards Reference

Configuration templates for documentation linting, generators, and tests.

## TypeScript Configuration

### `tsdoc.json`

```json
{
  "$schema": "https://developer.microsoft.com/json-schemas/tsdoc/v0/tsdoc.schema.json"
}
```

### TypeDoc Installation

```bash
npm install --save-dev typedoc
# or
bun add --dev typedoc
```

### `typedoc.json`

```json
{
  "$schema": "https://typedoc.org/schema.json",
  "entryPoints": ["./src"],
  "entryPointStrategy": "expand",
  "out": "docs/api",
  "name": "PROJECT_NAME",
  "includeVersion": true,
  "readme": "README.md",
  "plugin": ["typedoc-plugin-markdown"]
}
```

### Package.json Scripts

```json
{
  "scripts": {
    "docs:build": "typedoc",
    "docs:check": "typedoc --emit none",
    "docs:serve": "npx serve docs"
  }
}
```

### Documentation Test (`tests/docs.test.ts`)

```typescript
import { execSync } from 'child_process';
import { describe, it, expect } from 'vitest';

describe('Documentation Compliance', () => {
  it('should generate API documentation without errors', () => {
    expect(() => {
      execSync('npm run docs:check', { stdio: 'pipe' });
    }).not.toThrow();
  });
});
```

## Python Configuration

### Ruff Pydocstyle (`pyproject.toml`)

```toml
[tool.ruff.lint]
select = [
    "E",    # pycodestyle errors
    "F",    # pyflakes
    "D",    # pydocstyle
]

[tool.ruff.lint.pydocstyle]
convention = "google"  # or "numpy" for scientific projects
```

**Level-specific configuration:**

| Level | Rules |
|-------|-------|
| minimal | `D1` (missing docstrings warning) |
| standard | `D` with convention, ignore D107 (init), D203 |
| strict | All D rules, no ignores |

### MkDocs Installation

```bash
uv add --group docs mkdocs mkdocs-material mkdocstrings[python]
```

### `mkdocs.yml`

```yaml
site_name: PROJECT_NAME
site_description: Project description
repo_url: https://github.com/OWNER/REPO

theme:
  name: material
  features:
    - navigation.tabs
    - navigation.sections
    - search.suggest

plugins:
  - search
  - mkdocstrings:
      handlers:
        python:
          options:
            show_source: true
            show_root_heading: true

nav:
  - Home: index.md
  - API Reference: api/
```

### Sphinx Installation (Alternative)

```bash
uv add --group docs sphinx sphinx-rtd-theme sphinx-autodoc-typehints myst-parser
```

### `docs/conf.py`

```python
project = 'PROJECT_NAME'
extensions = [
    'sphinx.ext.autodoc',
    'sphinx.ext.napoleon',
    'sphinx_autodoc_typehints',
    'myst_parser',
]
html_theme = 'sphinx_rtd_theme'
```

### Documentation Test (`tests/test_docs.py`)

```python
"""Documentation compliance tests."""
import subprocess
import pytest


def test_pydocstyle_compliance():
    """Verify all modules have proper docstrings."""
    result = subprocess.run(
        ["ruff", "check", "--select", "D", "--output-format", "json", "src/"],
        capture_output=True,
        text=True,
    )
    assert result.returncode == 0, f"Documentation violations found:\n{result.stdout}"


def test_public_api_documented():
    """Verify public API has docstrings."""
    result = subprocess.run(
        ["ruff", "check", "--select", "D1", "src/"],
        capture_output=True,
        text=True,
    )
    assert result.returncode == 0, f"Missing public docstrings:\n{result.stdout}"
```

## Rust Configuration

### `Cargo.toml` Lints

```toml
[lints.rust]
missing_docs = "warn"  # standard level
# missing_docs = "deny"  # strict level

[lints.rustdoc]
broken_intra_doc_links = "warn"
missing_crate_level_docs = "warn"
```

**For strict level, add clippy lint:**

```toml
[lints.clippy]
missing_docs_in_private_items = "warn"
```

### `Cargo.toml` Docs.rs Metadata

```toml
[package.metadata.docs.rs]
all-features = true
rustdoc-args = ["--cfg", "docsrs"]
```

### CI Check (`.github/workflows/docs.yml`)

```yaml
name: Documentation Check
on: [push, pull_request]
jobs:
  docs:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: Check documentation
        run: |
          cargo doc --no-deps
          cargo clippy -- -W missing_docs
```

## Pre-commit Integration

```yaml
repos:
  # Python
  - repo: https://github.com/astral-sh/ruff-pre-commit
    rev: v0.8.2
    hooks:
      - id: ruff
        args: [--select, D, --fix]

  # Rust (if not already present)
  - repo: local
    hooks:
      - id: cargo-clippy-docs
        name: clippy docs
        entry: cargo clippy -- -W missing_docs
        language: system
        types: [rust]
        pass_filenames: false
```

## Build Commands Summary

| Language | Build Command | Output Directory |
|----------|--------------|-----------------|
| TypeScript | `typedoc` | `docs/api/` |
| Python (MkDocs) | `mkdocs build` | `site/` |
| Python (Sphinx) | `make -C docs html` | `docs/_build/html/` |
| Rust | `cargo doc --no-deps` | `target/doc/` |
