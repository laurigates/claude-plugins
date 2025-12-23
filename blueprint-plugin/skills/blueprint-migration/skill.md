---
name: Blueprint Migration
description: Versioned migration procedures for upgrading blueprint structure between format versions
allowed-tools: Bash, Read, Write, Edit, Glob, Grep, AskUserQuestion, TodoWrite
created: 2025-12-22
modified: 2025-12-22
reviewed: 2025-12-22
---

# Blueprint Migration

Expert skill for migrating blueprint structures between format versions. This skill is triggered by `/blueprint:upgrade` and handles version-specific migration logic.

## Core Expertise

- Reading and parsing `.claude/blueprints/.manifest.json` for current version
- Determining appropriate migration path based on version comparison
- Executing versioned migration steps with user confirmation
- Content hashing for detecting manual modifications
- Safe file moves with rollback capability

## Migration Workflow

```
1. Read current manifest version
2. Compare with target version (latest: 2.0.0)
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

## Version Detection

```bash
# Read manifest version
cat .claude/blueprints/.manifest.json | jq -r '.format_version'

# Detect v1.0 (no format_version field)
if ! jq -e '.format_version' .claude/blueprints/.manifest.json > /dev/null 2>&1; then
  echo "v1.0.0"
fi
```

## Content Hashing

For detecting modifications to generated content:

```bash
# Generate SHA256 hash of file content
sha256sum path/to/file | cut -d' ' -f1

# Compare with stored hash in manifest
jq -r '.generated.skills["skill-name"].content_hash' .claude/blueprints/.manifest.json
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
| Check version | `jq -r '.format_version' .claude/blueprints/.manifest.json` |
| Hash file | `sha256sum file \| cut -d' ' -f1` |
| Safe move | `cp -r source target && rm -rf source` |
| Check empty dir | `[ -z "$(ls -A dir)" ]` |
