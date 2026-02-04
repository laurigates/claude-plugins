---
model: haiku
created: 2025-12-16
modified: 2025-12-16
reviewed: 2025-12-16
description: Check and configure code documentation standards and generators (TSDoc, JSDoc, pydoc, rustdoc)
allowed-tools: Glob, Grep, Read, Write, Edit, Bash, AskUserQuestion, TodoWrite
argument-hint: "[--check-only] [--fix] [--level <minimal|standard|strict>] [--type <typescript|javascript|python|rust>] [--generator <typedoc|sphinx|mkdocs|rustdoc>]"
---

## Context

- Project root: !`pwd`
- Package files: !`ls -la package.json pyproject.toml Cargo.toml 2>/dev/null`
- Biome config: !`ls -la biome.json 2>/dev/null`
- TSDoc config: !`ls -la tsdoc.json typedoc.json 2>/dev/null`
- Python config: !`ls -la pyproject.toml ruff.toml .ruff.toml 2>/dev/null`
- Rust config: !`ls -la Cargo.toml clippy.toml 2>/dev/null`
- Pre-commit: !`ls -la .pre-commit-config.yaml 2>/dev/null`
- Doc generators: !`find . -maxdepth 1 \( -name 'mkdocs.yml' -o -name 'docusaurus.config.*' \) 2>/dev/null`
- Docs directory: !`find . -maxdepth 1 -type d -name 'docs' 2>/dev/null`

## Parameters

Parse from command arguments:

- `--check-only`: Report compliance status without modifications (CI/CD mode)
- `--fix`: Apply fixes automatically without prompting
- `--level <minimal|standard|strict>`: Documentation enforcement level (default: standard)
- `--type <typescript|javascript|python|rust>`: Override language detection
- `--generator <typedoc|sphinx|mkdocs|rustdoc>`: Override documentation generator detection

**Enforcement Levels:**
- `minimal`: Syntax validation only (valid doc comments)
- `standard`: Public API documentation required (recommended)
- `strict`: All items documented, including private

**Generator Auto-Detection:**
| Project Type | Default Generator |
|--------------|-------------------|
| TypeScript/JavaScript | TypeDoc |
| Python | MkDocs (simpler) or Sphinx |
| Rust | rustdoc |
| Multi-language/Other | MkDocs |

## Your Task

Configure documentation standards for the detected project language(s), including linter rules and compliance tests.

### Phase 1: Language Detection

Detect project language(s) from file structure:

| Indicator | Language |
|-----------|----------|
| `package.json` + `tsconfig.json` | TypeScript |
| `package.json` (no tsconfig) | JavaScript |
| `pyproject.toml` or `*.py` files | Python |
| `Cargo.toml` | Rust |

**Multi-language projects:** Configure each detected language. Allow `--type` override to focus on one.

### Phase 2: Current State Analysis

For each detected language, check existing documentation configuration:

**TypeScript/JavaScript:**
- [ ] `tsdoc.json` exists (TypeScript)
- [ ] Biome configured with organize imports
- [ ] TypeDoc or API Extractor configured for documentation generation

**Python:**
- [ ] `pyproject.toml` has `[tool.ruff.lint.pydocstyle]` section
- [ ] Convention specified (google, numpy, pep257)
- [ ] D rules enabled in ruff lint select

**Rust:**
- [ ] `Cargo.toml` has `[lints.rust]` section
- [ ] `missing_docs` lint configured
- [ ] `[lints.rustdoc]` section for rustdoc-specific lints

### Phase 3: Compliance Report

Generate formatted compliance report:

```
Documentation Standards Compliance Report
=========================================
Project: [name]
Languages: [detected languages]
Enforcement Level: [minimal|standard|strict]

TypeScript/JavaScript:
  tsdoc.json              [✅ PASS | ❌ MISSING | ⏭️ N/A]
  TypeDoc configured      [✅ PASS | ❌ MISSING | ⚠️ OUTDATED]
  API docs generated      [✅ PASS | ❌ DISABLED]

Python:
  ruff pydocstyle        [✅ PASS | ❌ MISSING]
  convention             [✅ google | ⚠️ not set]
  D rules enabled        [✅ PASS | ❌ DISABLED]

Rust:
  missing_docs lint      [✅ PASS | ❌ DISABLED]
  rustdoc lints          [✅ PASS | ⚠️ PARTIAL]

Overall: [X issues found]
```

### Phase 4: Configuration (if --fix or user confirms)

#### TypeScript Configuration

**Create/update `tsdoc.json`:**
```json
{
  "$schema": "https://developer.microsoft.com/json-schemas/tsdoc/v0/tsdoc.schema.json"
}
```

**Install TypeDoc for API documentation:**
```bash
npm install --save-dev typedoc
# or
bun add --dev typedoc
```

**Configure `typedoc.json`:**
```json
{
  "$schema": "https://typedoc.org/schema.json",
  "entryPoints": ["./src"],
  "entryPointStrategy": "expand",
  "out": "docs/api",
  "name": "PROJECT_NAME",
  "includeVersion": true,
  "readme": "README.md"
}
```

#### Python Configuration

**Update `pyproject.toml`:**
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

#### Rust Configuration

**Update `Cargo.toml`:**
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

### Phase 5: Test Configuration

Create tests to validate documentation compliance.

#### TypeScript/JavaScript Tests

