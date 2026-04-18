---
name: blueprint-migration
description: Versioned migration procedures for upgrading blueprint structure between format versions
user-invocable: false
allowed-tools: Bash, Read, Write, Edit, Glob, Grep, AskUserQuestion, TodoWrite
created: 2025-12-22
modified: 2026-04-18
reviewed: 2026-04-18
---

# Blueprint Migration

Expert skill for migrating blueprint structures between format versions. This skill is triggered by `/blueprint:upgrade` and handles version-specific migration logic.

## Core Expertise

- Reading and parsing the blueprint manifest (`docs/blueprint/manifest.json` in v3.0+, or legacy `.claude/blueprints/.manifest.json` in v1.x/v2.x) for current version
- Determining appropriate migration path based on version comparison
- Executing versioned migration steps with user confirmation
- Content hashing for detecting manual modifications
- Safe file moves with rollback capability

## Canonical Manifest Filename

- **v3.0+**: `docs/blueprint/manifest.json` (canonical, no dot prefix — produced by `/blueprint:init`). Some repos carry a legacy `docs/blueprint/.manifest.json` from earlier v3.0 migrations; upgrade tooling tolerates both via the `$MANIFEST` variable resolved in `/blueprint:upgrade` Step 2.
- **v1.x/v2.x (historical)**: `.claude/blueprints/.manifest.json` — references to this path in v1/v2 migration documents are historical and must not be renamed.

## Migration Workflow

```
1. Read current manifest version
2. Compare with target version (latest: 3.3.0)
3. Load migration document for version range
4. Execute migration steps sequentially
5. Confirm each destructive operation
6. Update manifest to target version
7. Report migration summary
```

## Available Migrations

| From | To | Document |
|------|-----|----------|
| 1.0.x | 1.1.x | `migrations/v1.0-to-v1.1.md` |
| 1.x.x | 2.0.0 | `migrations/v1.x-to-v2.0.md` |
| 2.x.x | 3.0.0 | `migrations/v2.x-to-v3.0.md` |
| 3.0.x | 3.1.0 | `migrations/v3.0-to-v3.1.md` |
| 3.1.x | 3.2.0 | inline in `blueprint-upgrade` (step 3a) |
| 3.2.x | 3.3.0 | `migrations/v3.2-to-v3.3.md` |

## Version Detection

```bash
# Resolve manifest path — canonical first, then tolerated variants
if [[ -f docs/blueprint/manifest.json ]]; then
  MANIFEST=docs/blueprint/manifest.json
elif [[ -f docs/blueprint/.manifest.json ]]; then
  MANIFEST=docs/blueprint/.manifest.json
elif [[ -f .claude/blueprints/.manifest.json ]]; then
  MANIFEST=.claude/blueprints/.manifest.json
fi

jq -r '.format_version // "1.0.0"' "$MANIFEST"

# Detect v1.0 (no format_version field — legacy v1.x/v2.x location only)
if [[ -f .claude/blueprints/.manifest.json ]] && \
   ! jq -e '.format_version' .claude/blueprints/.manifest.json > /dev/null 2>&1; then
  echo "v1.0.0"
fi
```

## Content Hashing

For detecting modifications to generated content:

```bash
# Generate SHA256 hash of file content
sha256sum path/to/file | cut -d' ' -f1

# Compare with stored hash in manifest (use $MANIFEST from Version Detection above)
jq -r '.generated.skills["skill-name"].content_hash' "$MANIFEST"
```

## Migration Execution Pattern

When executing migrations:

1. **Announce step** - Explain what will happen
2. **Check prerequisites** - Verify source exists, target doesn't
3. **Confirm with user** - Use AskUserQuestion for destructive operations
4. **Execute** - Perform the migration step
5. **Verify** - Check operation succeeded
6. **Update manifest** - Track completion in manifest

## Error Handling

If migration fails:
- Stop immediately (fail-fast)
- Report which step failed and why
- Preserve original files (don't delete until confirmed)
- Provide manual recovery instructions

## Quick Reference

| Operation | Command |
|-----------|---------|
| Check version | `jq -r '.format_version' "$MANIFEST"` (resolve `$MANIFEST` first; see Version Detection) |
| Hash file | `sha256sum file \| cut -d' ' -f1` |
| Safe move | `cp -r source target && rm -rf source` |
| Check empty dir | `[ -z "$(ls -A dir)" ]` |
