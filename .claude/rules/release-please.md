---
created: 2025-12-23
modified: 2026-11-06
reviewed: 2026-11-06
paths:
  - "release-please-config.json"
  - ".release-please-manifest.json"
  - "**/CHANGELOG.md"
---

# Release-Please Configuration

This monorepo uses [release-please](https://github.com/googleapis/release-please) for automated versioning and changelog generation. The facts below are read from the live files; `scripts/check-release-please-rule.sh` fails when this rule and those files disagree.

## Structure

| File | Purpose |
|------|---------|
| `.github/workflows/release-please.yml` | Runs release-please on every push to `main`, then syncs config files into the release PR and enables auto-merge |
| `release-please-config.json` | One package per plugin directory |
| `.release-please-manifest.json` | Current version of every package |

## How It Works

1. **Bump size comes from the commit type**: `feat` → minor, `fix`/`perf` → patch, `!` or a `BREAKING CHANGE:` footer → major.
2. **Which packages bump comes from the files a commit touches**, not from its scope. A commit is routed to every package whose directory it changes; the scope is only the changelog label. `.claude/rules/conventional-commits.md` § "Scope is a label; the files touched decide what releases" owns this, with examples.
3. **One combined release PR** covers every package with pending changes (`separate-pull-requests: false`). Tags carry the component (`include-component-in-tag: true`), e.g. `git-plugin-v2.69.5`.
4. **Version updates** sync to the plugin's `plugin.json` and to its entry in `.claude-plugin/marketplace.json` via `extra-files`. A leading `/` makes the marketplace path repo-root-relative.

## Authentication

The workflow mints a GitHub App token with `actions/create-github-app-token`, from the `RELEASE_PLEASE_APP_ID` repository variable and the `RELEASE_PLEASE_PRIVATE_KEY` secret, and passes it to `release-please-action`, the label step, the config-sync push and auto-merge. A `GITHUB_TOKEN` would not do: PRs and pushes it makes start no workflows, so the release PR would get no CI.

## Managed Files

These files are written by release-please:

| File | Source |
|------|--------|
| `**/CHANGELOG.md` | Generated from conventional commits |
| Version field in `plugin.json` | `extra-files`, `$.version` |
| Plugin's `version` in `.claude-plugin/marketplace.json` | `extra-files`, `$.plugins[?(@.name=='<plugin>')].version` |

Use conventional commits to change versions and changelogs. `python3 scripts/sync-plugin-configs.py --fix` writes both extra-files for a new plugin, and its check mode (the `Plugin: Validate configs` workflow) reports a package that lacks either.

## Adding a New Plugin

Add a package to **release-please-config.json** in the same shape as the existing ones:

```json
{
  "packages": {
    "new-plugin": {
      "component": "new-plugin",
      "release-type": "simple",
      "extra-files": [
        {"type": "json", "path": ".claude-plugin/plugin.json", "jsonpath": "$.version"},
        {"type": "json", "path": "/.claude-plugin/marketplace.json", "jsonpath": "$.plugins[?(@.name=='new-plugin')].version"}
      ],
      "changelog-sections": [
        {"type": "feat", "section": "Features"},
        {"type": "fix", "section": "Bug Fixes"},
        {"type": "perf", "section": "Performance"},
        {"type": "refactor", "section": "Code Refactoring"},
        {"type": "docs", "section": "Documentation"}
      ]
    }
  }
}
```

and its starting version to **.release-please-manifest.json**:

```json
{
  "new-plugin": "1.0.0"
}
```

## Version Checking

Fetch the latest release-please-action version:

```bash
curl -s https://api.github.com/repos/googleapis/release-please-action/releases/latest | jq -r '.tag_name'
```
