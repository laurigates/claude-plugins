---
description: Check and configure release-please workflow for FVH standards
allowed-tools: Glob, Grep, Read, Write, Edit, Bash, AskUserQuestion, TodoWrite, WebSearch, WebFetch
argument-hint: "[--check-only] [--fix]"
---

# /configure:release-please

Check and configure release-please against FVH (Forum Virium Helsinki) standards.

## Context

This command validates release-please configuration and workflow against FVH standards.

**Skills referenced**: `fvh-release-please`, `release-please-protection`

## Version Checking

**CRITICAL**: Before configuring release-please, verify latest action version:

1. **release-please-action**: Check [GitHub releases](https://github.com/google-github-actions/release-please-action/releases)
2. **release-please CLI**: Check [GitHub releases](https://github.com/googleapis/release-please/releases)

Use WebSearch or WebFetch to verify current versions before configuring release-please.

## Workflow

### Phase 1: Configuration Detection

Check for required files:

1. `.github/workflows/release-please.yml` - GitHub Actions workflow
2. `release-please-config.json` - Release configuration
3. `.release-please-manifest.json` - Version manifest

### Phase 2: Project Type Detection

Determine appropriate release-type:

- **node**: Has `package.json` (default for frontend/backend apps)
- **python**: Has `pyproject.toml` without `package.json`
- **helm**: Infrastructure with Helm charts
- **simple**: Generic projects

### Phase 3: Compliance Analysis

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

### Phase 4: Report Generation

```
FVH Release-Please Compliance Report
====================================
Project Type: node (detected)

File Status:
  Workflow        .github/workflows/release-please.yml  ✅ PASS
  Config          release-please-config.json            ✅ PASS
  Manifest        .release-please-manifest.json         ✅ PASS

Configuration Checks:
  Action version  v4                                    ✅ PASS
  Token           MY_RELEASE_PLEASE_TOKEN               ✅ PASS
  Release type    node                                  ✅ PASS
  Changelog       feat, fix sections                    ✅ PASS
  Plugin          node-workspace                        ✅ PASS

Overall: Fully compliant
```

### Phase 5: Configuration (If Requested)

If `--fix` flag or user confirms:

1. **Missing workflow**: Create from FVH template
2. **Missing config**: Create with detected release-type
3. **Missing manifest**: Create with initial version `0.0.0`
4. **Outdated action**: Update to v4
5. **Wrong token**: Update to use MY_RELEASE_PLEASE_TOKEN

### Phase 6: Standards Tracking

Update `.fvh-standards.yaml`:

```yaml
components:
  release-please: "2025.1"
```

## FVH Standard Templates

### Workflow Template

```yaml
name: Release Please

on:
  push:
    branches:
      - main

permissions:
  contents: write
  pull-requests: write

jobs:
  release-please:
    runs-on: ubuntu-latest
    steps:
      - uses: googleapis/release-please-action@v4
        with:
          token: ${{ secrets.MY_RELEASE_PLEASE_TOKEN }}
```

### Config Template (Node)

```json
{
  "packages": {
    ".": {
      "release-type": "node",
      "changelog-sections": [
        {"type": "feat", "section": "Features"},
        {"type": "fix", "section": "Bug Fixes"},
        {"type": "perf", "section": "Performance"},
        {"type": "deps", "section": "Dependencies"}
      ]
    }
  },
  "plugins": ["node-workspace"]
}
```

### Manifest Template

```json
{
  ".": "0.0.0"
}
```

## Flags

| Flag | Description |
|------|-------------|
| `--check-only` | Report status without offering fixes |
| `--fix` | Apply all fixes automatically |

## Important Notes

- Requires `MY_RELEASE_PLEASE_TOKEN` secret in repository settings
- CHANGELOG.md is managed by release-please - never edit manually
- Version fields in package.json/pyproject.toml are managed automatically
- Works with `conventional-pre-commit` hook for commit validation

## See Also

- `/configure:pre-commit` - Ensure conventional commits hook
- `/configure:all` - Run all FVH compliance checks
- `release-please-protection` skill - Protected file rules
