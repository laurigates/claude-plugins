---
model: haiku
created: 2025-12-16
modified: 2026-02-10
reviewed: 2025-12-16
description: Check and configure EditorConfig and VS Code workspace settings
allowed-tools: Glob, Grep, Read, Write, Edit, Bash, AskUserQuestion, TodoWrite
argument-hint: "[--check-only] [--fix]"
name: configure-editor
---

# /configure:editor

Check and configure editor settings for consistency across the team.

## When to Use This Skill

| Use this skill when... | Use another approach when... |
|------------------------|------------------------------|
| Setting up consistent editor configuration across a team | Personal editor preferences only (configure in user settings) |
| Checking EditorConfig or VS Code workspace compliance | Just viewing existing .editorconfig (use Read tool) |
| Configuring format-on-save for detected languages | Project doesn't use VS Code (configure for other editors manually) |
| Adding recommended VS Code extensions for project tools | Extensions are already properly configured |
| Setting up debug configurations and tasks | Simple project with no debugging needs |

## Context

- EditorConfig: !`find . -maxdepth 1 -name \'.editorconfig\' 2>/dev/null`
- VS Code settings: !`find . -maxdepth 1 -name \'.vscode/settings.json\' 2>/dev/null`
- VS Code extensions: !`find . -maxdepth 1 -name \'.vscode/extensions.json\' 2>/dev/null`
- VS Code launch: !`find . -maxdepth 1 -name \'.vscode/launch.json\' 2>/dev/null`
- VS Code tasks: !`find . -maxdepth 1 -name \'.vscode/tasks.json\' 2>/dev/null`
- Project languages: !`find . -maxdepth 1 \( -name 'package.json' -o -name 'tsconfig.json' -o -name 'pyproject.toml' -o -name 'Cargo.toml' -o -name 'biome.json' \) 2>/dev/null`
- Project standards: !`find . -maxdepth 1 -name \'.project-standards.yaml\' 2>/dev/null`

## Parameters

Parse from `$ARGUMENTS`:

- `--check-only`: Report compliance status without modifications
- `--fix`: Apply all fixes automatically without prompting

## Execution

Execute this editor configuration workflow:

### Step 1: Detect project languages and tools

Check for language indicators:

| Indicator | Language/Tool | Configuration Needed |
|-----------|---------------|---------------------|
| `package.json` | JavaScript/TypeScript | Biome |
| `tsconfig.json` | TypeScript | TypeScript extension |
| `pyproject.toml` | Python | Ruff, Python extension |
| `Cargo.toml` | Rust | rust-analyzer |
| `biome.json` | Biome formatter/linter | Biome extension |

### Step 2: Analyze current editor configuration

Check existing configuration against these requirements:

**EditorConfig:**
1. Verify `.editorconfig` exists
2. Check root directive, charset, end-of-line, final newline, trim whitespace
3. Check language-specific sections match detected languages

**VS Code Settings:**
1. Verify `.vscode/settings.json` exists
2. Check format-on-save, default formatters per language, language-specific settings

**VS Code Extensions:**
1. Verify `.vscode/extensions.json` exists
2. Check recommended extensions match project tools

### Step 3: Generate compliance report

Print a formatted compliance report showing status of each check:

```
Editor Configuration Compliance Report
=======================================
Project: [name]
Languages: [detected]
Detected Tools: [detected]

EditorConfig:     [status per check]
VS Code Settings: [status per check]
VS Code Extensions: [status per check]

Overall: [X issues found]
Recommendations: [list specific fixes]
```

If `--check-only`, stop here.

### Step 4: Configure editor files (if --fix or user confirms)

Apply fixes based on detected languages. Use configurations from [REFERENCE.md](REFERENCE.md).

1. Create or update `.editorconfig` with language-specific sections
2. Create or update `.vscode/settings.json` with format-on-save and per-language formatters
3. Create or update `.vscode/extensions.json` with recommended extensions for detected tools
4. Add language-specific settings (TypeScript import preferences, Python interpreter, Rust clippy)

### Step 5: Create launch and task configurations

1. Create `.vscode/launch.json` with debug configurations for detected languages
2. Create `.vscode/tasks.json` with build/test/lint tasks

### Step 6: Update standards tracking

Update `.project-standards.yaml`:

```yaml
components:
  editor: "2025.1"
  editor_config: true
  vscode_settings: true
  vscode_extensions: true
```

### Step 7: Create documentation

Create `docs/EDITOR_SETUP.md` with quick start instructions for the team covering VS Code setup, recommended extensions, and troubleshooting.

### Step 8: Print completion report

Print a summary of all changes made, including files created/updated, extensions recommended, and next steps for the team.

For detailed configuration templates and language-specific settings, see [REFERENCE.md](REFERENCE.md).

## Agentic Optimizations

| Context | Command |
|---------|---------|
| Check if EditorConfig exists | `test -f .editorconfig && echo "exists" \|\| echo "missing"` |
| Validate EditorConfig syntax | `editorconfig-checker .editorconfig 2>&1` (if installed) |
| Check VS Code settings exist | `test -f .vscode/settings.json && jq empty .vscode/settings.json 2>&1` |
| List detected languages | `find . -maxdepth 1 \( -name 'package.json' -o -name 'pyproject.toml' -o -name 'Cargo.toml' \) -exec basename {} \;` |
| Quick compliance check | `/configure:editor --check-only` |
| Auto-fix all issues | `/configure:editor --fix` |

## Flags

| Flag | Description |
|------|-------------|
| `--check-only` | Report status without offering fixes |
| `--fix` | Apply all fixes automatically without prompting |

## Examples

```bash
# Check compliance and offer fixes
/configure:editor

# Check only, no modifications
/configure:editor --check-only

# Auto-fix all issues
/configure:editor --fix
```

## Error Handling

- **No language detected**: Create minimal EditorConfig
- **Conflicting formatters**: Warn about duplicate formatter configs
- **Invalid JSON**: Report parse error, offer to replace with template

## See Also

- `/configure:formatting` - Configure code formatting
- `/configure:linting` - Configure linting tools
- `/configure:all` - Run all compliance checks
- **EditorConfig documentation**: https://editorconfig.org
- **VS Code settings reference**: https://code.visualstudio.com/docs/getstarted/settings
