# ADR-0008: Semantic Versioning with Manifest

## Status

Accepted

## Date

2024-12 (retroactively documented 2025-12)

## Context

As plugins evolved, we needed answers to:

1. **What version is installed?** Users need to know if they're current
2. **What changed?** Breaking changes must be communicated
3. **Can I upgrade?** Compatibility between versions must be clear
4. **What artifacts exist?** Generated commands/skills need tracking
5. **When was this created?** Audit trail for configurations

Without versioning:
- Users couldn't tell if updates were available
- Breaking changes surprised users
- No upgrade path documentation
- Generated artifacts weren't tracked

## Decision

Implement **semantic versioning** with **manifest tracking** at two levels:

### Plugin-Level Versioning (plugin.json)

Each plugin declares its version:

```json
{
  "name": "blueprint-plugin",
  "version": "1.1.0",
  "description": "Blueprint Development methodology"
}
```

### Project-Level Manifest (.manifest.json)

Projects using blueprint methodology track their state:

```json
{
  "version": "1.1.0",
  "created_at": "2024-12-15T10:30:00Z",
  "updated_at": "2024-12-17T14:22:00Z",
  "project": {
    "type": "team",
    "rules_mode": "modular"
  },
  "artifacts": {
    "commands": ["project/continue.md", "project/test-loop.md"],
    "skills": [],
    "rules": ["development.md", "testing.md"]
  }
}
```

### Versioning Scheme

Following [Semantic Versioning 2.0.0](https://semver.org/):

```
MAJOR.MINOR.PATCH

MAJOR: Breaking changes (command renames, removed features)
MINOR: New features, backward compatible
PATCH: Bug fixes, documentation updates
```

### Version Tracking Commands

| Command | Purpose |
|---------|---------|
| `/blueprint-status` | Display version, configuration, upgrade availability |
| `/blueprint-upgrade` | Upgrade manifest to latest format |

### Marketplace Sync

The `marketplace.json` reflects plugin versions:

```json
{
  "plugins": [
    {
      "name": "blueprint-plugin",
      "version": "1.1.0",
      ...
    }
  ]
}
```

## Consequences

### Advantages

- **Clear expectations**: Version numbers communicate stability
- **Upgrade paths**: Manifest version enables migration scripts
- **Audit trail**: Timestamps show configuration history
- **Artifact tracking**: Know what was generated and when
- **Breaking change awareness**: MAJOR bumps signal caution

### Disadvantages

- **Maintenance overhead**: Must update versions consistently
- **Sync requirements**: plugin.json ↔ marketplace.json must match
- **Upgrade complexity**: Migration scripts need writing
- **Version fatigue**: Many small updates may accumulate

### Version Update Process

1. Make changes to plugin
2. Update `plugin.json` version
3. Update `marketplace.json` version
4. Write migration notes if MAJOR change
5. Update `/blueprint-upgrade` if manifest format changes

### Breaking Changes (MAJOR)

Examples that require MAJOR version bump:
- Command renamed or removed
- Skill activation keywords changed
- Manifest format incompatible
- Required configuration added

### New Features (MINOR)

Examples that require MINOR version bump:
- New command added
- New skill added
- New optional configuration
- Enhanced functionality

## Alternatives Considered

### 1. No Versioning

Plugins are always "latest"; users accept whatever is current.

**Rejected**: No way to communicate breaking changes.

### 2. Date-Based Versioning

Use dates: `2024.12.15`.

**Rejected**: Doesn't convey breaking vs. minor changes.

### 3. Git-Based Versioning

Use commit hashes or tags.

**Rejected**: Not human-readable; hard to compare.

### 4. Per-Component Versioning

Version each command/skill independently.

**Rejected**: Too granular; coordination nightmare.

## Related Decisions

- ADR-0004: Marketplace Registry Model (version in marketplace.json)
- ADR-0005: Blueprint Development Methodology (manifest usage)
- Dotfiles ADR-0009: Conventional Commits + Release-Please (versioning automation)
