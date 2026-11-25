# configure-formatting Reference

Configuration templates, migration guides, and pre-commit configurations for code formatters.

## Biome Configuration (JS/TS/JSON/CSS — the Prettier + ESLint replacement)

### Install

```bash
npm install --save-dev --save-exact @biomejs/biome
# or
bun add --dev --exact @biomejs/biome
```

Pin the exact version: the pre-commit hook, CI and the editor then run the same Biome.

### `biome.json`

Biome 2.x syntax (`files.includes` with `!` negations; the 1.x keys `include` and `ignore` are an error: ``Found an unknown key `include` ``). Match the style the code already has (quotes, semicolons, trailing commas) so the reformat stays small; these values are a starting point.

```json
{
  "$schema": "./node_modules/@biomejs/biome/configuration_schema.json",
  "vcs": { "enabled": true, "clientKind": "git", "useIgnoreFile": true },
  "files": {
    "includes": [
      "*.{js,ts}",
      "src/**/*.{js,jsx,ts,tsx}",
      "!**/node_modules",
      "!**/dist",
      "!**/coverage",
      "!.claude/worktrees"
    ]
  },
  "formatter": {
    "enabled": true,
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
      "arrowParentheses": "always"
    }
  },
  "linter": { "enabled": false },
  "assist": { "enabled": false }
}
```

- **Scope.** `"includes": ["**"]` also formats Markdown and JSON: it rewrote README and CLAUDE.md tables and `.claude/settings.json` in a run on a repo that wanted JavaScript only. List the language globs instead. A fixture with one `.js` file, `README.md` and a file under `.claude/worktrees/` was checked as 2 files with the language globs and 4 with `["**"]`. The `biome.json` itself is always checked.
- **`vcs.useIgnoreFile`** needs a `.gitignore` at the project root; without one Biome stops with `couldn't find an ignore file`.
- **`linter` and `assist` off** when ESLint stays the linter. Set `linter.enabled` to `true` (and add rules) only when the repo is dropping ESLint.

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

A local hook runs the Biome pinned in `package.json`, so nothing else carries a version:

```yaml
repos:
  - repo: local
    hooks:
      - id: biome-format
        name: Biome format
        entry: npx --no-install biome format --write --no-errors-on-unmatched
        language: system
        types: [javascript]
```

The mirror hook (`https://github.com/biomejs/pre-commit`) installs its own Biome from `additional_dependencies`, a second pin that has to be bumped with `package.json` and with the hook's `rev`. Its `biome-check` id also runs the linter and, on 2.6+, the Markdown formatter. Use the mirror only for a repo with no `package.json`, pin `additional_dependencies` to the same version, and pick `biome-format` rather than `biome-check` when ESLint stays the linter.

### Ruff Format

```yaml
repos:
  - repo: https://github.com/astral-sh/ruff-pre-commit
    rev: v0.15.15
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
  run: npm run format:check   # biome format ., the version pinned in package.json
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
