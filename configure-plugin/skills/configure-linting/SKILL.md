---
model: haiku
created: 2025-12-16
modified: 2026-02-10
reviewed: 2025-12-16
description: Check and configure linting tools (Biome, Ruff, Clippy)
allowed-tools: Glob, Grep, Read, Write, Edit, Bash, AskUserQuestion, TodoWrite, WebSearch, WebFetch
argument-hint: "[--check-only] [--fix] [--linter <biome|ruff|clippy>]"
name: configure-linting
---

# /configure:linting

Check and configure linting tools against modern best practices.

## Context

- Project root: !`pwd`
- Biome config: !`find . -maxdepth 1 -name 'biome.json' -o -name 'biome.jsonc' 2>/dev/null`
- Ruff config: !`grep -l 'tool.ruff' pyproject.toml 2>/dev/null`
- Clippy config: !`grep -l 'lints.clippy' Cargo.toml 2>/dev/null`
- Legacy linters: !`find . -maxdepth 1 \( -name '.eslintrc*' -o -name '.flake8' -o -name '.pylintrc' \) 2>/dev/null`
- Package files: !`find . -maxdepth 1 \( -name 'package.json' -o -name 'pyproject.toml' -o -name 'Cargo.toml' \) 2>/dev/null`
- Pre-commit config: !`find . -maxdepth 1 -name '.pre-commit-config.yaml' 2>/dev/null`
- CI workflows: !`find .github/workflows -maxdepth 1 -name '*.yml' 2>/dev/null`

## Parameters

Parse from `$ARGUMENTS`:

- `--check-only`: Report linting compliance status without modifications
- `--fix`: Apply all fixes automatically without prompting
- `--linter <biome|ruff|clippy>`: Override auto-detection and force specific linter

**Modern linting preferences:**
- **JavaScript/TypeScript**: Biome (unified linter + formatter, fast)
- **Python**: Ruff (replaces flake8, isort, pyupgrade)
- **Rust**: Clippy with workspace lints

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

Apply configuration using templates from [REFERENCE.md](REFERENCE.md).

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

If legacy linters are detected (ESLint, Flake8, etc.), offer migration. See migration guides in [REFERENCE.md](REFERENCE.md).

### Step 6: Configure pre-commit and CI integration

1. Add linter pre-commit hook to `.pre-commit-config.yaml`
2. Add linter CI check to GitHub Actions workflow
3. Use templates from [REFERENCE.md](REFERENCE.md)

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

For detailed configuration templates, migration guides, and CI integration patterns, see [REFERENCE.md](REFERENCE.md).

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
- `/configure:all` - Run all compliance checks
- **Biome documentation**: https://biomejs.dev
- **Ruff documentation**: https://docs.astral.sh/ruff
- **Clippy documentation**: https://doc.rust-lang.org/clippy
