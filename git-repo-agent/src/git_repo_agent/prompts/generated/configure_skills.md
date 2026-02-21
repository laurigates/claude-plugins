## configure-linting

# /configure:linting

Check and configure linting tools against modern best practices.


## Execution

Execute this linting configuration check:


### Step 1: Detect project language and existing linters

Read the context values above and determine:

| Indicator | Language | Detected Linter |
|-----------|----------|-----------------|
| `biome.json` | JavaScript/TypeScript | Biome |
| `pyproject.toml` [tool.ruff] | Python | Ruff |
| `.flake8` | Python | Flake8 (legacy) |
| `Cargo.toml` [lints.clippy] | Rust | Clippy |

If `--linter` flag is set, use that linter regardless of detection.


### Step 2: Verify latest tool versions

Use WebSearch or WebFetch to check current versions:

1. **Biome**: Check [biomejs.dev](https://biomejs.dev/) or [GitHub releases](https://github.com/biomejs/biome/releases)
2. **Ruff**: Check [docs.astral.sh/ruff](https://docs.astral.sh/ruff/) or [GitHub releases](https://github.com/astral-sh/ruff/releases)
3. **Clippy**: Check [Rust releases](https://releases.rs/)


### Step 3: Analyze current linter configuration

For each detected linter, check configuration completeness:

**Biome (for JS/TS):**
- Config file exists with linter rules
- Formatter configured
- File patterns and ignores set
- Recommended rules enabled

**Ruff (for Python):**
- `pyproject.toml` has `[tool.ruff]` section
- Rules selected (E, F, I, N, etc.)
- Line length and target Python version set

**Clippy:**
- `Cargo.toml` has `[lints.clippy]` section
- Pedantic lints enabled
- Workspace-level lints if applicable


### Step 4: Generate compliance report

Print a compliance report covering:
- Config file status (exists / missing)
- Linter enabled status
- Rules configuration (recommended / minimal / missing)
- Formatter integration
- Ignore patterns
- Lint scripts in package.json / Makefile
- Pre-commit hook integration
- CI/CD check integration

End with overall issue count and recommendations.

If `--check-only` is set, stop here.


### Step 5: Configure linting (if --fix or user confirms)

Apply configuration using templates from .

**For Biome (JS/TS):**
1. Install Biome as dev dependency
2. Create `biome.json` with recommended rules
3. Add npm scripts (`lint`, `lint:fix`, `format`, `check`)

**For Ruff (Python):**
1. Install Ruff via `uv add --group dev ruff`
2. Add `[tool.ruff]` section to `pyproject.toml`
3. Configure rules, line length, target version

**For Clippy (Rust):**
1. Add `[lints.clippy]` section to `Cargo.toml`
2. Enable pedantic lints
3. Configure workspace-level lints if applicable

If legacy linters are detected (ESLint, Flake8, etc.), offer migration. See migration guides in .


### Step 6: Configure pre-commit and CI integration

1. Add linter pre-commit hook to `.pre-commit-config.yaml`
2. Add linter CI check to GitHub Actions workflow
3. Use templates from 


### Step 7: Update standards tracking

Update `.project-standards.yaml`:

```yaml
components:
  linting: "2025.1"
  linting_tool: "[biome|ruff|clippy]"
  linting_pre_commit: true
  linting_ci: true
```


### Step 8: Print final compliance report

Print a summary of all changes applied, scripts added, integrations configured, and next steps for the user.

For detailed configuration templates, migration guides, and CI integration patterns, see .


## Examples

```bash

# Check compliance and offer fixes
/configure:linting


# Check only, no modifications
/configure:linting --check-only


# Auto-fix and migrate to Biome
/configure:linting --fix --linter biome
```


## Error Handling

- **Multiple linters detected**: Warn about conflict, suggest migration
- **No package manager found**: Cannot install linter, error
- **Invalid configuration**: Report parse error, offer to replace with template
- **Missing dependencies**: Offer to install required packages


# Linting Configuration Reference

Detailed configuration templates, migration guides, and integration patterns for linting tools.


## Biome Configuration (JavaScript/TypeScript)


### Installation

```bash
npm install --save-dev @biomejs/biome

# or
bun add --dev @biomejs/biome
```


### biome.json Template

```json
{
  "$schema": "https://biomejs.dev/schemas/1.9.4/schema.json",
  "vcs": {
    "enabled": true,
    "clientKind": "git",
    "useIgnoreFile": true
  },
  "files": {
    "include": ["src/**/*.ts", "src/**/*.tsx", "src/**/*.js", "src/**/*.jsx"],
    "ignore": [
      "node_modules",
      "dist",
      "build",
      ".next",
      "coverage",
      "*.config.js",
      "*.config.ts"
    ]
  },
  "formatter": {
    "enabled": true,
    "formatWithErrors": false,
    "indentStyle": "space",
    "indentWidth": 2,
    "lineWidth": 100
  },
  "linter": {
    "enabled": true,
    "rules": {
      "recommended": true,
      "suspicious": {
        "noExplicitAny": "warn",
        "noConsoleLog": "warn"
      },
      "complexity": {
        "noExcessiveCognitiveComplexity": "warn",
        "noForEach": "off"
      },
      "style": {
        "useConst": "error",
        "useTemplate": "warn"
      },
      "correctness": {
        "noUnusedVariables": "error"
      }
    }
  },
  "organizeImports": {
    "enabled": true
  },
  "javascript": {
    "formatter": {
      "quoteStyle": "single",
      "semicolons": "always",
      "trailingCommas": "all",
      "arrowParentheses": "always"
    }
  },
  "json": {
    "formatter": {
      "enabled": true
    }
  }
}
```


### npm Scripts

```json
{
  "scripts": {
    "lint": "biome check .",
    "lint:fix": "biome check --write .",
    "format": "biome format --write .",
    "check": "biome ci ."
  }
}
```


## Ruff Configuration (Python)


### Installation

```bash
uv add --group dev ruff
```


### pyproject.toml Template

```toml
[tool.ruff]

# Target Python version
target-version = "py312"


# Line length
line-length = 100


# Exclude directories
exclude = [
    ".git",
    ".venv",
    "__pycache__",
    "dist",
    "build",
    "*.egg-info",
]

[tool.ruff.lint]

# Rule selection
select = [
    "E",      # pycodestyle errors
    "F",      # pyflakes
    "I",      # isort
    "N",      # pep8-naming
    "UP",     # pyupgrade
    "B",      # flake8-bugbear
    "C4",     # flake8-comprehensions
    "SIM",    # flake8-simplify
    "TCH",    # flake8-type-checking
    "PTH",    # flake8-use-pathlib
    "RUF",    # Ruff-specific rules
]


# Rules to ignore
ignore = [
    "E501",   # Line too long (handled by formatter)
    "B008",   # Function call in default argument
]


# Per-file ignores
[tool.ruff.lint.per-file-ignores]
"__init__.py" = ["F401"]  # Unused imports
"tests/**/*.py" = ["S101"]  # Use of assert

[tool.ruff.lint.isort]
known-first-party = ["your_package"]
force-sort-within-sections = true

[tool.ruff.lint.mccabe]
max-complexity = 10

[tool.ruff.format]

# Formatter options
quote-style = "double"
indent-style = "space"
line-ending = "auto"
```


## Clippy Configuration (Rust)


### Cargo.toml Template

```toml
[lints.clippy]

# Enable pedantic lints
pedantic = { level = "warn", priority = -1 }


# Specific lints to deny
all = "warn"
correctness = "deny"
suspicious = "deny"
complexity = "warn"
perf = "warn"
style = "warn"


# Allow some pedantic lints that are too noisy
module-name-repetitions = "allow"
missing-errors-doc = "allow"
missing-panics-doc = "allow"


# Deny specific dangerous patterns
unwrap-used = "deny"
expect-used = "deny"
panic = "deny"

[lints.rust]
unsafe-code = "deny"
missing-docs = "warn"
```


### Workspace Configuration

```toml
[workspace.lints.clippy]
pedantic = { level = "warn", priority = -1 }
all = "warn"

[workspace.lints.rust]
unsafe-code = "deny"
```


### Run Command

```bash
cargo clippy --all-targets --all-features -- -D warnings
```


## Migration Guides


### Flake8/isort/black to Ruff

1. Install Ruff: `uv add --group dev ruff`
2. Configure in `pyproject.toml` (see Ruff template above)
3. Remove old tools: `uv remove flake8 isort black pyupgrade`
4. Remove old config files: `rm .flake8 .isort.cfg`
5. Update pre-commit hooks (see below)


### ESLint to Biome

1. Install Biome: `bun add --dev @biomejs/biome`
2. Create `biome.json` (see template above)
3. Remove ESLint: `bun remove eslint @typescript-eslint/parser @typescript-eslint/eslint-plugin`
4. Remove config files: `rm .eslintrc* .eslintignore`
5. Update npm scripts and pre-commit hooks


## Pre-commit Integration


### Biome

```yaml
repos:
  - repo: https://github.com/biomejs/pre-commit
    rev: v0.4.0
    hooks:
      - id: biome-check
        additional_dependencies: ["@biomejs/biome@1.9.4"]
```


### Ruff

```yaml
repos:
  - repo: https://github.com/astral-sh/ruff-pre-commit
    rev: v0.8.4
    hooks:
      - id: ruff
        args: [--fix]
      - id: ruff-format
```


### Clippy

```yaml
repos:
  - repo: local
    hooks:
      - id: clippy
        name: clippy
        entry: cargo clippy --all-targets --all-features -- -D warnings
        language: system
        types: [rust]
        pass_filenames: false
```


## CI/CD Integration


### GitHub Actions - Biome

```yaml
- name: Run Biome
  run: npx @biomejs/biome ci .
```


### GitHub Actions - Ruff

```yaml
- name: Run Ruff
  run: |
    uv run ruff check .
    uv run ruff format --check .
```


### GitHub Actions - Clippy

```yaml
- name: Run Clippy
  run: cargo clippy --all-targets --all-features -- -D warnings
```


## Compliance Report Template

```
Linting Configuration Compliance Report
========================================
Project: [name]
Language: [TypeScript | Python | Rust]
Linter: [Biome 1.x | Ruff 0.x | Clippy 1.x]

Configuration:
  Config file             biome.json                 [EXISTS | MISSING]
  Linter enabled          true                       [ENABLED | DISABLED]
  Rules configured        recommended + custom       [CONFIGURED | MINIMAL]
  Formatter integrated    biome format               [CONFIGURED | SEPARATE]
  Ignore patterns         node_modules, dist         [CONFIGURED | INCOMPLETE]

Rules:
  Recommended             enabled                    [ENABLED | DISABLED]
  Suspicious              enabled                    [ENABLED | DISABLED]
  Complexity              enabled                    [ENABLED | DISABLED]
  Performance             enabled                    [ENABLED | N/A]
  Style                   enabled                    [ENABLED | N/A]

Scripts:
  lint command            package.json scripts       [CONFIGURED | MISSING]
  lint:fix                package.json scripts       [CONFIGURED | MISSING]

Integration:
  Pre-commit hook         .pre-commit-config.yaml    [CONFIGURED | MISSING]
  CI/CD check             .github/workflows/         [CONFIGURED | MISSING]

Overall: [X issues found]
```

---

## configure-formatting

# /configure:formatting

Check and configure code formatting tools against modern best practices.


## Version Checking

**CRITICAL**: Before flagging outdated formatters, verify latest releases using WebSearch or WebFetch:

1. **Biome**: Check [biomejs.dev](https://biomejs.dev/) or [GitHub releases](https://github.com/biomejs/biome/releases)
2. **Prettier**: Check [prettier.io](https://prettier.io/) or [npm](https://www.npmjs.com/package/prettier)
3. **Ruff**: Check [docs.astral.sh/ruff](https://docs.astral.sh/ruff/) or [GitHub releases](https://github.com/astral-sh/ruff/releases)
4. **rustfmt**: Bundled with Rust toolchain - check [Rust releases](https://releases.rs/)


## Execution

Execute this code formatting configuration workflow:


### Step 1: Detect project languages and existing formatters

Check for language indicators and formatter configurations:

| Indicator | Language | Detected Formatter |
|-----------|----------|-------------------|
| `biome.json` with formatter | JavaScript/TypeScript | Biome |
| `.prettierrc.*` | JavaScript/TypeScript | Prettier |
| `pyproject.toml` [tool.ruff.format] | Python | Ruff |
| `pyproject.toml` [tool.black] | Python | Black (legacy) |
| `rustfmt.toml` or `.rustfmt.toml` | Rust | rustfmt |

**Modern formatting preferences:**
- **JavaScript/TypeScript**: Biome (preferred) or Prettier
- **Python**: Ruff format (replaces Black)
- **Rust**: rustfmt (standard)


### Step 2: Analyze current formatter configuration

For each detected formatter, check configuration completeness:
1. Config file exists with required settings (indent, line width, quotes, etc.)
2. Ignore patterns configured
3. Format scripts defined in package.json / pyproject.toml
4. Pre-commit hook configured
5. CI/CD check configured


### Step 3: Generate compliance report

Print a formatted compliance report:

```
Code Formatting Compliance Report
==================================
Project: [name]
Language: [detected]
Formatter: [detected]

Configuration:  [status per check]
Format Options: [status per check]
Scripts:        [status per check]
Integration:    [status per check]

Overall: [X issues found]
Recommendations: [list specific fixes]
```

If `--check-only`, stop here.


### Step 4: Install and configure formatter (if --fix or user confirms)

Based on detected language and formatter preference, install and configure. Use configuration templates from .

1. Install formatter package
2. Create configuration file (biome.json, .prettierrc.json, pyproject.toml section, rustfmt.toml)
3. Add format scripts to package.json or Makefile/justfile
4. Create ignore file if needed (.prettierignore)


### Step 5: Create EditorConfig integration

Create or update `.editorconfig` with settings matching the formatter configuration.


### Step 6: Handle migrations (if applicable)

If legacy formatter detected (Prettier -> Biome, Black -> Ruff):
1. Import existing configuration
2. Install new formatter
3. Remove old formatter
4. Update scripts
5. Update pre-commit hooks

Use migration guides from .


### Step 7: Configure pre-commit hooks

Add formatter to `.pre-commit-config.yaml` using the appropriate hook repository.


### Step 8: Configure CI/CD integration

Add format check step to GitHub Actions workflow.


### Step 9: Configure editor integration

Create or update `.vscode/settings.json` with format-on-save and `.vscode/extensions.json` with formatter extension.


### Step 10: Update standards tracking

Update `.project-standards.yaml`:

```yaml
components:
  formatting: "2025.1"
  formatting_tool: "[biome|prettier|ruff|rustfmt]"
  formatting_pre_commit: true
  formatting_ci: true
```


### Step 11: Print completion report

Print a summary of changes made, scripts added, and next steps (run format, verify CI, enable format-on-save).

For detailed configuration templates, migration guides, and pre-commit configurations, see .


## Examples

```bash

# Check compliance and offer fixes
/configure:formatting


# Check only, no modifications
/configure:formatting --check-only


# Auto-fix and migrate to Biome
/configure:formatting --fix --formatter biome
```


## Error Handling

- **Multiple formatters detected**: Warn about conflict, suggest migration
- **No package manager found**: Cannot install formatter, error
- **Invalid configuration**: Report parse error, offer to replace with template
- **Formatting conflicts**: Report files that would be reformatted


# configure-formatting Reference

Configuration templates, migration guides, and pre-commit configurations for code formatters.


## Biome Configuration (Recommended for JS/TS)


### Install

```bash
npm install --save-dev @biomejs/biome

# or
bun add --dev @biomejs/biome
```


### `biome.json`

```json
{
  "$schema": "https://biomejs.dev/schemas/1.9.4/schema.json",
  "formatter": {
    "enabled": true,
    "formatWithErrors": false,
    "indentStyle": "space",
    "indentWidth": 2,
    "lineWidth": 100,
    "lineEnding": "lf"
  },
  "javascript": {
    "formatter": {
      "quoteStyle": "single",
      "semicolons": "always",
      "trailingCommas": "all",
      "arrowParentheses": "always",
      "bracketSpacing": true,
      "jsxQuoteStyle": "double"
    }
  },
  "json": {
    "formatter": {
      "enabled": true,
      "indentWidth": 2
    }
  },
  "files": {
    "include": ["src/**/*.ts", "src/**/*.tsx", "src/**/*.js", "src/**/*.jsx", "*.json"],
    "ignore": [
      "node_modules",
      "dist",
      "build",
      ".next",
      "coverage",
      "*.min.js"
    ]
  }
}
```


### package.json Scripts

```json
{
  "scripts": {
    "format": "biome format --write .",
    "format:check": "biome format .",
    "lint:format": "biome check --write ."
  }
}
```


## Prettier Configuration (Alternative for JS/TS)


### Install

```bash
npm install --save-dev prettier

# or
bun add --dev prettier
```


### `.prettierrc.json`

```json
{
  "printWidth": 100,
  "tabWidth": 2,
  "useTabs": false,
  "semi": true,
  "singleQuote": true,
  "quoteProps": "as-needed",
  "jsxSingleQuote": false,
  "trailingComma": "all",
  "bracketSpacing": true,
  "bracketSameLine": false,
  "arrowParens": "always",
  "endOfLine": "lf",
  "embeddedLanguageFormatting": "auto"
}
```


### `.prettierignore`

```
node_modules
dist
build
.next
coverage
*.min.js
*.min.css
package-lock.json
pnpm-lock.yaml
```


### package.json Scripts

```json
{
  "scripts": {
    "format": "prettier --write .",
    "format:check": "prettier --check ."
  }
}
```


## Ruff Format Configuration (Recommended for Python)


### Install

```bash
uv add --group dev ruff
```


### `pyproject.toml`

```toml
[tool.ruff.format]
quote-style = "double"
indent-style = "space"
line-ending = "auto"
skip-magic-trailing-comma = false
docstring-code-format = true
docstring-code-line-length = 72
preview = false

[tool.ruff]
line-length = 100
exclude = [
    ".git",
    ".venv",
    "__pycache__",
    "dist",
    "build",
]
```


### Run

```bash
uv run ruff format .
```


## Black Configuration (Alternative for Python)


### Install

```bash
uv add --group dev black
```


### `pyproject.toml`

```toml
[tool.black]
line-length = 100
target-version = ['py312']
include = '\.pyi?$'
extend-exclude = '''
/(
  \.eggs
  | \.git
  | \.venv
  | dist
  | build
)/
'''
```


## rustfmt Configuration (Rust)


### `rustfmt.toml`

```toml
edition = "2021"
max_width = 100
tab_spaces = 4
hard_tabs = false
newline_style = "Unix"
use_small_heuristics = "Default"
reorder_imports = true
reorder_modules = true
remove_nested_parens = true
format_code_in_doc_comments = true
normalize_comments = true
wrap_comments = true
format_strings = true
format_macro_bodies = true
format_macro_matchers = true
imports_granularity = "Crate"
group_imports = "StdExternalCrate"
```


### Run

```bash
cargo fmt --all
```


## EditorConfig Template

```ini
root = true

[*]
charset = utf-8
end_of_line = lf
insert_final_newline = true
trim_trailing_whitespace = true

[*.{js,jsx,ts,tsx,json,jsonc}]
indent_style = space
indent_size = 2
max_line_length = 100

[*.py]
indent_style = space
indent_size = 4
max_line_length = 100

[*.rs]
indent_style = space
indent_size = 4
max_line_length = 100

[*.{yml,yaml}]
indent_style = space
indent_size = 2

[*.md]
trim_trailing_whitespace = false
max_line_length = off

[Makefile]
indent_style = tab
```


## Migration Guides


### Prettier to Biome

```bash

# Step 1: Install Biome
npm install --save-dev @biomejs/biome


# Step 2: Import Prettier config
npx @biomejs/biome migrate prettier --write


# Step 3: Review and adjust biome.json


# Step 4: Remove Prettier
npm uninstall prettier
rm .prettierrc.* prettier.config.* .prettierignore


# Step 5: Update scripts in package.json
```


### Black to Ruff Format

```bash

# Step 1: Install Ruff
uv add --group dev ruff


# Step 2: Configure [tool.ruff.format] in pyproject.toml


# Step 3: Format codebase
uv run ruff format .


# Step 4: Remove Black
uv remove black
```


## Pre-commit Hooks


### Biome

```yaml
repos:
  - repo: https://github.com/biomejs/pre-commit
    rev: v0.4.0
    hooks:
      - id: biome-check
        additional_dependencies: ["@biomejs/biome@1.9.4"]
```


### Prettier

```yaml
repos:
  - repo: https://github.com/pre-commit/mirrors-prettier
    rev: v4.0.0-alpha.8
    hooks:
      - id: prettier
        types_or: [javascript, jsx, ts, tsx, json, yaml, markdown]
```


### Ruff Format

```yaml
repos:
  - repo: https://github.com/astral-sh/ruff-pre-commit
    rev: v0.8.4
    hooks:
      - id: ruff-format
```


### rustfmt

```yaml
repos:
  - repo: https://github.com/doublify/pre-commit-rust
    rev: v1.0
    hooks:
      - id: fmt
```


## CI/CD Integration


### GitHub Actions - Biome

```yaml
- name: Check formatting
  run: npx @biomejs/biome format .
```


### GitHub Actions - Prettier

```yaml
- name: Check formatting
  run: npm run format:check
```


### GitHub Actions - Ruff

```yaml
- name: Check formatting
  run: uv run ruff format --check .
```


### GitHub Actions - rustfmt

```yaml
- name: Check formatting
  run: cargo fmt --all -- --check
```


## VS Code Editor Integration


### `.vscode/settings.json`

```json
{
  "editor.formatOnSave": true,
  "editor.defaultFormatter": "biomejs.biome",
  "[javascript]": { "editor.defaultFormatter": "biomejs.biome" },
  "[typescript]": { "editor.defaultFormatter": "biomejs.biome" },
  "[python]": { "editor.defaultFormatter": "charliermarsh.ruff" },
  "[rust]": { "editor.defaultFormatter": "rust-lang.rust-analyzer", "editor.formatOnSave": true }
}
```


### `.vscode/extensions.json`

```json
{
  "recommendations": [
    "biomejs.biome",
    "charliermarsh.ruff",
    "rust-lang.rust-analyzer",
    "editorconfig.editorconfig"
  ]
}
```

---

## configure-tests

# /configure:tests

Check and configure testing frameworks against best practices (Vitest, Jest, pytest, cargo-nextest).


## Version Checking

**CRITICAL**: Before flagging outdated versions, verify latest releases:

1. **Vitest**: Check [vitest.dev](https://vitest.dev/) or [GitHub releases](https://github.com/vitest-dev/vitest/releases)
2. **Jest**: Check [jestjs.io](https://jestjs.io/) or [npm](https://www.npmjs.com/package/jest)
3. **pytest**: Check [pytest.org](https://pytest.org/) or [PyPI](https://pypi.org/project/pytest/)
4. **cargo-nextest**: Check [nexte.st](https://nexte.st/) or [GitHub releases](https://github.com/nextest-rs/nextest/releases)

Use WebSearch or WebFetch to verify current versions before reporting outdated frameworks.


## Execution

Execute this testing framework compliance check:


### Step 1: Detect framework

Identify the project language and existing test framework:

| Indicator | Language | Detected Framework |
|-----------|----------|-------------------|
| `vitest.config.*` | JavaScript/TypeScript | Vitest |
| `jest.config.*` | JavaScript/TypeScript | Jest |
| `pyproject.toml` [tool.pytest] | Python | pytest |
| `pytest.ini` | Python | pytest |
| `Cargo.toml` | Rust | cargo test |
| `.nextest.toml` | Rust | cargo-nextest |

If `--framework` flag is provided, use that value instead.


### Step 2: Analyze current state

Read the detected framework's configuration and check completeness. For each framework, verify:

**Vitest:**
- Config file exists (`vitest.config.ts` or `.js`)
- `globals: true` configured for compatibility
- `environment` set appropriately (jsdom, happy-dom, node)
- Coverage configured with `@vitest/coverage-v8` or `@vitest/coverage-istanbul`
- Watch mode exclusions configured

**Jest:**
- Config file exists (`jest.config.js` or `.ts`)
- `testEnvironment` configured
- Coverage configuration present
- Transform configured for TypeScript/JSX
- Module path aliases configured

**pytest:**
- `pyproject.toml` has `[tool.pytest.ini_options]` section
- `testpaths` configured
- `addopts` includes useful flags (`-v`, `--strict-markers`)
- `markers` defined for test categorization
- `pytest-cov` installed

**cargo-nextest:**
- `.nextest.toml` exists
- Profile configurations (default, ci)
- Retry policy configured
- Test groups defined if needed


### Step 3: Report results

Print a compliance report with:
- Detected framework and version
- Configuration check results for each item
- Test organization (unit/integration/e2e directories)
- Package scripts status (test, test:watch, test:coverage)
- Overall issue count and recommendations

If `--check-only`, stop here.


### Step 4: Apply fixes (if --fix or user confirms)

Install dependencies and create configuration using templates from :

1. **Missing config**: Create framework config file from template
2. **Missing dependencies**: Install required packages
3. **Missing coverage**: Add coverage configuration with 80% threshold
4. **Missing scripts**: Add test scripts to package.json
5. **Missing test directories**: Create standard test directory structure


### Step 5: Set up test organization

Create standard test directory structure for the detected language. See directory structure patterns in .


### Step 6: Configure CI/CD integration

Check for test commands in GitHub Actions workflows. If missing, add CI test commands using the CI templates from .


### Step 7: Handle migration (if upgrading)

If migrating between frameworks (e.g., Jest to Vitest, unittest to pytest), follow the migration guide in .


### Step 8: Update standards tracking

Update `.project-standards.yaml`:

```yaml
standards_version: "2025.1"
last_configured: "<timestamp>"
components:
  tests: "2025.1"
  tests_framework: "<vitest|jest|pytest|nextest>"
  tests_coverage_threshold: 80
  tests_ci_integrated: true
```

For detailed configuration templates, migration guides, CI/CD integration examples, and directory structure patterns, see .


## Error Handling

- **No package.json found**: Cannot configure JS/TS tests, skip or error
- **Conflicting frameworks**: Warn about multiple test configs, require manual resolution
- **Missing dependencies**: Offer to install required packages
- **Invalid config syntax**: Report parse error, offer to replace with template


# Testing Configuration Reference


## Report Template

```
Testing Framework Compliance Report
====================================
Project: [name]
Language: [TypeScript | Python | Rust]
Framework: [Vitest 2.x | pytest 8.x | cargo-nextest 0.9.x]

Configuration:
  Config file             <file>                     EXISTS/MISSING
  Test directory          <dir>                      EXISTS/NON-STANDARD
  Coverage provider       <provider>                 CONFIGURED/MISSING
  Environment             <env>                      CONFIGURED/NOT SET
  Watch exclusions        <patterns>                 CONFIGURED/INCOMPLETE

Test Organization:
  Unit tests              <pattern>                  FOUND/NONE
  Integration tests       <dir>                      FOUND/N/A
  E2E tests               <dir>                      FOUND/N/A

Scripts:
  test command            package.json scripts       CONFIGURED/MISSING
  test:watch              package.json scripts       CONFIGURED/MISSING
  test:coverage           package.json scripts       CONFIGURED/MISSING

Overall: [X issues found]

Recommendations:
  - <recommendation>
```


## Vitest Configuration


### Install Dependencies

```bash
npm install --save-dev vitest @vitest/ui @vitest/coverage-v8

# or
bun add --dev vitest @vitest/ui @vitest/coverage-v8
```


### vitest.config.ts Template

```typescript
import { defineConfig } from 'vitest/config';
import { resolve } from 'path';

export default defineConfig({
  test: {
    // Enable globals for compatibility with Jest-style tests
    globals: true,

    // Test environment (jsdom for DOM testing, node for backend)
    environment: 'jsdom', // or 'node', 'happy-dom'

    // Setup files to run before tests
    setupFiles: ['./tests/setup.ts'],

    // Coverage configuration
    coverage: {
      provider: 'v8', // or 'istanbul'
      reporter: ['text', 'json', 'html', 'lcov'],
      exclude: [
        'node_modules/',
        'dist/',
        'tests/',
        '**/*.config.*',
        '**/*.d.ts',
      ],
      thresholds: {
        lines: 80,
        functions: 80,
        branches: 80,
        statements: 80,
      },
    },

    // Watch mode exclusions
    watchExclude: ['**/node_modules/**', '**/dist/**', '**/.next/**'],

    // Test timeout
    testTimeout: 10000,

    // Include/exclude patterns
    include: ['**/*.{test,spec}.{js,mjs,cjs,ts,mts,cts,jsx,tsx}'],
    exclude: ['node_modules', 'dist', '.next', 'out'],
  },

  // Resolve aliases (if using path aliases)
  resolve: {
    alias: {
      '@': resolve(__dirname, './src'),
    },
  },
});
```


### Package.json Scripts

```json
{
  "scripts": {
    "test": "vitest run",
    "test:watch": "vitest",
    "test:ui": "vitest --ui",
    "test:coverage": "vitest run --coverage",
    "test:ci": "vitest run --coverage --reporter=junit --reporter=default"
  }
}
```


## Jest Configuration


### jest.config.ts Template

```typescript
import type { Config } from 'jest';

const config: Config = {
  preset: 'ts-jest',
  testEnvironment: 'jsdom',
  roots: ['<rootDir>/src', '<rootDir>/tests'],
  testMatch: ['**/__tests__/**/*.ts', '**/?(*.)+(spec|test).ts'],

  transform: {
    '^.+\\.tsx?$': ['ts-jest', {
      tsconfig: 'tsconfig.json',
    }],
  },

  collectCoverageFrom: [
    'src/**/*.{js,jsx,ts,tsx}',
    '!src/**/*.d.ts',
    '!src/**/*.stories.tsx',
  ],

  coverageThresholds: {
    global: {
      lines: 80,
      functions: 80,
      branches: 80,
      statements: 80,
    },
  },

  moduleNameMapper: {
    '^@/(.*)$': '<rootDir>/src/$1',
  },

  setupFilesAfterEnv: ['<rootDir>/tests/setup.ts'],
};

export default config;
```


## Python pytest Configuration


### pyproject.toml Template

```toml
[tool.pytest.ini_options]
testpaths = ["tests"]
python_files = ["test_*.py", "*_test.py"]
python_classes = ["Test*"]
python_functions = ["test_*"]

addopts = [
    "-v",
    "--strict-markers",
    "--strict-config",
    "--cov=src",
    "--cov-report=term-missing",
    "--cov-report=html",
    "--cov-report=xml",
    "--cov-fail-under=80",
]

markers = [
    "unit: Unit tests",
    "integration: Integration tests",
    "e2e: End-to-end tests",
    "slow: Slow running tests",
]

[tool.coverage.run]
source = ["src"]
omit = [
    "*/tests/*",
    "*/migrations/*",
    "*/__init__.py",
]

[tool.coverage.report]
exclude_lines = [
    "pragma: no cover",
    "def __repr__",
    "if __name__ == .__main__.:",
    "raise AssertionError",
    "raise NotImplementedError",
    "if 0:",
    "if False:",
    "if TYPE_CHECKING:",
]
```


### Install Dependencies

```bash
uv add --group dev pytest pytest-cov pytest-asyncio pytest-mock
```


## Rust cargo-nextest Configuration


### Install

```bash
cargo install cargo-nextest --locked
```


### .nextest.toml Template

```toml
[profile.default]
retries = 0
fail-fast = false


# Run tests with all features enabled
test-threads = "num-cpus"

[profile.ci]
retries = 2
fail-fast = true
test-threads = 2


# JUnit output for CI
[profile.ci.junit]
path = "target/nextest/ci/junit.xml"

[profile.default.junit]
path = "target/nextest/default/junit.xml"
```


### Optional cargo alias (.cargo/config.toml)

```toml
[alias]
test = "nextest run"
```


## Test Directory Structures


### JavaScript/TypeScript

```
tests/
├── setup.ts              # Test setup and global mocks
├── unit/                 # Unit tests
│   └── utils.test.ts
├── integration/          # Integration tests
│   └── api.test.ts
└── e2e/                  # E2E tests
    └── user-flow.test.ts
```


### Python

```
tests/
├── conftest.py           # pytest fixtures and configuration
├── unit/                 # Unit tests
│   └── test_utils.py
├── integration/          # Integration tests
│   └── test_api.py
└── e2e/                  # E2E tests
    └── test_user_flow.py
```


### Rust

```
tests/
├── integration_test.rs   # Integration tests
└── common/               # Shared test utilities
    └── mod.rs
```


## CI/CD Integration Templates


### JavaScript/TypeScript (Vitest)

```yaml
- name: Run tests
  run: npm test -- --reporter=junit --reporter=default --coverage

- name: Upload coverage
  uses: codecov/codecov-action@v4
  with:
    files: ./coverage/lcov.info
```


### Python (pytest)

```yaml
- name: Run tests
  run: |
    uv run pytest --junitxml=junit.xml --cov-report=xml

- name: Upload coverage
  uses: codecov/codecov-action@v4
  with:
    files: ./coverage.xml
```


### Rust (cargo-nextest)

```yaml
- name: Install nextest
  uses: taiki-e/install-action@nextest

- name: Run tests
  run: cargo nextest run --profile ci --no-fail-fast

- name: Upload test results
  uses: actions/upload-artifact@v4
  with:
    name: test-results
    path: target/nextest/ci/junit.xml
```


## Migration Guides


### Jest to Vitest

1. **Update dependencies:**
   ```bash
   npm uninstall jest @types/jest
   npm install --save-dev vitest @vitest/ui @vitest/coverage-v8
   ```

2. **Rename config file:**
   ```bash
   mv jest.config.ts vitest.config.ts
   ```

3. **Update test imports:**
   ```typescript
   // Before (Jest)
   import { describe, it, expect } from '@jest/globals';

   // After (Vitest with globals)
   // No import needed if globals: true in config
   ```

4. **Update package.json scripts:**
   ```json
   {
     "scripts": {
       "test": "vitest run",
       "test:watch": "vitest"
     }
   }
   ```


### unittest to pytest (Python)

1. **Install pytest:**
   ```bash
   uv add --group dev pytest pytest-cov
   ```

2. **Convert test files:**
   ```python
   # Before (unittest)
   import unittest
   class TestExample(unittest.TestCase):
       def test_something(self):
           self.assertEqual(1, 1)

   # After (pytest)
   def test_something():
       assert 1 == 1
   ```

3. **Convert assertions:**
   - `self.assertEqual(a, b)` -> `assert a == b`
   - `self.assertTrue(x)` -> `assert x`
   - `self.assertRaises(Error)` -> `with pytest.raises(Error):`

---

## configure-pre-commit

# /configure:pre-commit

Check and configure pre-commit hooks against project standards.


## Execution

Execute this pre-commit compliance check:


### Step 1: Detect project type

1. Read `.project-standards.yaml` for `project_type` field if it exists
2. If not found, auto-detect:
   - **infrastructure**: Has `terraform/`, `helm/`, `argocd/`, or `*.tf` files
   - **frontend**: Has `package.json` with vue/react dependencies
   - **python**: Has `pyproject.toml` or `requirements.txt`
3. Apply `--type` flag override if provided


### Step 2: Check configuration file

1. If `.pre-commit-config.yaml` is missing: report FAIL, offer to create from template
2. If it exists: read and parse the configuration


### Step 3: Verify hook versions against latest releases

**CRITICAL**: Before flagging outdated hooks, verify latest releases using WebSearch or WebFetch:

1. **pre-commit-hooks**: [GitHub releases](https://github.com/pre-commit/pre-commit-hooks/releases)
2. **conventional-pre-commit**: [GitHub releases](https://github.com/compilerla/conventional-pre-commit/releases)
3. **biome**: [GitHub releases](https://github.com/biomejs/biome/releases)
4. **ruff-pre-commit**: [GitHub releases](https://github.com/astral-sh/ruff-pre-commit/releases)
5. **gitleaks**: [GitHub releases](https://github.com/gitleaks/gitleaks/releases)


### Step 4: Analyze compliance

Compare existing configuration against project standards (from `pre-commit-standards` skill):

**Required Base Hooks (All Projects):**
- `pre-commit-hooks` v5.0.0+ with: trailing-whitespace, end-of-file-fixer, check-yaml, check-json, check-merge-conflict, check-added-large-files
- `conventional-pre-commit` v4.3.0+ with commit-msg stage

**Frontend-specific:**
- `biome` (pre-commit) v0.4.0+
- `helmlint` (if helm/ directory exists)

**Infrastructure-specific:**
- `tflint`, `helmlint` (gruntwork v0.1.29+)
- `actionlint` v1.7.7+
- `helm-docs` v1.14.2+
- `gitleaks` v8.22.1+

**Python-specific:**
- `ruff-pre-commit` v0.8.4+ (ruff, ruff-format)
- `gitleaks` v8.22.1+


### Step 5: Generate compliance report

Print a report in this format:

```
Pre-commit Compliance Report
================================
Project Type: [type] ([detected|override])
Config File: .pre-commit-config.yaml ([found|missing])

Hook Status:
  [hook-name]     [version]   [PASS|WARN|FAIL] ([details])

Outdated Hooks:
  - [hook]: [current] -> [standard]

Overall: [N] issues found
```


### Step 6: Apply fixes (if requested)

If `--fix` flag is set or user confirms:

1. **Missing config file**: Create from standard template for detected project type
2. **Missing hooks**: Add required hooks with standard versions
3. **Outdated versions**: Update `rev:` values to standard versions
4. **Missing hook types**: Add `default_install_hook_types` with `pre-commit` and `commit-msg`

After modification, run `pre-commit install --install-hooks` to install hooks.


### Step 7: Update standards tracking

Update or create `.project-standards.yaml`:

```yaml
standards_version: "2025.1"
project_type: "[detected]"
last_configured: "[timestamp]"
components:
  pre-commit: "2025.1"
```


## Error Handling

- **No git repository**: Warn but continue (pre-commit still useful)
- **Invalid YAML**: Report parse error, offer to replace with template
- **Unknown hook repos**: Skip (do not remove custom hooks)
- **Permission errors**: Report and suggest manual fix

---

## configure-workflows

# /configure:workflows

Check and configure GitHub Actions CI/CD workflows against project standards.


## Execution

Execute this GitHub Actions workflow configuration check:


### Step 1: Fetch latest action versions

Verify latest versions before reporting outdated actions:

1. `actions/checkout` - [releases](https://github.com/actions/checkout/releases)
2. `actions/setup-node` - [releases](https://github.com/actions/setup-node/releases)
3. `actions/cache` - [releases](https://github.com/actions/cache/releases)
4. `docker/setup-buildx-action` - [releases](https://github.com/docker/setup-buildx-action/releases)
5. `docker/build-push-action` - [releases](https://github.com/docker/build-push-action/releases)
6. `docker/login-action` - [releases](https://github.com/docker/login-action/releases)
7. `docker/metadata-action` - [releases](https://github.com/docker/metadata-action/releases)
8. `reproducible-containers/buildkit-cache-dance` - [releases](https://github.com/reproducible-containers/buildkit-cache-dance/releases)
9. `google-github-actions/release-please-action` - [releases](https://github.com/google-github-actions/release-please-action/releases)

Use WebSearch or WebFetch to verify current versions.


### Step 2: Detect project type and list workflows

1. Check for `.github/workflows/` directory
2. List all workflow files (*.yml, *.yaml)
3. Categorize workflows by purpose (container build, test, release)

Determine required workflows based on project type:

| Project Type | Required Workflows |
|--------------|-------------------|
| Frontend | container-build, release-please |
| Python | container-build, release-please, test |
| Infrastructure | release-please (optional: docs) |


### Step 3: Analyze workflow compliance

**Container Build Workflow Checks:**

| Check | Standard | Severity |
|-------|----------|----------|
| checkout action | v4 | WARN if older |
| build-push action | v6 | WARN if older |
| Multi-platform | amd64 + arm64 | WARN if missing |
| Registry | GHCR (ghcr.io) | INFO |
| Caching | GHA cache enabled | WARN if missing |
| Permissions | Explicit | WARN if missing |
| `id-token: write` | Required when provenance/SBOM enabled | WARN if missing |
| Cache scope | Explicit `scope=` when multiple build jobs | WARN if missing |
| Dead metadata tags | No `type=schedule` without schedule trigger | INFO |
| Semver regex escaping | Dots escaped in `type=match` patterns (`\d+\.\d+`) | WARN if unescaped |
| Hardcoded image names | Derive from `${{ github.repository }}` | INFO if hardcoded |
| Digest output | Capture `build-push` digest via `id:` for traceability | INFO if missing |
| Job summary | Write image/digest/tags to `$GITHUB_STEP_SUMMARY` | INFO if missing |
| Duplicated job conditions | Identical `if:` on sibling jobs; suggest gate job | INFO |

**Release Please Workflow Checks:**

| Check | Standard | Severity |
|-------|----------|----------|
| Action version | v4 | WARN if older |
| Token | MY_RELEASE_PLEASE_TOKEN | WARN if GITHUB_TOKEN |
| Permissions | contents: write, pull-requests: write | FAIL if missing |

**Test Workflow Checks:**

| Check | Standard | Severity |
|-------|----------|----------|
| Node version | 22 | WARN if older |
| Linting | npm run lint | WARN if missing |
| Type check | npm run typecheck | WARN if missing |
| Coverage | Coverage upload | INFO |


### Step 4: Generate compliance report

Print a formatted compliance report showing workflow status, per-workflow check results, and missing workflows.

If `--check-only` is set, stop here.

For the report format, see .


### Step 5: Apply configuration (if --fix or user confirms)

1. **Missing workflows**: Create from standard templates
2. **Outdated actions**: Update version numbers
3. **Missing multi-platform**: Add platforms to build-push
4. **Missing caching**: Add GHA cache configuration

For standard templates (container build, test workflow), see .


### Step 6: Update standards tracking

Update `.project-standards.yaml`:

```yaml
components:
  workflows: "2025.1"
```


# configure-workflows Reference


## Compliance Report Format

```
GitHub Workflows Compliance Report
======================================
Project Type: frontend (detected)
Workflows Directory: .github/workflows/ (found)

Workflow Status:
  container-build.yml   [PASS | MISSING]
  release-please.yml    [PASS | MISSING]
  test.yml              [PASS | MISSING]

container-build.yml Checks:
  checkout              v4              [PASS | OUTDATED]
  build-push-action     v6              [PASS | OUTDATED]
  Multi-platform        amd64,arm64     [PASS | MISSING]
  Caching               GHA cache       [PASS | MISSING]
  Permissions           Explicit        [PASS | MISSING]

release-please.yml Checks:
  Action version        v4              [PASS | OUTDATED]
  Token                 MY_RELEASE...   [PASS | WRONG TOKEN]

Missing Workflows:
  - test.yml (recommended for frontend projects)

Overall: X issues found
```


## Container Build Template

```yaml
name: Build Container

on:
  push:
    branches: [main]
    tags: ['v*.*.*']
  pull_request:
    branches: [main]

env:
  REGISTRY: ghcr.io
  # Derive from repository — avoids hardcoded image names
  IMAGE_NAME: ${{ github.repository }}

jobs:
  build:
    runs-on: ubuntu-latest
    permissions:
      contents: read
      packages: write
      id-token: write  # Required for provenance/SBOM attestations

    steps:
      - uses: actions/checkout@v4

      - uses: docker/setup-buildx-action@v3

      - uses: docker/login-action@v3
        if: github.event_name != 'pull_request'
        with:
          registry: ${{ env.REGISTRY }}
          username: ${{ github.actor }}
          password: ${{ secrets.GITHUB_TOKEN }}

      - id: meta
        uses: docker/metadata-action@v5
        with:
          images: ${{ env.REGISTRY }}/${{ env.IMAGE_NAME }}
          tags: |
            type=ref,event=branch
            type=ref,event=pr
            type=semver,pattern={{version}}
            type=semver,pattern={{major}}.{{minor}}
            type=sha
            # For release-please component tags: {component}-v{version}
            # Escape dots in semver regex for correct matching
            type=match,pattern=.*-v(\d+\.\d+\.\d+),group=1
            type=match,pattern=.*-v(\d+\.\d+),group=1
            type=match,pattern=.*-v(\d+),group=1

      - id: build-push
        uses: docker/build-push-action@v6
        with:
          context: .
          platforms: linux/amd64,linux/arm64
          push: ${{ github.event_name != 'pull_request' }}
          tags: ${{ steps.meta.outputs.tags }}
          labels: ${{ steps.meta.outputs.labels }}
          cache-from: type=gha
          cache-to: type=gha,mode=max
          # Provenance and SBOM only on tagged releases (saves ~30s otherwise)
          provenance: ${{ startsWith(github.ref, 'refs/tags/') && 'mode=max' || 'false' }}
          sbom: ${{ startsWith(github.ref, 'refs/tags/') }}

      - name: Job summary
        if: always()
        run: |
          echo "## Container Build" >> $GITHUB_STEP_SUMMARY
          echo "- **Image**: \`${{ env.REGISTRY }}/${{ env.IMAGE_NAME }}\`" >> $GITHUB_STEP_SUMMARY
          echo "- **Digest**: \`${{ steps.build-push.outputs.digest }}\`" >> $GITHUB_STEP_SUMMARY
          echo "- **Tags**:" >> $GITHUB_STEP_SUMMARY
          echo '${{ steps.meta.outputs.tags }}' | while read -r tag; do
            echo "  - \`$tag\`" >> $GITHUB_STEP_SUMMARY
          done
```


### Multi-Job Cache Scope

When a workflow has multiple build jobs (e.g., app + db-init), use explicit `scope=` to prevent cache collisions:

```yaml

# Job 1: main image
cache-from: type=gha,scope=app
cache-to: type=gha,mode=max,scope=app


# Job 2: secondary image
cache-from: type=gha,scope=db-init
cache-to: type=gha,mode=max,scope=db-init
```


### BuildKit Cache Dance (Optional)

For persisting BuildKit `--mount=type=cache` mounts across CI runs:

```yaml
- name: Cache BuildKit mounts
  id: cache
  uses: actions/cache@v4
  with:
    path: buildkit-cache
    key: ${{ runner.os }}-buildkit-${{ hashFiles('package.json', 'bun.lock') }}
    restore-keys: |
      ${{ runner.os }}-buildkit-

- name: Inject BuildKit cache mounts
  uses: reproducible-containers/buildkit-cache-dance@v3
  with:
    cache-map: |
      {
        "dep-cache": {
          "target": "/root/.cache",
          "id": "dep-cache"
        }
      }
    skip-extraction: ${{ steps.cache.outputs.cache-hit }}
```


## Test Workflow Template (Node)

```yaml
name: Tests

on:
  push:
    branches: [main]
  pull_request:
    branches: [main]

jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - uses: actions/setup-node@v4
        with:
          node-version: '22'
          cache: 'npm'

      - run: npm ci
      - run: npm run lint
      - run: npm run typecheck
      - run: npm run test:coverage
```

---

## configure-coverage

# /configure:coverage

Check and configure code coverage thresholds and reporting for test frameworks.


## Execution

Execute this code coverage compliance check:


### Step 1: Detect test framework and coverage configuration

Check for framework indicators:

| Indicator | Framework | Coverage Tool |
|-----------|-----------|---------------|
| `vitest.config.*` with coverage | Vitest | @vitest/coverage-v8 |
| `jest.config.*` with coverage | Jest | Built-in |
| `pyproject.toml` [tool.coverage] | pytest | pytest-cov |
| `.cargo/config.toml` with coverage | Rust | cargo-llvm-cov |

Use WebSearch or WebFetch to verify latest versions of coverage tools before configuring.


### Step 2: Analyze current coverage state

For the detected framework, check configuration completeness:

**Vitest:**
- [ ] Coverage provider configured (`v8` or `istanbul`)
- [ ] Coverage reporters configured (`text`, `json`, `html`, `lcov`)
- [ ] Thresholds set for lines, functions, branches, statements
- [ ] Exclusions configured (node_modules, dist, tests, config files)
- [ ] Output directory specified

**Jest:**
- [ ] `collectCoverage` enabled
- [ ] `coverageProvider` set (`v8` or `babel`)
- [ ] `collectCoverageFrom` patterns configured
- [ ] `coverageThresholds` configured
- [ ] `coverageReporters` configured

**pytest:**
- [ ] `pytest-cov` installed
- [ ] `[tool.coverage.run]` section exists
- [ ] `[tool.coverage.report]` section exists
- [ ] Coverage threshold configured (`--cov-fail-under`)

**Rust (cargo-llvm-cov):**
- [ ] `cargo-llvm-cov` installed
- [ ] Coverage configuration in workspace
- [ ] HTML/LCOV output configured


### Step 3: Generate compliance report

Print a formatted compliance report:

```
Code Coverage Compliance Report
================================
Project: [name]
Framework: [Vitest 2.x | pytest 8.x | cargo-llvm-cov 0.6.x]

Coverage Configuration:
  Provider                @vitest/coverage-v8        [CONFIGURED | MISSING]
  Reporters               text, json, html, lcov     [ALL | PARTIAL]
  Output directory        coverage/                  [CONFIGURED | DEFAULT]
  Exclusions              node_modules, dist, tests  [CONFIGURED | INCOMPLETE]

Thresholds:
  Lines                   80%                        [PASS | LOW | NOT SET]
  Branches                80%                        [PASS | LOW | NOT SET]
  Functions               80%                        [PASS | LOW | NOT SET]
  Statements              80%                        [PASS | LOW | NOT SET]

CI/CD Integration:
  Coverage upload         codecov/coveralls          [CONFIGURED | MISSING]
  Artifact upload         coverage reports           [CONFIGURED | MISSING]

Overall: [X issues found]
```

If `--check-only`, stop here.


### Step 4: Configure coverage (if --fix or user confirms)

Apply coverage configuration based on detected framework. Use templates from :

1. **Install coverage provider** (e.g., `@vitest/coverage-v8`, `pytest-cov`)
2. **Update config file** with thresholds, reporters, exclusions
3. **Add scripts** to package.json or pyproject.toml
4. **Configure CI/CD** with Codecov upload and artifact storage


### Step 5: Update standards tracking

Update `.project-standards.yaml`:

```yaml
standards_version: "2025.1"
last_configured: "[timestamp]"
components:
  coverage: "2025.1"
  coverage_threshold: 80
  coverage_provider: "[v8|istanbul|pytest-cov|llvm-cov]"
  coverage_reporters: ["text", "json", "html", "lcov"]
  coverage_ci: "codecov"
```


### Step 6: Print final report

Print a summary of changes applied, scripts added, and next steps for verifying coverage.

For detailed configuration templates, see .


## Examples

```bash

# Check compliance and offer fixes
/configure:coverage


# Check only, no modifications
/configure:coverage --check-only


# Auto-fix with custom threshold
/configure:coverage --fix --threshold 90
```


## Error Handling

- **No test framework detected**: Suggest running `/configure:tests` first
- **Coverage provider missing**: Offer to install
- **Invalid threshold**: Reject values <0 or >100
- **CI token missing**: Warn about Codecov/Coveralls setup


# Coverage Configuration Reference

Detailed configuration templates for code coverage tools.


## Vitest Coverage Configuration


### Install Coverage Provider

```bash
npm install --save-dev @vitest/coverage-v8

# or for Istanbul
npm install --save-dev @vitest/coverage-istanbul
```


### `vitest.config.ts` Template

```typescript
import { defineConfig } from 'vitest/config';

export default defineConfig({
  test: {
    coverage: {
      provider: 'v8',

      reporter: [
        'text',           // Console output
        'json',           // JSON report for tools
        'html',           // HTML report for browsing
        'lcov',           // LCOV for CI/CD (codecov, coveralls)
      ],

      reportsDirectory: './coverage',

      thresholds: {
        lines: 80,
        functions: 80,
        branches: 80,
        statements: 80,
      },

      include: ['src/**/*.{js,ts,jsx,tsx}'],

      exclude: [
        'node_modules/',
        'dist/',
        'tests/',
        '**/*.config.*',
        '**/*.d.ts',
        '**/*.test.*',
        '**/*.spec.*',
        '**/types/',
        '**/__tests__/',
      ],

      clean: true,
      all: true,
      skipFull: false,
    },
  },
});
```


### Package.json Scripts

```json
{
  "scripts": {
    "test:coverage": "vitest run --coverage",
    "coverage:report": "open coverage/index.html",
    "coverage:check": "vitest run --coverage --reporter=json"
  }
}
```


## Jest Coverage Configuration


### `jest.config.ts` Template

```typescript
import type { Config } from 'jest';

const config: Config = {
  collectCoverage: true,
  coverageProvider: 'v8',

  collectCoverageFrom: [
    'src/**/*.{js,jsx,ts,tsx}',
    '!src/**/*.d.ts',
    '!src/**/*.stories.*',
    '!src/**/__tests__/**',
    '!src/**/types/**',
  ],

  coverageDirectory: 'coverage',

  coverageReporters: [
    'text',
    'text-summary',
    'json',
    'html',
    'lcov',
  ],

  coverageThresholds: {
    global: {
      lines: 80,
      functions: 80,
      branches: 80,
      statements: 80,
    },
    './src/critical/**/*.ts': {
      lines: 90,
      functions: 90,
      branches: 90,
      statements: 90,
    },
  },

  coveragePathIgnorePatterns: [
    '/node_modules/',
    '/dist/',
    '/tests/',
    '.config.js',
  ],
};

export default config;
```


## pytest Coverage Configuration


### Install pytest-cov

```bash
uv add --group dev pytest-cov
```


### `pyproject.toml` Template

```toml
[tool.pytest.ini_options]
addopts = [
    "-v",
    "--cov=src",
    "--cov-report=term-missing",
    "--cov-report=html",
    "--cov-report=xml",
    "--cov-report=json",
    "--cov-fail-under=80",
]

[tool.coverage.run]
source = ["src"]
branch = true
parallel = true
omit = [
    "*/tests/*",
    "*/migrations/*",
    "*/__init__.py",
    "*/config.py",
    "*/settings.py",
]

[tool.coverage.report]
precision = 2
show_missing = true
fail_under = 80

exclude_lines = [
    "pragma: no cover",
    "def __repr__",
    "def __str__",
    "if __name__ == .__main__.:",
    "raise AssertionError",
    "raise NotImplementedError",
    "if 0:",
    "if False:",
    "if TYPE_CHECKING:",
    "@abstractmethod",
    "@overload",
]

[tool.coverage.html]
directory = "coverage/html"

[tool.coverage.xml]
output = "coverage/coverage.xml"

[tool.coverage.json]
output = "coverage/coverage.json"
```


## Rust Coverage Configuration


### Install cargo-llvm-cov

```bash
cargo install cargo-llvm-cov --locked
```


### `.cargo/config.toml` Template

```toml
[alias]
coverage = "llvm-cov --html --open"
coverage-lcov = "llvm-cov --lcov --output-path lcov.info"
```


### `Cargo.toml` Coverage Metadata

```toml
[package.metadata.coverage]
exclude = [
    "tests/*",
    "benches/*",
    "examples/*",
]
```


### Run Coverage

```bash

# Generate HTML report
cargo coverage


# Generate LCOV for CI
cargo coverage-lcov
```


## CI/CD Integration


### GitHub Actions - Vitest/Jest

```yaml
- name: Run tests with coverage
  run: npm run test:coverage

- name: Upload coverage to Codecov
  uses: codecov/codecov-action@v4
  with:
    token: ${{ secrets.CODECOV_TOKEN }}
    files: ./coverage/lcov.info
    flags: unittests
    name: codecov-umbrella
    fail_ci_if_error: true

- name: Upload coverage artifacts
  uses: actions/upload-artifact@v4
  if: always()
  with:
    name: coverage-report
    path: coverage/
```


### GitHub Actions - pytest

```yaml
- name: Run tests with coverage
  run: uv run pytest --cov --cov-report=xml --cov-report=html

- name: Upload coverage to Codecov
  uses: codecov/codecov-action@v4
  with:
    token: ${{ secrets.CODECOV_TOKEN }}
    files: ./coverage/coverage.xml
    flags: unittests
    name: codecov-umbrella
    fail_ci_if_error: true

- name: Upload coverage artifacts
  uses: actions/upload-artifact@v4
  if: always()
  with:
    name: coverage-report
    path: coverage/
```


### GitHub Actions - Rust

```yaml
- name: Install cargo-llvm-cov
  uses: taiki-e/install-action@cargo-llvm-cov

- name: Generate coverage
  run: cargo llvm-cov --all-features --lcov --output-path lcov.info

- name: Upload coverage to Codecov
  uses: codecov/codecov-action@v4
  with:
    token: ${{ secrets.CODECOV_TOKEN }}
    files: ./lcov.info
    flags: unittests
    fail_ci_if_error: true
```


## Coverage Badges

**Codecov:**
```markdown
[![codecov](https://codecov.io/gh/USERNAME/REPO/branch/main/graph/badge.svg)](https://codecov.io/gh/USERNAME/REPO)
```

**Coveralls:**
```markdown
[![Coverage Status](https://coveralls.io/repos/github/USERNAME/REPO/badge.svg?branch=main)](https://coveralls.io/github/USERNAME/REPO?branch=main)
```


## Codecov Configuration


### `codecov.yml` Template

```yaml
coverage:
  status:
    project:
      default:
        target: 80%
        threshold: 1%
    patch:
      default:
        target: 80%

comment:
  layout: "reach,diff,flags,tree"
  behavior: default
  require_changes: false
```


### Codecov Setup Steps

1. Sign up at https://codecov.io
2. Add repository
3. Copy token from Codecov dashboard
4. Add secret: GitHub repo -> Settings -> Secrets -> `CODECOV_TOKEN`
5. Add upload step to workflow