**Add npm script to `package.json`:**
```json
{
  "scripts": {
    "docs:build": "typedoc",
    "docs:check": "typedoc --emit none"
  }
}
```

**Create test file `tests/docs.test.ts`:**
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

#### Python Tests

**Add test file `tests/test_docs.py`:**
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

#### Rust Tests

**Add test in `tests/docs.rs`:**
```rust
//! Documentation compliance tests.

#[test]
fn verify_docs_compile() {
    // Run rustdoc in test mode to verify doc examples compile
    // This is automatically done by `cargo test --doc`
}
```

**Add CI check in `.github/workflows/docs.yml`:**
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

### Phase 6: Pre-commit Integration

If `.pre-commit-config.yaml` exists, add documentation hooks:

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

### Phase 7: Standards Tracking

Update `.project-standards.yaml`:

```yaml
standards_version: "2025.1"
project_type: "[detected]"
last_configured: "[timestamp]"
components:
  docs: "2025.1"
  docs_level: "[minimal|standard|strict]"
  docs_languages: ["typescript", "python", "rust"]
```

### Phase 8: Documentation Generator Setup

Auto-detect and configure the appropriate static site generator for publishing documentation.

**Detection Logic:**
1. Check for existing generator configs (use existing if found)
2. If `--generator` provided, use specified generator
3. Otherwise, match to detected project type

#### TypeScript/JavaScript: TypeDoc

**Install TypeDoc:**
```bash
npm install --save-dev typedoc
# or
bun add --dev typedoc
```

**Create `typedoc.json`:**
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

#### Python: MkDocs (Default)

**Install MkDocs with Material theme:**
```bash
uv add --group docs mkdocs mkdocs-material mkdocstrings[python]
```

**Create `mkdocs.yml`:**
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

#### Python: Sphinx (Alternative)

**Install Sphinx:**
```bash
uv add --group docs sphinx sphinx-rtd-theme sphinx-autodoc-typehints myst-parser
```

**Create `docs/conf.py`:**
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

#### Rust: rustdoc

**Update `Cargo.toml`:**
```toml
[package.metadata.docs.rs]
all-features = true
rustdoc-args = ["--cfg", "docsrs"]

[lints.rustdoc]
broken_intra_doc_links = "warn"
missing_crate_level_docs = "warn"
```

### Phase 9: Build Scripts

Add documentation build commands to the project.

#### TypeScript/JavaScript

**Add to `package.json`:**
```json
{
  "scripts": {
    "docs:build": "typedoc",
    "docs:serve": "npx serve docs"
  }
}
```

#### Python (MkDocs)

**Add to `pyproject.toml`:**
```toml
[project.scripts]
# Or use uv run directly:
# uv run mkdocs build
# uv run mkdocs serve
```

**Build command:** `mkdocs build` (outputs to `site/`)
**Serve command:** `mkdocs serve`

#### Python (Sphinx)

**Create `docs/Makefile`:**
```makefile
SPHINXBUILD = sphinx-build
SOURCEDIR = .
BUILDDIR = _build

html:
	$(SPHINXBUILD) -b html $(SOURCEDIR) $(BUILDDIR)/html
```

**Build command:** `make -C docs html` (outputs to `docs/_build/html/`)

#### Rust

**Build command:** `cargo doc --no-deps` (outputs to `target/doc/`)

### Phase 10: Updated Compliance Report

Add generator status to the compliance report:

```
Documentation Standards Compliance Report
=========================================
Project: [name]
Languages: [detected languages]
Enforcement Level: [minimal|standard|strict]

Linting Standards:
  TypeScript/JavaScript:
    tsdoc.json              [✅ PASS | ❌ MISSING | ⏭️ N/A]
    TypeDoc configured      [✅ PASS | ❌ MISSING | ⚠️ OUTDATED]
    API docs generated      [✅ PASS | ❌ DISABLED]

  Python:
    ruff pydocstyle        [✅ PASS | ❌ MISSING]
    convention             [✅ google | ⚠️ not set]
    D rules enabled        [✅ PASS | ❌ DISABLED]

  Rust:
    missing_docs lint      [✅ PASS | ❌ DISABLED]
    rustdoc lints          [✅ PASS | ⚠️ PARTIAL]

Documentation Generator:
  Generator type         [typedoc|mkdocs|sphinx|rustdoc]  [✅ DETECTED | ⚠️ SUGGESTED]
  Config file            [config path]                     [✅ EXISTS | ❌ MISSING]
  Build script           [command]                         [✅ EXISTS | ❌ MISSING]
  Output directory       [docs/|site/|target/doc/]         [✅ EXISTS | ⏭️ NOT BUILT]

Overall: [X issues found]

Next Steps:
  - Run `[build command]` to generate documentation locally
  - Run `/configure:github-pages` to set up deployment
```

## Output

Provide:
1. Compliance report with per-language status
2. List of changes made (if --fix) or proposed (if interactive)
3. Instructions for running documentation tests
4. Next steps for improving coverage

## See Also

- `/configure:github-pages` - Set up GitHub Pages deployment
- `/configure:all` - Run all compliance checks
- `/configure:status` - Quick compliance overview
- `/configure:pre-commit` - Pre-commit hook configuration
- **biome-tooling** skill for TypeScript/JavaScript
- **ruff-linting** skill for Python
- **rust-development** skill for Rust
