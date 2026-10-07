# Migrating from Shared Tags to Component Tags

Moved verbatim from `SKILL.md`. Read when moving a repo from `v1.0.0` tags to `component-v1.0.0` tags.

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
