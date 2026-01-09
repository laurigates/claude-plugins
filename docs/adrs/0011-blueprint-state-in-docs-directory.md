# ADR-0011: Blueprint State in docs/ Directory

**Date**: 2026-01-09
**Status**: Proposed
**Deciders**: Blueprint Plugin Maintainers

## Context

The blueprint-plugin currently stores project state in `.claude/blueprints/`:

```
.claude/
├── blueprints/
│   ├── .manifest.json
│   ├── work-orders/
│   ├── ai_docs/
│   ├── generated/
│   └── work-overview.md
├── rules/
├── skills/
└── commands/
```

This creates a significant usability problem: **Claude Code's permission system prompts for every file operation in `.claude/`**. Users cannot grant persistent write permissions to this directory, resulting in:

- Multiple permission prompts per session
- Interrupted workflows when updating manifest, creating work-orders, or modifying ai_docs
- Reduced velocity on routine operations
- User frustration with repetitive confirmations

The `docs/` directory, by contrast, is commonly whitelisted for persistent write permissions since documentation is expected to change frequently during development.

## Decision Drivers

- **Velocity**: Eliminate per-file permission prompts for routine blueprint operations
- **Separation of concerns**: Distinguish between Claude Code configuration (rules, skills, commands) and project state (manifest, work-orders, progress tracking)
- **Consistency**: PRDs, ADRs, and PRPs already live in `docs/` - blueprint state logically belongs there
- **Visibility**: Project state should be browsable and visible, not hidden in dotfiles
- **Migration complexity**: Must be achievable with existing migration infrastructure

## Considered Options

### Option 1: Keep Everything in `.claude/blueprints/` (Status Quo)

Maintain current structure where all blueprint artifacts live under `.claude/`.

**Pros**:
- No migration needed
- All Claude-related content in one location
- Consistent with initial design

**Cons**:
- Permission prompts on every operation
- Poor velocity for routine tasks
- Conflates configuration with project state

### Option 2: Move All Blueprint Content to `docs/blueprint/`

Move manifest, work-orders, ai_docs, generated content, and progress tracking to `docs/blueprint/`.

**Pros**:
- Persistent permissions possible
- Clear separation: `.claude/` for config, `docs/` for artifacts
- Visible and browsable content
- Consistent with PRD/ADR/PRP locations

**Cons**:
- Breaking change requiring migration
- Split between `.claude/` and `docs/` may confuse users initially
- Generated skills/commands source lives in `docs/` but active versions in `.claude/`

### Option 3: Hybrid - Only Move Frequently-Changed Files

Move only high-churn files (manifest, work-orders, work-overview) while keeping ai_docs and generated in `.claude/`.

**Pros**:
- Smaller migration surface
- Reduces most permission friction

**Cons**:
- Arbitrary split creates confusion
- ai_docs and generated also need frequent updates
- Doesn't solve the problem completely

### Option 4: Use `docs/.blueprint/` (Hidden in docs/)

Same as Option 2 but with dot-prefix to indicate tooling directory.

**Pros**:
- Hidden from casual browsing
- Signals "system" content

**Cons**:
- Hidden directories in `docs/` are unexpected
- Blueprint state is legitimate project content, not something to hide
- Some tools/editors hide dotfiles by default

## Decision Outcome

**Chosen option**: Option 2 - Move all blueprint content to `docs/blueprint/`

This provides the best balance of velocity improvement, conceptual clarity, and consistency with existing document structure.

### New Directory Structure

```
docs/
├── prds/                    # Product Requirements Documents
├── adrs/                    # Architecture Decision Records
├── prps/                    # Product Requirement Prompts
└── blueprint/               # Blueprint system state (NEW)
    ├── README.md            # Quick reference for developers
    ├── manifest.json        # Version tracking, project config
    ├── work-overview.md     # Progress tracking
    ├── feature-tracker.json # FR code tracking (optional)
    ├── work-orders/         # Task packages for subagents
    │   ├── completed/
    │   └── archived/
    └── ai_docs/             # Curated documentation
        ├── libraries/
        └── project/

.claude/                     # Claude Code configuration
├── rules/                   # Behavior rules (manual AND generated from PRDs)
│   ├── development.md       # Manual rules
│   ├── testing.md           # Manual rules
│   ├── architecture-patterns.md    # Generated from PRDs
│   ├── testing-strategies.md       # Generated from PRDs
│   └── ...
├── skills/                  # Custom skills
├── commands/                # Custom commands
└── settings.json            # Claude Code settings
```

