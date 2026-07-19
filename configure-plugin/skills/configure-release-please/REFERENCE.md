# configure-release-please Reference

Standard release-please configuration (v2025.1) for automated semantic
versioning and changelog generation. (Absorbed the former
`release-please-standards` reference skill; the **monorepo** strategy —
component tags, per-package `extra-files`, tag migration — lives in
`git-plugin:release-please-configuration`.)

## Compliance Report Format

```
Release-Please Compliance Report
====================================
Project Type: node (detected)

File Status:
  Workflow        .github/workflows/release-please.yml  [PASS | MISSING]
  Config          release-please-config.json            [PASS | MISSING]
  Manifest        .release-please-manifest.json         [PASS | MISSING]

Configuration Checks:
  Action version  v5                                    [PASS | OUTDATED]
  Token           App token / MY_RELEASE_PLEASE_TOKEN    [PASS | WRONG TOKEN]
  Release type    node                                  [PASS | WRONG TYPE]
  Changelog       feat, fix sections                    [PASS | INCOMPLETE]
  Plugin          node-workspace                        [PASS | MISSING]

Overall: Fully compliant | X issues found
```

## Standard Templates

### Workflow Template — GitHub App token (preferred)

This is the laurigates org standard. `create-github-app-token` mints a
short-lived token from the `laurigates-release-please` GitHub App;
`RELEASE_PLEASE_APP_ID` (variable) and `RELEASE_PLEASE_PRIVATE_KEY` (secret)
are provisioned by gitops on repos flagged `release_please = true`.

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
      - uses: actions/create-github-app-token@v3.2.0
        id: app-token
        with:
          app-id: ${{ vars.RELEASE_PLEASE_APP_ID }}
          private-key: ${{ secrets.RELEASE_PLEASE_PRIVATE_KEY }}
      - uses: googleapis/release-please-action@v4.4.1
        with:
          token: ${{ steps.app-token.outputs.token }}
```

### Workflow Template — PAT (legacy)

Still valid where the GitHub App isn't set up, but diverges from the org
standard and won't consume the gitops-provisioned App credentials.

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
      - uses: googleapis/release-please-action@v5
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

Version `0.0.0` is a placeholder — release-please updates it automatically.

## Project Type Variations

| Project type | release-type | Updates |
|--------------|--------------|---------|
| Node.js frontend/backend | `node` (+ `node-workspace` plugin) | `package.json` version field |
| Python service | `python` | `pyproject.toml` version field, `__version__` in code |
| Infrastructure (Helm) | `helm` | `Chart.yaml` version field |
| Multi-package repo | per-package `component` + root `include-component-in-tag: true` | See `git-plugin:release-please-configuration` for the full monorepo strategy |

## Token Configuration

The workflow uses a dedicated release token (not `GITHUB_TOKEN`) so release
PRs can trigger other workflows, CI runs on release PRs, and the audit trail
stays clean. Two accepted patterns:

| Pattern | How | When |
|---------|-----|------|
| **GitHub App token (preferred)** | `actions/create-github-app-token` → `app-id: ${{ vars.RELEASE_PLEASE_APP_ID }}`, `private-key: ${{ secrets.RELEASE_PLEASE_PRIVATE_KEY }}`, passed as `token: ${{ steps.app-token.outputs.token }}` | laurigates org standard — credentials are gitops-provisioned on `release_please = true` repos |
| **PAT (legacy)** | `token: ${{ secrets.MY_RELEASE_PLEASE_TOKEN }}` | Where the GitHub App isn't set up |

A workflow already using the App-token pattern is compliant — do not flag it
to switch to `MY_RELEASE_PLEASE_TOKEN`.

## Validation Rules

| Status | Condition |
|--------|-----------|
| PASS | All three files present with valid configuration |
| WARN | Files present but using a deprecated action version (older than v5) |
| FAIL | Missing required files or invalid configuration |

1. **Workflow**: action version v5 (warn if older); token from a secret,
   never hardcoded; triggers on `push` to `main`
2. **Config**: valid release-type (`node`, `python`, `helm`, `simple`);
   changelog-sections include at least `feat` and `fix`
3. **Manifest**: valid JSON; packages match the config

## Protected Files

Release-please manages these automatically — never edit them manually:
`CHANGELOG.md`, version fields in `package.json` / `pyproject.toml` /
`Chart.yaml`, and `.release-please-manifest.json` (initial setup only). See
`git-plugin:release-please-protection` for enforcement.

## Conventional Commits

| Prefix | Release Type | Example |
|--------|--------------|---------|
| `feat:` | Minor | `feat: add user authentication` |
| `fix:` | Patch | `fix: correct login timeout` |
| `feat!:` | Major | `feat!: redesign API` |
| `BREAKING CHANGE:` | Major | In commit body |

## Installation Steps

1. Create workflow, config, and manifest files (templates above)
2. Provide the release token — preferred: `RELEASE_PLEASE_APP_ID` variable +
   `RELEASE_PLEASE_PRIVATE_KEY` secret (gitops provisions these on
   `release_please = true` repos); legacy: `MY_RELEASE_PLEASE_TOKEN` secret
3. Ensure pre-commit has the conventional-pre-commit hook

## Troubleshooting

| Symptom | Check |
|---------|-------|
| Release PR not created | Conventional commit format; workflow permissions; token has write access |
| Version not updated | Manifest is valid JSON; release-type matches project; release-please logs in Actions |
| CI not running on release PR | Token must be a dedicated release token (App token or PAT), not `GITHUB_TOKEN` |
