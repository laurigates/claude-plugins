---
created: 2025-12-16
modified: 2026-06-18
reviewed: 2026-06-10
description: "Biome formatter for JS/TS/JSON/CSS — the modern Prettier/ESLint replacement. Also Ruff (Python) and rustfmt. Use when setting up formatting, replacing Prettier, or wiring CI format checks."
allowed-tools: Glob, Grep, Read, Write, Edit, Bash, AskUserQuestion, TodoWrite, WebSearch, WebFetch
args: "[--check-only] [--fix] [--formatter <biome|ruff|rustfmt>]"
argument-hint: "[--check-only] [--fix] [--formatter <biome|ruff|rustfmt>]"
name: configure-formatting
---

# /configure:formatting

Check and configure code formatting tools against modern best practices.

## When to Use This Skill

| Use this skill when... | Use another approach when... |
|------------------------|------------------------------|
| Setting up Biome, Ruff format, or rustfmt for a project | Running an existing formatter (`biome format`, `ruff format`) |
| Migrating from Prettier or ESLint to Biome, or Black to Ruff | Fixing individual formatting issues in specific files |
| Auditing formatter configuration for completeness and best practices | Configuring linting rules (`/configure:linting` instead) |
| Adding format-on-save and CI format checks | Setting up pre-commit hooks only (`/configure:pre-commit` instead) |
| Standardizing formatting settings across a monorepo | Editing `.editorconfig` or `.vscode/settings.json` manually |

## Context

- Biome config: !`find . -maxdepth 1 -name \'biome.json\'`
- Prettier config: !`find . -maxdepth 1 \( -name '.prettierrc*' -o -name 'prettier.config.*' \)`
- Ruff config: !`find . -maxdepth 1 -name 'pyproject.toml' -exec grep -l 'tool.ruff.format' {} +`
- Black config: !`find . -maxdepth 1 -name 'pyproject.toml' -exec grep -l 'tool.black' {} +`
- Rustfmt config: !`find . -maxdepth 1 \( -name 'rustfmt.toml' -o -name '.rustfmt.toml' \)`
- EditorConfig: !`find . -maxdepth 1 -name \'.editorconfig\'`
- Package JSON: !`find . -maxdepth 1 -name \'package.json\'`
- Python project: !`find . -maxdepth 1 -name \'pyproject.toml\'`
- Rust project: !`find . -maxdepth 1 -name \'Cargo.toml\'`
- Pre-commit: !`find . -maxdepth 1 -name \'.pre-commit-config.yaml\'`
- Project standards: !`find . -maxdepth 1 -name \'.project-standards.yaml\'`

## Parameters

Parse from `$ARGUMENTS`:

- `--check-only`: Report compliance status without modifications
- `--fix`: Apply all fixes automatically without prompting
- `--formatter <formatter>`: Override formatter detection (biome, ruff, rustfmt)

## Version Checking

**CRITICAL**: Before flagging outdated formatters, verify latest releases using WebSearch or WebFetch:

1. **Biome**: Check [biomejs.dev](https://biomejs.dev/) or [GitHub releases](https://github.com/biomejs/biome/releases)
2. **Ruff**: Check [docs.astral.sh/ruff](https://docs.astral.sh/ruff/) or [GitHub releases](https://github.com/astral-sh/ruff/releases)
3. **rustfmt**: Bundled with Rust toolchain - check [Rust releases](https://releases.rs/)

## Execution

Execute this code formatting configuration workflow:

### Step 1: Detect formatters and integration state

Run the detection script to scan the project for formatter config files,
script/hook/CI presence, and a recommendation over the detected booleans:

```bash
bash "${CLAUDE_SKILL_DIR}/scripts/configure-formatting.sh" --home-dir "$HOME" --project-dir "$(pwd)"
```

Parse `STATUS=` and the `ISSUES:` block from the output. The `KEY=VALUE` lines
report formatter detection (`BIOME`, `PRETTIER`, `RUFF_FORMAT`, `BLACK`,
`RUSTFMT`, `EDITORCONFIG`), integration signals (`FORMAT_SCRIPT`,
`PRE_COMMIT_FORMAT`, `CI_FORMAT`), and a `RECOMMENDATION` of `configured`
(a modern formatter is set up), `migrate` (a legacy formatter wants migration to
Biome/Ruff), or `setup` (no formatter detected).

**Modern formatting preferences:**
- **JavaScript/TypeScript**: Biome (replaces Prettier + ESLint). On `RECOMMENDATION=migrate` with Prettier present, offer migration to Biome — do not configure Prettier as the target formatter.
- **Python**: Ruff format (replaces Black)
- **Rust**: rustfmt (standard)

### Step 2: Generate compliance report

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

### Step 3: Install and configure formatter (if --fix or user confirms)

Based on detected language and formatter preference, install and configure. Use configuration templates from [REFERENCE.md](REFERENCE.md).

1. Install formatter package
2. Create configuration file (biome.json, pyproject.toml section, rustfmt.toml)
3. Add format scripts to package.json or Makefile/justfile
4. Configure ignore patterns in the formatter config (e.g. `files.includes` in biome.json)

### Step 4: Create EditorConfig integration

Create or update `.editorconfig` with settings matching the formatter configuration.

### Step 5: Handle migrations (if applicable)

If legacy formatter detected (Prettier -> Biome, Black -> Ruff):
1. Import existing configuration
2. Install new formatter
3. Remove old formatter
4. Update scripts
5. Update pre-commit hooks

Use migration guides from [REFERENCE.md](REFERENCE.md).

### Step 6: Configure pre-commit hooks

Add formatter to `.pre-commit-config.yaml` using the appropriate hook repository.

### Step 7: Configure CI/CD integration

Add format check step to GitHub Actions workflow.

### Step 8: Configure editor integration

Create or update `.vscode/settings.json` with format-on-save and `.vscode/extensions.json` with formatter extension.

### Step 9: Update standards tracking

Update `.project-standards.yaml`:

```yaml
components:
  formatting: "2025.1"
  formatting_tool: "[biome|ruff|rustfmt]"
  formatting_pre_commit: true
  formatting_ci: true
```

### Step 10: Print completion report

Print a summary of changes made, scripts added, and next steps (run format, verify CI, enable format-on-save).

For detailed configuration templates, migration guides, and pre-commit configurations, see [REFERENCE.md](REFERENCE.md).

## Agentic Optimizations

| Context | Command |
|---------|---------|
| Quick compliance check | `/configure:formatting --check-only` |
| Auto-fix all issues | `/configure:formatting --fix` |
| Check Biome formatting | `biome format --check --reporter=github` |
| Check Ruff formatting | `ruff format --check --output-format=github` |
| Check rustfmt formatting | `cargo fmt --check 2>&1 | head -20` |

## Flags

| Flag | Description |
|------|-------------|
| `--check-only` | Report status without offering fixes |
| `--fix` | Apply all fixes automatically without prompting |
| `--formatter <formatter>` | Override formatter detection (biome, ruff, rustfmt) |

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
