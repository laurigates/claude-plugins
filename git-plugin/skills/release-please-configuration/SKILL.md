---
created: 2025-12-28
modified: 2025-12-28
reviewed: 2025-12-28
name: release-please-configuration
description: |
  Configures release-please for monorepos and single-package repos. Handles
  manifest files, component tagging, changelog sections, and extra-files setup.
  Use when setting up automated releases, fixing release workflow issues, or
  configuring version bump automation.
allowed-tools: Read, Write, Edit, Bash, Grep, Glob, TodoWrite
---

# Release-Please Configuration

Expert knowledge for configuring Google's release-please for automated releases.

## Core Files

| File | Purpose |
|------|---------|
| `release-please-config.json` | Package configuration, changelog sections, extra-files |
| `.release-please-manifest.json` | Current versions for each package |
| `.github/workflows/release-please.yml` | GitHub Actions workflow |

## Monorepo Configuration

### Critical Settings for Monorepos

```json
{
  "$schema": "https://raw.githubusercontent.com/googleapis/release-please/main/schemas/config.json",
  "include-component-in-tag": true,
  "separate-pull-requests": true,
  "packages": {
    "package-a": {
      "component": "package-a",
      "release-type": "simple",
      "extra-files": ["package-a/version.json"]
    }
  }
}
```

**Key Fields:**

| Field | Required | Purpose |
|-------|----------|---------|
| `include-component-in-tag` | Yes (monorepo) | Creates `package-a-v1.0.0` tags instead of `v1.0.0` |
| `component` | Yes (monorepo) | Unique identifier for each package; **must be set for every package** |
| `separate-pull-requests` | Recommended | Creates per-package release PRs instead of combined |

### Common Failure: Duplicate Release Tags

**Symptom:** Workflow fails with `Duplicate release tag: v2.0.0`

**Cause:** All packages try to create the same tag (e.g., `v2.0.0`) because:
1. Missing `include-component-in-tag: true` at root level
2. Missing `component` field in each package

**Fix:**
```json
{
  "include-component-in-tag": true,
  "packages": {
    "my-package": {
      "component": "my-package",  // Add this to every package
      ...
    }
  }
}
```

### Common Failure: Multiple Paths Warning

**Symptom:** `Multiple paths for : package-a, package-b`

**Cause:** Empty `component` field (the `:` with nothing after it indicates empty string)

**Fix:** Ensure every package has `"component": "package-name"` set

## Release Types

| Type | Use Case | Version File |
|------|----------|--------------|
| `simple` | Generic projects | `version.txt` |
| `node` | npm packages | `package.json` |
| `python` | Python (pyproject.toml) | `pyproject.toml` |
| `rust` | Rust crates | `Cargo.toml` |
| `go` | Go modules | `version.go` or similar |

### Extra Files for Custom Version Locations

For JSON files, you **must** use the object format with `type`, `path`, and `jsonpath`:

```json
{
  "packages": {
    "my-plugin": {
      "release-type": "simple",
      "extra-files": [
        {"type": "json", "path": "my-plugin/.claude-plugin/plugin.json", "jsonpath": "$.version"}
      ]
    }
  }
}
```

**Common Mistakes:**

1. Using a simple string path for JSON files:
```json
// WRONG - won't update the version field
"extra-files": [".claude-plugin/plugin.json"]

// CORRECT - uses JSON updater with jsonpath
"extra-files": [
  {"type": "json", "path": ".claude-plugin/plugin.json", "jsonpath": "$.version"}
]
```

2. Using absolute paths instead of package-relative paths:
```json
// WRONG - path gets doubled (package-name/package-name/.claude-plugin/...)
"extra-files": [
  {"type": "json", "path": "my-plugin/.claude-plugin/plugin.json", "jsonpath": "$.version"}
]

// CORRECT - path is relative to the package directory
"extra-files": [
  {"type": "json", "path": ".claude-plugin/plugin.json", "jsonpath": "$.version"}
]
```

**Key insight:** For monorepo packages, `extra-files` paths are relative to the package directory, NOT the repo root. Release-please automatically prepends the package path.

**File Type Formats:**

| File Type | Format |
|-----------|--------|
| JSON | `{"type": "json", "path": "...", "jsonpath": "$.version"}` |
| YAML | `{"type": "yaml", "path": "...", "jsonpath": "$.version"}` |
| TOML | `{"type": "toml", "path": "...", "jsonpath": "$.version"}` |
| XML | `{"type": "xml", "path": "...", "xpath": "//version"}` |
| Plain text | `"path/to/version.txt"` (string is fine) |

## Changelog Configuration

