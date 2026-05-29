---
created: 2025-12-28
modified: 2026-05-29
reviewed: 2026-05-29
name: release-please-configuration
description: "release-please monorepo config — component tags, per-package extra-files, tag migration. Use when adding packages or fixing duplicate-tag / no-bump failures."
user-invocable: false
allowed-tools: Read, Write, Edit, Bash, Grep, Glob, TodoWrite
---

# Release-Please Monorepo Configuration

Monorepo-specific release-please strategy: component tagging, per-package
`extra-files`, linked versions, and the shared→component tag migration. For
the single-repo workflow/manifest/config shape, the conventional-commit
version-bump rules, and compliance auditing, use
`configure-plugin:release-please-standards`.

## When to Use This Skill

| Use this skill when... | Use the alternative when... |
|---|---|
| Configuring `component`/`include-component-in-tag` for a multi-package repo | Setting up a **single-repo** release-please (workflow, manifest, config shape) — use `configure-plugin:release-please-standards` |
| Adding a new package to a monorepo's release-please config | Auditing an existing setup against documented conventions — use `configure-plugin:release-please-standards` |
| Fixing duplicate-tag, multiple-paths, or per-package no-bump failures | Actually merging release-please PRs — use `release-please-pr-workflow` |
| Migrating from shared `v1.0.0` tags to `component-v1.0.0` tags | Detecting manual edits to managed files — use `release-please-protection` |
| Setting per-package `extra-files` (JSON/YAML/TOML/XML version locations) | `Release-As:` trailer-based one-off overrides — use `git-commit-trailers` |

## Core Files

| File | Purpose |
|------|---------|
| `release-please-config.json` | Per-package config, changelog sections, extra-files |
| `.release-please-manifest.json` | Current version for each package/component |
| `.github/workflows/release-please.yml` | GitHub Actions workflow (see `release-please-standards` for the shape) |

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

### Linked Versions

To keep a set of components on the same version, use the `linked-versions`
plugin:

```json
{
  "packages": {
    "packages/frontend": {"release-type": "node", "component": "frontend"},
    "packages/backend": {"release-type": "node", "component": "backend"}
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

## Per-Package `extra-files` for Custom Version Locations

For JSON files, you **must** use the object format with `type`, `path`, and `jsonpath`:

```json
{
  "packages": {
    "my-plugin": {
      "release-type": "simple",
      "extra-files": [
        {"type": "json", "path": ".claude-plugin/plugin.json", "jsonpath": "$.version"}
      ]
    }
  }
}
```

**Key insight:** For monorepo packages, `extra-files` paths are relative to the
package directory, NOT the repo root. Release-please automatically prepends the
package path.

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

2. Prepending the package path yourself (it gets doubled):
```json
// WRONG - path becomes my-plugin/my-plugin/.claude-plugin/...
"extra-files": [
  {"type": "json", "path": "my-plugin/.claude-plugin/plugin.json", "jsonpath": "$.version"}
]

// CORRECT - path is relative to the package directory
"extra-files": [
  {"type": "json", "path": ".claude-plugin/plugin.json", "jsonpath": "$.version"}
]
```

**File Type Formats:**

| File Type | Format |
|-----------|--------|
| JSON | `{"type": "json", "path": "...", "jsonpath": "$.version"}` |
| YAML | `{"type": "yaml", "path": "...", "jsonpath": "$.version"}` |
| TOML | `{"type": "toml", "path": "...", "jsonpath": "$.version"}` |
| XML | `{"type": "xml", "path": "...", "xpath": "//version"}` |
| Plain text | `"path/to/version.txt"` (string is fine) |

## Adding a New Package to a Monorepo

1. **Update `release-please-config.json`:**
```json
{
  "packages": {
    "new-package": {
      "component": "new-package",
      "release-type": "simple",
      "extra-files": [
        {"type": "json", "path": ".claude-plugin/plugin.json", "jsonpath": "$.version"}
      ],
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

3. **Create the initial version file** in the package if needed.

For the standard `changelog-sections` set and release-type table, see
`configure-plugin:release-please-standards`.

## Migrating from Shared Tags to Component Tags

When transitioning from `v1.0.0` style tags to `component-v1.0.0`:

1. Add `"include-component-in-tag": true` to config
2. Add `"component": "package-name"` to each package
3. Old tags (`v1.0.0`) will be ignored
4. New releases will create component-specific tags
5. Close any pending combined release PRs

**Note:** Release-please scans for component-specific tags. The first run after
migration creates release PRs for all packages with changes since the manifest
version.

## Monorepo Troubleshooting

### One Package's PR Not Created (others fine)

Check:
1. Are there releasable commits scoped to that package path since its last
   component tag?
2. Does the commit scope match the package path?
3. Is the package's `component` set and unique?

### Wrong Version in a Package's Extra File

Ensure the package's `extra-files` paths are relative to the **package
directory**, not the repo root (release-please prepends the package path):
```json
// Correct (package path is "my-package")
"extra-files": [{"type": "json", "path": ".claude-plugin/plugin.json", "jsonpath": "$.version"}]
```

For single-repo troubleshooting (no PR created at all, version not bumping,
CI not running on the release PR), see `configure-plugin:release-please-standards`.

## Quick Reference

```bash
# Check latest release-please-action version
curl -s https://api.github.com/repos/googleapis/release-please-action/releases/latest | jq -r '.tag_name'

# List pending release PRs (per-component in a monorepo)
gh pr list --label "autorelease: pending"

# View recent workflow runs
gh run list --workflow=release-please.yml --limit=5

# Inspect a package's current version in the manifest
jq -r '."my-package"' .release-please-manifest.json
```

## Resources

- [Manifest Releaser Guide](https://github.com/googleapis/release-please/blob/main/docs/manifest-releaser.md) — the canonical monorepo reference
- [Release-Please Documentation](https://github.com/googleapis/release-please)
- [Release-Please Action](https://github.com/googleapis/release-please-action)
- `configure-plugin:release-please-standards` — single-repo standards, version-bump rules, compliance auditing
