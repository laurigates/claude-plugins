# Quick Reference

Moved verbatim from `SKILL.md`. Inspection commands for a release-please monorepo.

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
