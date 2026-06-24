---
created: 2025-12-16
modified: 2026-06-24
reviewed: 2026-06-24
name: release-please-standards
description: "release-please standards and configuration reference. Use when configuring release workflows, checking automation compliance, or working with version bumps."
user-invocable: false
allowed-tools: Bash, Read, Write, Edit, Grep, Glob
---

# Release-Please Standards

## When to Use This Skill

| Use this skill when... | Use the alternative instead when... |
|---|---|
| You need the canonical release-please workflow, manifest, and config-file shape | You want to audit or set up release-please end-to-end as an interactive workflow — use `configure-release-please` |
| You are checking an existing release-please setup against documented conventions | You want runtime detection of repo type and existing config before changes — use `configure-release-please` |
| Another skill needs to cite the standard release-please configuration | You are configuring **monorepo** component tags, per-package `extra-files`, or shared→component tag migration — use `git-plugin:release-please-configuration` |

## Version: 2025.1

Standard release-please configuration for automated semantic versioning and changelog generation.

## Standard Configuration

### GitHub Actions Workflow

**File**: `.github/workflows/release-please.yml`

The release PR needs a token that can trigger other workflows. Two patterns;
the **GitHub App token is preferred** (the laurigates org standard), with the
`MY_RELEASE_PLEASE_TOKEN` PAT kept as a legacy fallback.

**GitHub App token (preferred)** — `create-github-app-token` mints a token from
`RELEASE_PLEASE_APP_ID` (variable) and `RELEASE_PLEASE_PRIVATE_KEY` (secret),
which gitops provisions on repos flagged `release_please = true`:

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
      - uses: actions/create-github-app-token@v3
        id: app-token
        with:
          app-id: ${{ vars.RELEASE_PLEASE_APP_ID }}
          private-key: ${{ secrets.RELEASE_PLEASE_PRIVATE_KEY }}
      - uses: googleapis/release-please-action@v4
        with:
          token: ${{ steps.app-token.outputs.token }}
```

**PAT (legacy)** — a `MY_RELEASE_PLEASE_TOKEN` secret in repository settings:

```yaml
      - uses: googleapis/release-please-action@v5
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

Monorepos need `component` on every package and `include-component-in-tag: true`
at the root, plus per-package `extra-files` and (optionally) the
`linked-versions` plugin:

```json
{
  "packages": {
    "packages/frontend": {"release-type": "node", "component": "frontend"},
    "packages/backend": {"release-type": "node", "component": "backend"}
  },
  "plugins": ["node-workspace"]
}
```

For the full monorepo strategy — component tagging, duplicate-tag / multiple-paths
fixes, per-package `extra-files` path rules, linked versions, adding a package,
and shared→component tag migration — see `git-plugin:release-please-configuration`.

## Required Components

### Minimum Requirements

1. **Workflow file**: `.github/workflows/release-please.yml`
   - Uses `googleapis/release-please-action@v5`
   - Token: GitHub App token (preferred) or `MY_RELEASE_PLEASE_TOKEN` secret
   - Triggers on push to `main`

2. **Config file**: `release-please-config.json`
   - Valid release-type for project
   - changelog-sections defined

3. **Manifest file**: `.release-please-manifest.json`
   - Lists all packages with current versions

### Token Configuration

The workflow uses a dedicated release token (not `GITHUB_TOKEN`) because:
- Allows release PRs to trigger other workflows
- Enables CI checks on release PRs
- Maintains proper audit trail

Two token patterns are accepted:

| Pattern | How | When |
|---------|-----|------|
| **GitHub App token (preferred)** | `actions/create-github-app-token` → `app-id: ${{ vars.RELEASE_PLEASE_APP_ID }}`, `private-key: ${{ secrets.RELEASE_PLEASE_PRIVATE_KEY }}`, passed as `token: ${{ steps.app-token.outputs.token }}` | laurigates org standard — credentials are gitops-provisioned on `release_please = true` repos |
| **PAT (legacy)** | `token: ${{ secrets.MY_RELEASE_PLEASE_TOKEN }}` | Where the GitHub App isn't set up |

A workflow already using the App-token pattern is compliant — do not flag it to
switch to `MY_RELEASE_PLEASE_TOKEN`.

## Compliance Checking

### Status Levels

| Status | Condition |
|--------|-----------|
| PASS | All three files present with valid configuration |
| WARN | Files present but using deprecated action version (older than v5) |
| FAIL | Missing required files or invalid configuration |

### Validation Rules

1. **Workflow validation**:
   - Action version: `v5` (warn if older)
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
4. Provide the release token — preferred: set the `RELEASE_PLEASE_APP_ID`
   variable + `RELEASE_PLEASE_PRIVATE_KEY` secret (gitops provisions these on
   `release_please = true` repos); legacy: add `MY_RELEASE_PLEASE_TOKEN` to
   repository secrets
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

- Token must be a dedicated release token (GitHub App token or PAT), not `GITHUB_TOKEN`
- Verify workflow trigger includes pull_request
