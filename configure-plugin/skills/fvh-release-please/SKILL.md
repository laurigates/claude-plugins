---
name: fvh-release-please
description: |
  FVH (Forum Virium Helsinki) release-please standards and configuration. Use when
  configuring release-please workflows, checking release automation compliance, or
  when the user mentions FVH release-please, automated releases, or version management.
---

# FVH Release-Please Standards

## Version: 2025.1

FVH standard release-please configuration for automated semantic versioning and changelog generation.

## Standard Configuration

### GitHub Actions Workflow

**File**: `.github/workflows/release-please.yml`

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

### Configuration Files

**File**: `release-please-config.json`

```json
{
  "packages": {
    ".": {
      "release-type": "node",
      "changelog-sections": [
        {"type": "feat", "section": "Features"},
        {"type": "fix", "section": "Bug Fixes"},
        {"type": "perf", "section": "Performance"},
        {"type": "deps", "section": "Dependencies"},
        {"type": "docs", "section": "Documentation", "hidden": true},
        {"type": "chore", "section": "Miscellaneous", "hidden": true}
      ]
    }
  },
  "plugins": ["node-workspace"]
}
```

**File**: `.release-please-manifest.json`

```json
{
  ".": "0.0.0"
}
```

Note: Version `0.0.0` is a placeholder - release-please updates this automatically.

## Project Type Variations

### Node.js Frontend/Backend

- release-type: `node`
- plugins: `node-workspace`
- Updates: `package.json` version field

### Python Service

- release-type: `python`
- Updates: `pyproject.toml` version field, `__version__` in code

### Infrastructure (Helm)

- release-type: `helm`
- Updates: `Chart.yaml` version field

### Multi-package Repository

```json
{
  "packages": {
    "packages/frontend": {
      "release-type": "node",
      "component": "frontend"
    },
    "packages/backend": {
      "release-type": "node",
      "component": "backend"
    }
  },
  "plugins": [
    "node-workspace",
    {
      "type": "linked-versions",
      "groupName": "workspace",
      "components": ["frontend", "backend"]
    }
  ]
}
```

## Required Components

### Minimum Requirements

1. **Workflow file**: `.github/workflows/release-please.yml`
   - Uses `googleapis/release-please-action@v4`
   - Token: `MY_RELEASE_PLEASE_TOKEN` secret
   - Triggers on push to `main`

2. **Config file**: `release-please-config.json`
   - Valid release-type for project
   - changelog-sections defined

3. **Manifest file**: `.release-please-manifest.json`
   - Lists all packages with current versions

### Token Configuration

The workflow uses `MY_RELEASE_PLEASE_TOKEN` secret (not `GITHUB_TOKEN`) because:
- Allows release PRs to trigger other workflows
- Enables CI checks on release PRs
- Maintains proper audit trail

## Compliance Checking

### Status Levels

| Status | Condition |
|--------|-----------|
| PASS | All three files present with valid configuration |
| WARN | Files present but using deprecated action version |
| FAIL | Missing required files or invalid configuration |

### Validation Rules

1. **Workflow validation**:
   - Action version: `v4` (warn if older)
   - Token: Must use secret, not hardcoded
   - Trigger: Must include `push` to `main`

2. **Config validation**:
   - release-type: Must be valid (node, python, helm, simple)
   - changelog-sections: Must include feat and fix

3. **Manifest validation**:
   - Must be valid JSON
   - Packages must match config

## Protected Files

**IMPORTANT**: Release-please manages these files automatically:
- `CHANGELOG.md` - Never edit manually
- Version fields in `package.json`, `pyproject.toml`, `Chart.yaml`
- `.release-please-manifest.json` - Only edit for initial setup

See `release-please-protection` skill for enforcement.

## Conventional Commits

Release-please requires conventional commit messages:

| Prefix | Release Type | Example |
|--------|--------------|---------|
| `feat:` | Minor | `feat: add user authentication` |
| `fix:` | Patch | `fix: correct login timeout` |
| `feat!:` | Major | `feat!: redesign API` |
| `BREAKING CHANGE:` | Major | In commit body |

## Installation

1. Create workflow file
2. Create config file
3. Create manifest file
4. Add `MY_RELEASE_PLEASE_TOKEN` to repository secrets
5. Ensure pre-commit has conventional-pre-commit hook

## Troubleshooting

### Release PR Not Created

- Check conventional commit format
- Verify workflow has correct permissions
- Ensure token has write access

### Version Not Updated

- Check manifest file is valid JSON
- Verify release-type matches project
- Review release-please logs in Actions

### CI Not Running on Release PR

- Token must be PAT, not GITHUB_TOKEN
- Verify workflow trigger includes pull_request