### Key Insight: Generated Content is Rules, Not Skills

The `/blueprint:generate-skills` command extracts from PRDs:
- Architecture patterns
- Testing strategies
- Implementation guides
- Quality standards

These are **behavioral guidelines**, not capabilities. They belong in `.claude/rules/` alongside manual rules, not in a separate `generated/` directory.

The manifest tracks which rules were generated (vs manual) via content hashes:

```json
{
  "generated": {
    "rules": {
      "architecture-patterns": {
        "source": "docs/prds/project-overview.md",
        "source_hash": "sha256:...",
        "content_hash": "sha256:...",
        "plugin_version": "3.0.0",
        "generated_at": "2026-01-09T..."
      }
    }
  }
}
```

This allows detecting user modifications (hash mismatch) without needing directory-level separation.

### What Stays in `.claude/`

| Content | Reason |
|---------|--------|
| `rules/` | All behavior rules (manual and generated from PRDs) |
| `skills/` | Custom skills |
| `commands/` | Custom commands |
| `settings.json` | Claude Code application settings |

### What Moves to `docs/blueprint/`

| Content | Reason |
|---------|--------|
| `manifest.json` | Project state, frequently updated |
| `work-overview.md` | Progress tracking document |
| `feature-tracker.json` | Requirement tracking state |
| `work-orders/` | Task artifacts, created/completed often |
| `ai_docs/` | Curated documentation, evolves with project |

### Architecture Simplification

The previous three-layer architecture with "generated" as a separate layer was overcomplicated:

**Old (v2.x)**:
1. Plugin layer → Generic commands
2. Generated layer → `docs/blueprint/generated/` → copied to `.claude/`
3. Custom layer → `.claude/skills/`, `.claude/commands/`

**New (v3.0)**:
1. **Plugin layer** → Generic commands from blueprint-plugin
2. **Project layer** → Rules in `.claude/rules/` (both manual and PRD-generated)
3. **Custom layer** → Custom skills/commands in `.claude/skills/`, `.claude/commands/`

Generated rules are just rules. The manifest tracks provenance; the directory structure doesn't need to.

## Consequences

### Positive

- **Eliminated permission friction**: `docs/` can receive persistent write permissions
- **Improved velocity**: Manifest updates, work-order creation, and ai_docs modifications happen without prompts
- **Clearer mental model**: Configuration vs. state separation is explicit
- **Better visibility**: Blueprint state is browsable alongside other documentation
- **Consistent location**: All project documentation artifacts in `docs/`
- **Simpler architecture**: No "generated layer" indirection; rules are just rules

### Negative

- **Breaking change**: Requires v2.x → v3.0 migration
- **Split locations**: Users must understand `.claude/` vs `docs/blueprint/` distinction
- **Existing tutorials/docs outdated**: Documentation references `.claude/blueprints/`

### Mitigation for Negatives

| Concern | Mitigation |
|---------|------------|
| Breaking change | Use existing migration infrastructure; provide clear upgrade path |
| Split locations | Document the separation clearly; `docs/blueprint/README.md` explains purpose |
| Outdated docs | Update all command/skill documentation as part of release |

## Migration Path

This constitutes a **major version bump** (v2.x → v3.0).

Migration steps:
1. Create `docs/blueprint/` directory structure
2. Move state files: `.claude/blueprints/{manifest,work-overview,feature-tracker,work-orders,ai_docs}` → `docs/blueprint/`
3. Move generated content to rules: `.claude/blueprints/generated/skills/*` → `.claude/rules/`
4. Remove `.claude/blueprints/generated/` directory
5. Update manifest schema to v3.0.0 (change `generated.skills` to `generated.rules`)
6. Preserve `.claude/rules/`, `.claude/skills/`, `.claude/commands/`
7. Add `docs/blueprint/README.md` from template
8. Add migration entry to manifest's `upgrade_history`

The existing `blueprint-migration` skill handles version-specific migrations and will include a `v2.x-to-v3.0.md` migration document.

## Links

- [ADR-0005: Blueprint Development Methodology](0005-blueprint-development-methodology.md)
- [ADR-0010: Proactive Document Detection](0010-proactive-document-detection.md)
- Blueprint Plugin Documentation: `blueprint-plugin/README.md`
- Migration Skill: `blueprint-plugin/skills/blueprint-migration/`
