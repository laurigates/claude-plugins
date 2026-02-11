---
model: haiku
created: 2025-12-16
modified: 2026-02-11
reviewed: 2025-12-16
description: Check and configure code documentation standards and generators (TSDoc, JSDoc, pydoc, rustdoc)
allowed-tools: Glob, Grep, Read, Write, Edit, Bash, AskUserQuestion, TodoWrite
argument-hint: "[--check-only] [--fix] [--level <minimal|standard|strict>] [--type <typescript|javascript|python|rust>] [--generator <typedoc|sphinx|mkdocs|rustdoc>]"
name: configure-docs
---

# /configure:docs

Check and configure code documentation standards and generators.

## When to Use This Skill

| Use this skill when... | Use another approach when... |
|------------------------|------------------------------|
| Setting up TSDoc, JSDoc, pydoc, or rustdoc standards for a project | Writing actual documentation content for functions or modules |
| Configuring a documentation generator (TypeDoc, MkDocs, Sphinx, rustdoc) | Deploying documentation to GitHub Pages (`/configure:github-pages` instead) |
| Auditing documentation coverage and lint compliance | Reviewing generated documentation for accuracy |
| Adding documentation enforcement rules to CI/CD | Editing ruff or biome configuration for non-doc rules (`/configure:linting`) |
| Migrating between documentation conventions (e.g., numpy to google style) | Setting up pre-commit hooks only (`/configure:pre-commit` instead) |

## Context

- Project root: !`pwd`
- Package files: !`find . -maxdepth 1 \( -name 'package.json' -o -name 'pyproject.toml' -o -name 'Cargo.toml' \) 2>/dev/null`
- Biome config: !`find . -maxdepth 1 -name 'biome.json' 2>/dev/null`
- TSDoc config: !`find . -maxdepth 1 \( -name 'tsdoc.json' -o -name 'typedoc.json' \) 2>/dev/null`
- Python config: !`find . -maxdepth 1 \( -name 'pyproject.toml' -o -name 'ruff.toml' -o -name '.ruff.toml' \) 2>/dev/null`
- Rust config: !`find . -maxdepth 1 \( -name 'Cargo.toml' -o -name 'clippy.toml' \) 2>/dev/null`
- Pre-commit: !`find . -maxdepth 1 -name '.pre-commit-config.yaml' 2>/dev/null`
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

## Execution

Execute this documentation standards configuration check:

### Step 1: Detect project language

Identify language(s) from file structure:

| Indicator | Language |
|-----------|----------|
| `package.json` + `tsconfig.json` | TypeScript |
| `package.json` (no tsconfig) | JavaScript |
| `pyproject.toml` or `*.py` files | Python |
| `Cargo.toml` | Rust |

For multi-language projects, configure each detected language. Allow `--type` override to focus on one.

### Step 2: Analyze current documentation state

For each detected language, check existing configuration:

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

### Step 3: Generate compliance report

Print a formatted compliance report:

```
Documentation Standards Compliance Report
=========================================
Project: [name]
Languages: [detected languages]
Enforcement Level: [minimal|standard|strict]

Linting Standards:
  TypeScript/JavaScript:
    tsdoc.json              [PASS | MISSING | N/A]
    TypeDoc configured      [PASS | MISSING | OUTDATED]
    API docs generated      [PASS | DISABLED]

  Python:
    ruff pydocstyle        [PASS | MISSING]
    convention             [google | not set]
    D rules enabled        [PASS | DISABLED]

  Rust:
    missing_docs lint      [PASS | DISABLED]
    rustdoc lints          [PASS | PARTIAL]

Documentation Generator:
  Generator type         [typedoc|mkdocs|sphinx|rustdoc]  [DETECTED | SUGGESTED]
  Config file            [config path]                     [EXISTS | MISSING]
  Build script           [command]                         [EXISTS | MISSING]
  Output directory       [docs/|site/|target/doc/]         [EXISTS | NOT BUILT]

Overall: [X issues found]

Next Steps:
  - Run `[build command]` to generate documentation locally
  - Run `/configure:github-pages` to set up deployment
```

If `--check-only`, stop here.

### Step 4: Configure documentation standards (if --fix or user confirms)

Apply configuration based on detected language. Use templates from [REFERENCE.md](REFERENCE.md):

#### TypeScript Configuration
1. Create `tsdoc.json` with schema reference
2. Install TypeDoc: `npm install --save-dev typedoc`
3. Create `typedoc.json` with entry points and output directory

#### Python Configuration
1. Update `pyproject.toml` with `[tool.ruff.lint.pydocstyle]` section
2. Set convention to `google` (or `numpy` for scientific projects)
3. Configure level-specific rules (minimal: D1 only, standard: D with convention, strict: all D rules)

#### Rust Configuration
1. Update `Cargo.toml` with `[lints.rust]` section
2. Set `missing_docs = "warn"` (standard) or `"deny"` (strict)
3. Add `[lints.rustdoc]` section for broken link detection

### Step 5: Configure documentation tests

Create tests to validate documentation compliance:

1. **TypeScript/JavaScript**: Add `docs:check` script running `typedoc --emit none`
2. **Python**: Add test file running `ruff check --select D` on source
3. **Rust**: Add `cargo doc --no-deps` and `cargo clippy -- -W missing_docs` to CI

Use test templates from [REFERENCE.md](REFERENCE.md).

### Step 6: Set up documentation generator

Auto-detect or configure the documentation site generator:

1. Check for existing generator configs (use existing if found)
2. If `--generator` provided, use specified generator
3. Otherwise, match to detected project type
4. Create config file and add build scripts

Use generator templates from [REFERENCE.md](REFERENCE.md).

### Step 7: Add pre-commit integration

If `.pre-commit-config.yaml` exists, add documentation hooks for the detected language. Use hook templates from [REFERENCE.md](REFERENCE.md).

### Step 8: Update standards tracking

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

For detailed configuration templates, see [REFERENCE.md](REFERENCE.md).

## Output

Provide:
1. Compliance report with per-language status
2. List of changes made (if --fix) or proposed (if interactive)
3. Instructions for running documentation tests
4. Next steps for improving coverage

## Agentic Optimizations

| Context | Command |
|---------|---------|
| Quick compliance check | `/configure:docs --check-only` |
| Auto-fix all issues | `/configure:docs --fix` |
| Check TSDoc validity | `typedoc --emit none 2>&1 | head -20` |
| Check Python docstrings | `ruff check --select D --output-format=github` |
| Check Rust doc lints | `cargo doc --no-deps 2>&1 | head -20` |
| Build docs (MkDocs) | `mkdocs build --strict 2>&1 | tail -5` |

## See Also

- `/configure:github-pages` - Set up GitHub Pages deployment
- `/configure:all` - Run all compliance checks
- `/configure:status` - Quick compliance overview
- `/configure:pre-commit` - Pre-commit hook configuration
- **biome-tooling** skill for TypeScript/JavaScript
- **ruff-linting** skill for Python
- **rust-development** skill for Rust
