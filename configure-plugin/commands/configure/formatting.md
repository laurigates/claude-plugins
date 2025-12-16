---
description: Check and configure code formatting (Biome, Prettier, Ruff, rustfmt)
allowed-tools: Glob, Grep, Read, Write, Edit, Bash, AskUserQuestion, TodoWrite, WebSearch, WebFetch
argument-hint: "[--check-only] [--fix] [--formatter <biome|prettier|ruff|rustfmt>]"
---

# /configure:formatting

Check and configure code formatting tools against modern best practices.

## Context

This command validates code formatting configuration and upgrades to modern tools.

**Modern formatting preferences:**
- **JavaScript/TypeScript**: Biome (preferred) or Prettier
- **Python**: Ruff format (replaces Black)
- **Rust**: rustfmt (standard)

## Version Checking

**CRITICAL**: Before flagging outdated formatters, verify latest releases:

1. **Biome**: Check [biomejs.dev](https://biomejs.dev/) or [GitHub releases](https://github.com/biomejs/biome/releases)
2. **Prettier**: Check [prettier.io](https://prettier.io/) or [npm](https://www.npmjs.com/package/prettier)
3. **Ruff**: Check [docs.astral.sh/ruff](https://docs.astral.sh/ruff/) or [GitHub releases](https://github.com/astral-sh/ruff/releases)
4. **rustfmt**: Bundled with Rust toolchain - check [Rust releases](https://releases.rs/)

Use WebSearch or WebFetch to verify current versions before reporting outdated formatters.

## Workflow

### Phase 1: Language Detection

Detect project language and existing formatters:

| Indicator | Language | Detected Formatter |
|-----------|----------|-------------------|
| `biome.json` with formatter | JavaScript/TypeScript | Biome |
| `.prettierrc.*` | JavaScript/TypeScript | Prettier |
| `pyproject.toml` [tool.ruff.format] | Python | Ruff |
| `pyproject.toml` [tool.black] | Python | Black (legacy) |
| `rustfmt.toml` or `.rustfmt.toml` | Rust | rustfmt |

### Phase 2: Current State Analysis

For each detected formatter, check configuration:

**Biome (preferred for JS/TS):**
- [ ] `biome.json` exists
- [ ] Formatter enabled
- [ ] Indent style configured
- [ ] Line width configured
- [ ] Quote style configured
- [ ] Files/ignore patterns set

**Prettier:**
- [ ] `.prettierrc.*` or `prettier.config.*` exists
- [ ] Print width configured
- [ ] Tab width configured
- [ ] Semicolons configured
- [ ] Quotes configured
- [ ] Trailing commas configured
- [ ] `.prettierignore` exists

**Ruff Format (preferred for Python):**
- [ ] `pyproject.toml` has `[tool.ruff.format]` section
- [ ] Quote style configured
- [ ] Indent style configured
- [ ] Line ending configured
- [ ] Docstring formatting configured

**rustfmt:**
- [ ] `rustfmt.toml` or `.rustfmt.toml` exists
- [ ] Edition configured
- [ ] Max width configured
- [ ] Tab spaces configured
- [ ] Newline style configured

### Phase 3: Compliance Report

Generate formatted compliance report:

```
Code Formatting Compliance Report
==================================
Project: [name]
Language: [TypeScript | Python | Rust]
Formatter: [Biome 1.x | Ruff 0.x | rustfmt 1.x]

Configuration:
  Config file             biome.json                 [✅ EXISTS | ❌ MISSING]
  Formatter enabled       true                       [✅ ENABLED | ❌ DISABLED]
  Line width              100                        [✅ CONFIGURED | ⚠️ DEFAULT]
  Indent style            space                      [✅ CONFIGURED | ⚠️ DEFAULT]
  Indent width            2                          [✅ CONFIGURED | ⚠️ DEFAULT]
  Quote style             single                     [✅ CONFIGURED | ⚠️ DEFAULT]
  Ignore patterns         node_modules, dist         [✅ CONFIGURED | ⚠️ INCOMPLETE]

Format Options:
  Semicolons              always                     [✅ CONFIGURED | ⚠️ DEFAULT]
  Trailing commas         all                        [✅ CONFIGURED | ⚠️ DEFAULT]
  Arrow parens            always                     [✅ CONFIGURED | ⏭️ N/A]
  End of line             lf                         [✅ CONFIGURED | ⚠️ DEFAULT]

Scripts:
  format command          package.json scripts       [✅ CONFIGURED | ❌ MISSING]
  format:check            package.json scripts       [✅ CONFIGURED | ❌ MISSING]

Integration:
  Pre-commit hook         .pre-commit-config.yaml    [✅ CONFIGURED | ❌ MISSING]
  CI/CD check             .github/workflows/         [✅ CONFIGURED | ❌ MISSING]
  Editor config           .editorconfig              [✅ CONFIGURED | ⚠️ MISSING]

Overall: [X issues found]

Recommendations:
  - Migrate from Prettier to Biome for better performance
  - Add .editorconfig for editor consistency
  - Enable format-on-save in editor
```

### Phase 4: Configuration (if --fix or user confirms)

#### Biome Configuration (Recommended for JS/TS)

**Install Biome:**
```bash
npm install --save-dev @biomejs/biome
# or
bun add --dev @biomejs/biome
```

**Create `biome.json`:**
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

**Add npm scripts to `package.json`:**
```json
{
  "scripts": {
    "format": "biome format --write .",
    "format:check": "biome format .",
    "lint:format": "biome check --write ."
  }
}
```

#### Prettier Configuration (Alternative)

**Install Prettier:**
```bash
npm install --save-dev prettier
# or
bun add --dev prettier
```

**Create `.prettierrc.json`:**
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

**Create `.prettierignore`:**
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

**Add npm scripts to `package.json`:**
```json
{
  "scripts": {
    "format": "prettier --write .",
    "format:check": "prettier --check ."
  }
}
```

#### Ruff Format Configuration (Recommended for Python)

**Install Ruff:**
```bash
uv add --group dev ruff
```

**Update `pyproject.toml`:**
```toml
[tool.ruff.format]
# Quote style (double or single)
quote-style = "double"

# Indent style (space or tab)
indent-style = "space"

# Line ending (auto, lf, crlf, cr)
line-ending = "auto"

# Skip magic trailing comma
skip-magic-trailing-comma = false

# Docstring formatting
docstring-code-format = true
docstring-code-line-length = 72

# Preview mode for unreleased formatting features
preview = false

[tool.ruff]
# Line length for both linter and formatter
line-length = 100

# Exclude directories
exclude = [
    ".git",
    ".venv",
    "__pycache__",
    "dist",
    "build",
]
```

**Run Ruff format:**
```bash
uv run ruff format .
```

#### Black Configuration (Alternative)

**Install Black:**
```bash
uv add --group dev black
```

**Update `pyproject.toml`:**
```toml
[tool.black]
line-length = 100
target-version = ['py312']
include = '\.pyi?$'
extend-exclude = '''
/(
  # directories
  \.eggs
  | \.git
  | \.venv
  | dist
  | build
)/
'''
```

#### rustfmt Configuration (Rust)

**Create `rustfmt.toml`:**
```toml
# Edition
edition = "2021"

# Max line width
max_width = 100

# Tab spaces
tab_spaces = 4

# Hard tabs
hard_tabs = false

# Newline style (Unix, Windows, Native)
newline_style = "Unix"

# Use small heuristics
use_small_heuristics = "Default"

# Reorder imports
reorder_imports = true

# Reorder modules
reorder_modules = true

# Remove nested parens
remove_nested_parens = true

# Format code in doc comments
format_code_in_doc_comments = true

# Normalize comments
normalize_comments = true

# Wrap comments
wrap_comments = true

# Format strings
format_strings = true

# Format macro bodies
format_macro_bodies = true

# Format macro matchers
format_macro_matchers = true

# Imports granularity (Preserve, Crate, Module, Item, One)
imports_granularity = "Crate"

# Group imports (Preserve, StdExternalCrate)
group_imports = "StdExternalCrate"
```

**Run rustfmt:**
```bash
cargo fmt --all
```

### Phase 5: EditorConfig Integration

**Create `.editorconfig`:**
```ini
# EditorConfig is awesome: https://EditorConfig.org

# top-most EditorConfig file
root = true

# Unix-style newlines with a newline ending every file
[*]
charset = utf-8
end_of_line = lf
insert_final_newline = true
trim_trailing_whitespace = true

# JavaScript, TypeScript, JSON
[*.{js,jsx,ts,tsx,json,jsonc}]
indent_style = space
indent_size = 2
max_line_length = 100

# Python
[*.py]
indent_style = space
indent_size = 4
max_line_length = 100

# Rust
[*.rs]
indent_style = space
indent_size = 4
max_line_length = 100

# YAML
[*.{yml,yaml}]
indent_style = space
indent_size = 2

# Markdown
[*.md]
trim_trailing_whitespace = false
max_line_length = off

# Makefile
[Makefile]
indent_style = tab
```

### Phase 6: Migration Guides

#### Prettier → Biome Migration

**Step 1: Install Biome**
```bash
npm install --save-dev @biomejs/biome
```

**Step 2: Import Prettier config**
```bash
npx @biomejs/biome migrate prettier --write
```

**Step 3: Review and adjust `biome.json`**

**Step 4: Remove Prettier**
```bash
npm uninstall prettier
rm .prettierrc.* prettier.config.* .prettierignore
```

**Step 5: Update scripts**
```json
{
  "scripts": {
    "format": "biome format --write .",
    "format:check": "biome format ."
  }
}
```

#### Black → Ruff Format Migration

**Step 1: Install Ruff**
```bash
uv add --group dev ruff
```

**Step 2: Configure in `pyproject.toml`** (see Phase 4)

**Step 3: Format codebase**
```bash
uv run ruff format .
```

**Step 4: Remove Black**
```bash
uv remove black
```

**Step 5: Update pre-commit hooks**
```yaml
repos:
  - repo: https://github.com/astral-sh/ruff-pre-commit
    rev: v0.8.4
    hooks:
      - id: ruff-format
```

### Phase 7: Pre-commit Integration

**Biome:**
```yaml
repos:
  - repo: https://github.com/biomejs/pre-commit
    rev: v0.4.0
    hooks:
      - id: biome-check
        additional_dependencies: ["@biomejs/biome@1.9.4"]
```

**Prettier:**
```yaml
repos:
  - repo: https://github.com/pre-commit/mirrors-prettier
    rev: v4.0.0-alpha.8
    hooks:
      - id: prettier
        types_or: [javascript, jsx, ts, tsx, json, yaml, markdown]
```

**Ruff Format:**
```yaml
repos:
  - repo: https://github.com/astral-sh/ruff-pre-commit
    rev: v0.8.4
    hooks:
      - id: ruff-format
```

**rustfmt:**
```yaml
repos:
  - repo: https://github.com/doublify/pre-commit-rust
    rev: v1.0
    hooks:
      - id: fmt
```

### Phase 8: CI/CD Integration

**GitHub Actions - Biome:**
```yaml
- name: Check formatting
  run: npx @biomejs/biome format .
```

**GitHub Actions - Prettier:**
```yaml
- name: Check formatting
  run: npm run format:check
```

**GitHub Actions - Ruff:**
```yaml
- name: Check formatting
  run: uv run ruff format --check .
```

**GitHub Actions - rustfmt:**
```yaml
- name: Check formatting
  run: cargo fmt --all -- --check
```

### Phase 9: Editor Integration

#### VS Code Settings

**Create `.vscode/settings.json`:**
```json
{
  "editor.formatOnSave": true,
  "editor.defaultFormatter": "biomejs.biome",
  "[javascript]": {
    "editor.defaultFormatter": "biomejs.biome"
  },
  "[typescript]": {
    "editor.defaultFormatter": "biomejs.biome"
  },
  "[python]": {
    "editor.defaultFormatter": "charliermarsh.ruff"
  },
  "[rust]": {
    "editor.defaultFormatter": "rust-lang.rust-analyzer",
    "editor.formatOnSave": true
  }
}
```

**Create `.vscode/extensions.json`:**
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

### Phase 10: Standards Tracking

Update `.fvh-standards.yaml`:

```yaml
standards_version: "2025.1"
last_configured: "[timestamp]"
components:
  formatting: "2025.1"
  formatting_tool: "[biome|prettier|ruff|rustfmt]"
  formatting_pre_commit: true
  formatting_ci: true
  formatting_editor_config: true
```

### Phase 11: Updated Compliance Report

```
Code Formatting Configuration Complete
=======================================

Language: TypeScript
Formatter: Biome 1.9.4 (modern, fast)

Configuration Applied:
  ✅ biome.json created
  ✅ Formatter enabled
  ✅ Line width: 100
  ✅ Indent: 2 spaces
  ✅ Quotes: single
  ✅ Semicolons: always
  ✅ Trailing commas: all
  ✅ Ignore patterns configured

Scripts Added:
  ✅ npm run format (format all)
  ✅ npm run format:check (check only)

Integration:
  ✅ .editorconfig created
  ✅ Pre-commit hook configured
  ✅ CI/CD check added
  ✅ VS Code settings configured

Migration:
  ✅ Prettier removed
  ✅ Configuration imported

Next Steps:
  1. Format codebase:
     npm run format

  2. Verify formatting:
     npm run format:check

  3. Enable format-on-save in editor:
     Install Biome extension

  4. Verify CI integration:
     Push changes and check workflow

Documentation: docs/FORMATTING.md
```

## Flags

| Flag | Description |
|------|-------------|
| `--check-only` | Report status without offering fixes |
| `--fix` | Apply all fixes automatically without prompting |
| `--formatter <formatter>` | Override formatter detection (biome, prettier, ruff, rustfmt) |

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

## See Also

- `/configure:linting` - Configure linting tools
- `/configure:editor` - Configure editor settings
- `/configure:pre-commit` - Pre-commit hook configuration
- `/configure:all` - Run all FVH compliance checks
- **Biome documentation**: https://biomejs.dev
- **Ruff documentation**: https://docs.astral.sh/ruff
- **rustfmt documentation**: https://rust-lang.github.io/rustfmt
