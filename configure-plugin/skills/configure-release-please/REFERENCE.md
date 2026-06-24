# configure-release-please Reference

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
      - uses: actions/create-github-app-token@v3
        id: app-token
        with:
          app-id: ${{ vars.RELEASE_PLEASE_APP_ID }}
          private-key: ${{ secrets.RELEASE_PLEASE_PRIVATE_KEY }}
      - uses: googleapis/release-please-action@v4
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