### Standard Changelog Sections

```json
{
  "changelog-sections": [
    {"type": "feat", "section": "Features"},
    {"type": "fix", "section": "Bug Fixes"},
    {"type": "perf", "section": "Performance"},
    {"type": "refactor", "section": "Code Refactoring"},
    {"type": "docs", "section": "Documentation"}
  ]
}
```

### Commit Type to Version Bump

| Commit Type | Version Bump | CHANGELOG Section |
|-------------|--------------|-------------------|
| `feat:` | Minor | Features |
| `fix:` | Patch | Bug Fixes |
| `feat!:` | Major | Features (with BREAKING CHANGE) |
| `BREAKING CHANGE:` | Major | Breaking Changes |
| `chore:` | None | (hidden) |
| `docs:` | None | Documentation |
| `refactor:` | None | Code Refactoring |
| `perf:` | Patch | Performance |

## Manifest File

The `.release-please-manifest.json` tracks current versions:

```json
{
  "package-a": "1.2.3",
  "package-b": "2.0.0"
}
```

**Important:** This file is auto-updated by release-please. Manual edits should only be done for:
- Initial bootstrapping
- Resetting after tag migration

## GitHub Actions Workflow

### Minimal Workflow

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
          token: ${{ secrets.GITHUB_TOKEN }}
```

### With Custom Token (Required for Triggering Other Workflows)

```yaml
- uses: googleapis/release-please-action@v4
  with:
    token: ${{ secrets.MY_RELEASE_PLEASE_TOKEN }}
```

Use a PAT if you need release PRs to trigger other workflows (e.g., CI checks).

## Adding a New Package to Monorepo

1. **Update `release-please-config.json`:**
```json
{
  "packages": {
    "new-package": {
      "component": "new-package",
      "release-type": "simple",
      "extra-files": ["new-package/.version-file.json"],
      "changelog-sections": [...]
    }
  }
}
```

2. **Update `.release-please-manifest.json`:**
```json
{
  "new-package": "1.0.0"
}
```

3. **Create initial version file** in the package if needed.

## Migrating from Shared Tags to Component Tags

When transitioning from `v1.0.0` style tags to `component-v1.0.0`:

1. Add `"include-component-in-tag": true` to config
2. Add `"component": "package-name"` to each package
3. Old tags (`v1.0.0`) will be ignored
4. New releases will create component-specific tags
5. Close any pending combined release PRs

**Note:** Release-please will scan for component-specific tags. First run after migration will create release PRs for all packages with changes since the manifest version.

## Troubleshooting

### Workflow Succeeds but No PR Created

Check:
1. Are there releasable commits since last release tag?
2. Do commits follow conventional format?
3. Is the package path correct in config?

### Version Not Bumping

Check:
1. Commit type (feat/fix vs chore/docs)
2. Commit scope matches package path
3. Conventional commit format is correct

### Wrong Version in Extra Files

Ensure `extra-files` paths are correct relative to repo root, not package root:
```json
// Correct
"extra-files": ["my-package/.claude-plugin/plugin.json"]

// Wrong (if package path is "my-package")
"extra-files": [".claude-plugin/plugin.json"]
```

## Quick Reference

### Conventional Commit Format

```
<type>(<scope>): <description>

[optional body]

[optional footer(s)]
```

**Examples:**
```bash
feat(auth): add OAuth2 support
fix(api): handle timeout edge case
feat(cli)!: redesign command interface

BREAKING CHANGE: Commands now use subcommand syntax.
```

### Version Bump Rules

| Pattern | Bump |
|---------|------|
| `feat:` | Minor (1.0.0 → 1.1.0) |
| `fix:` | Patch (1.0.0 → 1.0.1) |
| `!` suffix or `BREAKING CHANGE:` | Major (1.0.0 → 2.0.0) |
| `chore:`, `docs:`, `style:`, `test:` | No bump |

### Useful Commands

```bash
# Check latest release-please-action version
curl -s https://api.github.com/repos/googleapis/release-please-action/releases/latest | jq -r '.tag_name'

# List pending release PRs
gh pr list --label "autorelease: pending"

# View recent workflow runs
gh run list --workflow=release-please.yml --limit=5

# Check failed workflow logs
gh run view <run-id> --log-failed
```

## Resources

- [Release-Please Documentation](https://github.com/googleapis/release-please)
- [Release-Please Action](https://github.com/googleapis/release-please-action)
- [Conventional Commits](https://www.conventionalcommits.org/)
- [Manifest Releaser Guide](https://github.com/googleapis/release-please/blob/main/docs/manifest-releaser.md)
