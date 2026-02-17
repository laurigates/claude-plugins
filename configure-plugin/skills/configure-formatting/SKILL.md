---
model: haiku
created: 2025-12-16
modified: 2026-02-10
reviewed: 2025-12-16
description: Check and configure code formatting (Biome, Prettier, Ruff, rustfmt)
allowed-tools: Glob, Grep, Read, Write, Edit, Bash, AskUserQuestion, TodoWrite, WebSearch, WebFetch
argument-hint: "[--check-only] [--fix] [--formatter <biome|prettier|ruff|rustfmt>]"
name: configure-formatting
---

# /configure:formatting

Check and configure code formatting tools against modern best practices.

## When to Use This Skill

| Use this skill when... | Use another approach when... |
|------------------------|------------------------------|
| Setting up Biome, Prettier, Ruff format, or rustfmt for a project | Running an existing formatter (`biome format`, `ruff format`) |
| Migrating from Prettier to Biome or Black to Ruff | Fixing individual formatting issues in specific files |
| Auditing formatter configuration for completeness and best practices | Configuring linting rules (`/configure:linting` instead) |
| Adding format-on-save and CI format checks | Setting up pre-commit hooks only (`/configure:pre-commit` instead) |
| Standardizing formatting settings across a monorepo | Editing `.editorconfig` or `.vscode/settings.json` manually |

## Context

- Biome config: !`find . -maxdepth 1 -name \'biome.json\' 2>/dev/null`
- Prettier config: !`find . -maxdepth 1 \( -name '.prettierrc*' -o -name 'prettier.config.*' \) 2>/dev/null`
- Ruff config: !`grep -l 'tool.ruff.format' pyproject.toml 2>/dev/null`
- Black config: !`grep -l 'tool.black' pyproject.toml 2>/dev/null`
- Rustfmt config: !`find . -maxdepth 1 \( -name 'rustfmt.toml' -o -name '.rustfmt.toml' \) 2>/dev/null`
- EditorConfig: !`find . -maxdepth 1 -name \'.editorconfig\' 2>/dev/null`
- Package JSON: !`find . -maxdepth 1 -name \'package.json\' 2>/dev/null`
- Python project: !`find . -maxdepth 1 -name \'pyproject.toml\' 2>/dev/null`
- Rust project: !`find . -maxdepth 1 -name \'Cargo.toml\' 2>/dev/null`
- Pre-commit: !`find . -maxdepth 1 -name \'.pre-commit-config.yaml\' 2>/dev/null`
- Project standards: !`find . -maxdepth 1 -name \'.project-standards.yaml\' 2>/dev/null`

## Parameters

Parse from `$ARGUMENTS`:

- `--check-only`: Report compliance status without modifications
- `--fix`: Apply all fixes automatically without prompting
- `--formatter <formatter>`: Override formatter detection (biome, prettier, ruff, rustfmt)

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

Based on detected language and formatter preference, install and configure. Use configuration templates from [REFERENCE.md](REFERENCE.md).

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

Use migration guides from [REFERENCE.md](REFERENCE.md).

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

For detailed configuration templates, migration guides, and pre-commit configurations, see [REFERENCE.md](REFERENCE.md).

## Agentic Optimizations

| Context | Command |
|---------|---------|
| Quick compliance check | `/configure:formatting --check-only` |
| Auto-fix all issues | `/configure:formatting --fix` |
| Check Biome formatting | `biome format --check --reporter=github` |
| Check Prettier formatting | `npx prettier --check . 2>&1 | tail -5` |
| Check Ruff formatting | `ruff format --check --output-format=github` |
| Check rustfmt formatting | `cargo fmt --check 2>&1 | head -20` |

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
- `/configure:all` - Run all compliance checks
- **Biome documentation**: https://biomejs.dev
- **Ruff documentation**: https://docs.astral.sh/ruff
- **rustfmt documentation**: https://rust-lang.github.io/rustfmt
