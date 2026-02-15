---
model: opus
created: 2025-12-16
modified: 2026-02-10
reviewed: 2025-12-16
description: Check and configure pre-commit hooks for project standards
allowed-tools: Glob, Grep, Read, Write, Edit, Bash, AskUserQuestion, TodoWrite, WebSearch, WebFetch
argument-hint: "[--check-only] [--fix] [--type <frontend|infrastructure|python>]"
name: configure-pre-commit
---

# /configure:pre-commit

Check and configure pre-commit hooks against project standards.

## When to Use This Skill

| Use this skill when... | Use another approach when... |
|------------------------|------------------------------|
| Setting up or validating pre-commit hooks | Project doesn't use pre-commit framework (use git hooks directly) |
| Checking compliance with project standards | Just running hooks manually (use `pre-commit run` command) |
| Installing project-type-specific hooks | Hooks are already properly configured |
| Migrating to pre-commit framework | Simple project with no quality checks needed |
| Updating hook configurations for detected tools | Need to disable pre-commit entirely |

## Context

- Pre-commit config: !`test -f .pre-commit-config.yaml && echo "EXISTS" || echo "MISSING"`
- Project standards: !`test -f .project-standards.yaml && echo "EXISTS" || echo "MISSING"`
- Project type in standards: !`grep -m1 "^project_type:" .project-standards.yaml 2>/dev/null`
- Has terraform: !`find . -maxdepth 2 \( -name '*.tf' -o -type d -name 'terraform' \) -print -quit 2>/dev/null`
- Has helm: !`find . -maxdepth 2 -type d -name 'helm' -print -quit 2>/dev/null`
- Has package.json: !`test -f package.json && echo "EXISTS" || echo "MISSING"`
- Has pyproject.toml: !`test -f pyproject.toml && echo "EXISTS" || echo "MISSING"`

## Parameters

Parse from `$ARGUMENTS`:

- `--check-only`: Report status without offering fixes
- `--fix`: Apply all fixes automatically without prompting
- `--type <type>`: Override project type detection (`frontend`, `infrastructure`, `python`)

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
5. **detect-secrets**: [GitHub releases](https://github.com/Yelp/detect-secrets/releases)

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
- `detect-secrets` v1.5.0+

**Python-specific:**
- `ruff-pre-commit` v0.8.4+ (ruff, ruff-format)
- `detect-secrets` v1.5.0+

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

## Agentic Optimizations

| Context | Command |
|---------|---------|
| Check if pre-commit installed | `command -v pre-commit >/dev/null 2>&1 && echo "installed" \|\| echo "missing"` |
| Validate config syntax | `pre-commit validate-config .pre-commit-config.yaml 2>&1` |
| List configured hooks | `grep -E '^\s+- id:' .pre-commit-config.yaml 2>/dev/null \| sed 's/.*id:[[:space:]]*//'` |
| Check hook versions | `pre-commit autoupdate --freeze 2>&1` |
| Quick compliance check | `/configure:pre-commit --check-only` |
| Auto-fix configuration | `/configure:pre-commit --fix` |

## Flags

| Flag | Description |
|------|-------------|
| `--check-only` | Report status without offering fixes |
| `--fix` | Apply all fixes automatically without prompting |
| `--type <type>` | Override project type detection (frontend, infrastructure, python) |

## Error Handling

- **No git repository**: Warn but continue (pre-commit still useful)
- **Invalid YAML**: Report parse error, offer to replace with template
- **Unknown hook repos**: Skip (do not remove custom hooks)
- **Permission errors**: Report and suggest manual fix

## See Also

- `/configure:all` - Run all compliance checks
- `/configure:status` - Quick compliance overview
- `pre-commit-standards` skill - Standard definitions
