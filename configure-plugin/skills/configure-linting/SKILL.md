---
model: haiku
created: 2025-12-16
modified: 2025-12-16
reviewed: 2025-12-16
description: Check and configure linting tools (Biome, Ruff, Clippy)
allowed-tools: Glob, Grep, Read, Write, Edit, Bash, AskUserQuestion, TodoWrite, WebSearch, WebFetch
argument-hint: "[--check-only] [--fix] [--linter <biome|ruff|clippy>]"
name: configure-linting
---

# /configure:linting

Check and configure linting tools against modern best practices.

## Context

This command validates linting configuration and upgrades to modern tools.

**Modern linting preferences:**
- **JavaScript/TypeScript**: Biome (unified linter + formatter, fast)
- **Python**: Ruff (replaces flake8, isort, pyupgrade)
- **Rust**: Clippy with workspace lints

## Version Checking

**CRITICAL**: Before flagging outdated versions, verify latest releases:

1. **Biome**: Check [biomejs.dev](https://biomejs.dev/) or [GitHub releases](https://github.com/biomejs/biome/releases)
2. **Ruff**: Check [docs.astral.sh/ruff](https://docs.astral.sh/ruff/) or [GitHub releases](https://github.com/astral-sh/ruff/releases)
3. **Clippy**: Check [Rust releases](https://releases.rs/) for Clippy updates

Use WebSearch or WebFetch to verify current versions before reporting outdated tools.

## Workflow

### Phase 1: Language Detection

Detect project language and existing linters:

| Indicator | Language | Detected Linter |
|-----------|----------|-----------------|
| `biome.json` | JavaScript/TypeScript | Biome |
| `pyproject.toml` [tool.ruff] | Python | Ruff |
| `.flake8` | Python | Flake8 (legacy) |
| `Cargo.toml` [lints.clippy] | Rust | Clippy |

### Phase 2: Current State Analysis

For each detected linter, check configuration:

**Biome (for JS/TS):**
- [ ] `biome.json` exists
- [ ] Linter rules configured
- [ ] Formatter configured
- [ ] Files/ignore patterns set
- [ ] Recommended rules enabled

**Ruff (for Python):**
- [ ] `pyproject.toml` has `[tool.ruff]` section
- [ ] Rules selected (E, F, I, N, etc.)
- [ ] Line length configured
- [ ] Target Python version set
- [ ] Per-file ignores configured

**Clippy:**
- [ ] `Cargo.toml` has `[lints.clippy]` section
- [ ] Pedantic lints enabled
- [ ] Allowed/denied lints configured
- [ ] Workspace-level lints if applicable

### Phase 3: Compliance Report

Generate formatted compliance report:

```
Linting Configuration Compliance Report
========================================
Project: [name]
Language: [TypeScript | Python | Rust]
Linter: [Biome 1.x | Ruff 0.x | Clippy 1.x]

Configuration:
  Config file             biome.json                 [✅ EXISTS | ❌ MISSING]
  Linter enabled          true                       [✅ ENABLED | ❌ DISABLED]
  Rules configured        recommended + custom       [✅ CONFIGURED | ⚠️ MINIMAL]
  Formatter integrated    biome format               [✅ CONFIGURED | ⚠️ SEPARATE]
  Ignore patterns         node_modules, dist         [✅ CONFIGURED | ⚠️ INCOMPLETE]

Rules:
  Recommended             enabled                    [✅ ENABLED | ❌ DISABLED]
  Suspicious              enabled                    [✅ ENABLED | ❌ DISABLED]
  Complexity              enabled                    [✅ ENABLED | ❌ DISABLED]
  Performance             enabled                    [✅ ENABLED | ⏭️ N/A]
  Style                   enabled                    [✅ ENABLED | ⏭️ N/A]

Scripts:
  lint command            package.json scripts       [✅ CONFIGURED | ❌ MISSING]
  lint:fix                package.json scripts       [✅ CONFIGURED | ❌ MISSING]

Integration:
  Pre-commit hook         .pre-commit-config.yaml    [✅ CONFIGURED | ❌ MISSING]
  CI/CD check             .github/workflows/         [✅ CONFIGURED | ❌ MISSING]

Overall: [X issues found]

Recommendations:
  - Enable pedantic rules for stricter checking
  - Add lint-staged for faster pre-commit hooks
```

### Phase 4: Configuration (if --fix or user confirms)

#### Biome Configuration (for JS/TS)

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

**Add npm scripts to `package.json`:**
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

#### Ruff Configuration (for Python)

**Install Ruff:**
```bash
uv add --group dev ruff
```

**Update `pyproject.toml`:**
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

**Add to `pyproject.toml` scripts:**
```toml
[project.scripts]
# Or use directly: uv run ruff check / uv run ruff format
```

#### Clippy Configuration (Rust)

**Update `Cargo.toml`:**
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

**For workspace:**
```toml
[workspace.lints.clippy]
pedantic = { level = "warn", priority = -1 }
all = "warn"

[workspace.lints.rust]
unsafe-code = "deny"
```

**Run Clippy:**
```bash
cargo clippy --all-targets --all-features -- -D warnings
```

### Phase 5: Migration Guides

#### Flake8/isort/black → Ruff Migration

**Step 1: Install Ruff**
```bash
uv add --group dev ruff
```

**Step 2: Configure in `pyproject.toml`** (see Phase 4)

**Step 3: Remove old tools**
```bash
uv remove flake8 isort black pyupgrade
rm .flake8 .isort.cfg
```

**Step 4: Update pre-commit hooks**
```yaml
repos:
  - repo: https://github.com/astral-sh/ruff-pre-commit
    rev: v0.8.4
    hooks:
      - id: ruff
        args: [--fix]
      - id: ruff-format
```

### Phase 6: Pre-commit Integration

**Add to `.pre-commit-config.yaml`:**

**Biome:**
```yaml
repos:
  - repo: https://github.com/biomejs/pre-commit
    rev: v0.4.0
    hooks:
      - id: biome-check
        additional_dependencies: ["@biomejs/biome@1.9.4"]
```

**Ruff:**
```yaml
repos:
  - repo: https://github.com/astral-sh/ruff-pre-commit
    rev: v0.8.4
    hooks:
      - id: ruff
        args: [--fix]
      - id: ruff-format
```

**Clippy:**
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

### Phase 7: CI/CD Integration

**GitHub Actions - Biome:**
```yaml
- name: Run Biome
  run: npx @biomejs/biome ci .
```

**GitHub Actions - Ruff:**
```yaml
- name: Run Ruff
  run: |
    uv run ruff check .
    uv run ruff format --check .
```

**GitHub Actions - Clippy:**
```yaml
- name: Run Clippy
  run: cargo clippy --all-targets --all-features -- -D warnings
```

### Phase 8: Standards Tracking

Update `.project-standards.yaml`:

```yaml
standards_version: "2025.1"
last_configured: "[timestamp]"
components:
  linting: "2025.1"
  linting_tool: "[biome|ruff|clippy]"
  linting_pre_commit: true
  linting_ci: true
```

### Phase 9: Updated Compliance Report

```
Linting Configuration Complete
===============================

Language: TypeScript
Linter: Biome 1.9.4 (modern, fast)

Configuration Applied:
  ✅ biome.json created with recommended rules
  ✅ Linter and formatter integrated
  ✅ Ignore patterns configured
  ✅ Organize imports enabled

Scripts Added:
  ✅ npm run lint (check)
  ✅ npm run lint:fix (fix)
  ✅ npm run format (format)
  ✅ npm run check (CI mode)

Integration:
  ✅ Pre-commit hook configured
  ✅ CI/CD check added

Migration:
  ✅ ESLint removed
  ✅ Configuration imported

Next Steps:
  1. Run linting locally:
     npm run lint

  2. Fix issues automatically:
     npm run lint:fix

  3. Verify CI integration:
     Push changes and check workflow

Documentation: docs/LINTING.md
```

## Flags

| Flag | Description |
|------|-------------|
| `--check-only` | Report status without offering fixes |
| `--fix` | Apply all fixes automatically without prompting |
| `--linter <linter>` | Override linter detection (biome, ruff, clippy) |

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

## See Also

- `/configure:formatting` - Configure code formatting
- `/configure:pre-commit` - Pre-commit hook configuration
- `/lint:check` - Universal linter runner
- `/configure:all` - Run all compliance checks
- **Biome documentation**: https://biomejs.dev
- **Ruff documentation**: https://docs.astral.sh/ruff
- **Clippy documentation**: https://doc.rust-lang.org/clippy
