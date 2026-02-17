---
model: haiku
created: 2025-12-16
modified: 2026-02-11
reviewed: 2025-12-16
description: Check and configure release-please workflow for project standards
allowed-tools: Glob, Grep, Read, Write, Edit, Bash, AskUserQuestion, TodoWrite, WebSearch, WebFetch
argument-hint: "[--check-only] [--fix]"
name: configure-release-please
---

# /configure:release-please

Check and configure release-please against project standards.

## When to Use This Skill

| Use this skill when... | Use another approach when... |
|------------------------|------------------------------|
| Setting up release-please for a new project from scratch | Manually editing CHANGELOG.md or version fields — use conventional commits instead |
| Auditing existing release-please configuration for compliance | Creating a one-off release — use `gh release create` directly |
| Upgrading release-please-action to the latest version | Debugging a failed release PR — check GitHub Actions logs directly |
| Ensuring workflow uses correct token (MY_RELEASE_PLEASE_TOKEN) | Managing npm/PyPI publishing — configure separate publish workflows |
| Adding a new package to a monorepo release-please configuration | Writing conventional commit messages — use `/git:commit` skill |

## Context

- Workflow file: !`find .github/workflows -maxdepth 1 -name 'release-please*' 2>/dev/null`
- Config file: !`find . -maxdepth 1 -name \'release-please-config.json\' 2>/dev/null`
- Manifest file: !`find . -maxdepth 1 -name \'.release-please-manifest.json\' 2>/dev/null`
- Package files: !`find . -maxdepth 1 \( -name 'package.json' -o -name 'pyproject.toml' -o -name 'Cargo.toml' -o -name 'go.mod' \) 2>/dev/null`
- Workflows dir: !`find . -maxdepth 1 -type d -name \'.github/workflows\' 2>/dev/null`

**Skills referenced**: `release-please-standards`, `release-please-protection`

## Parameters

Parse from command arguments:

- `--check-only`: Report status without offering fixes
- `--fix`: Apply all fixes automatically

## Execution

Execute this release-please configuration check:

### Step 1: Fetch latest action version

Run this command to get the current release-please-action version dynamically:

```bash
curl -s https://api.github.com/repos/googleapis/release-please-action/releases/latest | jq -r '.tag_name'
```

**References**:
- [release-please-action releases](https://github.com/googleapis/release-please-action/releases)
- [release-please CLI releases](https://github.com/googleapis/release-please/releases)

### Step 2: Detect project type

Determine appropriate release-type from detected package files:

- **node**: Has `package.json` (default for frontend/backend apps)
- **python**: Has `pyproject.toml` without `package.json`
- **helm**: Infrastructure with Helm charts
- **simple**: Generic projects

### Step 3: Analyze compliance

**Workflow file checks**:
- Action version: `googleapis/release-please-action@v4`
- Token: Uses `MY_RELEASE_PLEASE_TOKEN` secret (not GITHUB_TOKEN)
- Trigger: Push to `main` branch
- Permissions: `contents: write`, `pull-requests: write`

**Config file checks**:
- Valid release-type for project
- changelog-sections includes `feat` and `fix`
- Appropriate plugins (e.g., `node-workspace` for Node projects)

**Manifest file checks**:
- Valid JSON structure
- Package paths match config

### Step 4: Generate compliance report

Print a formatted compliance report showing file status and configuration check results. If `--check-only` is set, stop here.

For the report format, see [REFERENCE.md](REFERENCE.md).

### Step 5: Apply configuration (if --fix or user confirms)

1. **Missing workflow**: Create from standard template
2. **Missing config**: Create with detected release-type
3. **Missing manifest**: Create with initial version `0.0.0`
4. **Outdated action**: Update to v4
5. **Wrong token**: Update to use MY_RELEASE_PLEASE_TOKEN

For standard templates, see [REFERENCE.md](REFERENCE.md).

### Step 6: Update standards tracking

Update `.project-standards.yaml`:

```yaml
components:
  release-please: "2025.1"
```

## Agentic Optimizations

| Context | Command |
|---------|---------|
| Quick compliance check | `/configure:release-please --check-only` |
| Auto-fix all issues | `/configure:release-please --fix` |
| Check latest action version | `curl -s https://api.github.com/repos/googleapis/release-please-action/releases/latest \| jq -r '.tag_name'` |
| Verify config JSON | `jq . release-please-config.json` |
| Verify manifest JSON | `jq . .release-please-manifest.json` |
| Check workflow exists | `find .github/workflows -name 'release-please*'` |

## Important Notes

- Requires `MY_RELEASE_PLEASE_TOKEN` secret in repository settings
- CHANGELOG.md is managed by release-please - never edit manually
- Version fields in package.json/pyproject.toml are managed automatically
- Works with `conventional-pre-commit` hook for commit validation

## See Also

- `/configure:pre-commit` - Ensure conventional commits hook
- `/configure:all` - Run all compliance checks
- `release-please-protection` skill - Protected file rules
