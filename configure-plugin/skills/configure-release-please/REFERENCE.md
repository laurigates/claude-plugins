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
  Action version  v4                                    [PASS | OUTDATED]
  Token           MY_RELEASE_PLEASE_TOKEN               [PASS | WRONG TOKEN]
  Release type    node                                  [PASS | WRONG TYPE]
  Changelog       feat, fix sections                    [PASS | INCOMPLETE]
  Plugin          node-workspace                        [PASS | MISSING]

Overall: Fully compliant | X issues found
```

## Standard Templates

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
