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
