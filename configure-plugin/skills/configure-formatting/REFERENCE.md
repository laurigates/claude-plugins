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
