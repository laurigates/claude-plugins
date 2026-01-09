# ADR-0005: Blueprint Development Methodology

## Status

Accepted

## Date

2024-12 (retroactively documented 2025-12)

## Context

As Claude Code became central to development workflows, a recurring problem emerged: complex features were implemented without sufficient upfront planning, leading to:

1. **Scope creep**: Features expanded beyond original intent
2. **Inconsistent quality**: No standard for "done"
3. **Poor documentation**: Implementation details lost
4. **Unclear requirements**: Ambiguous success criteria
5. **Difficult handoffs**: Context not preserved between sessions

The `context7` MCP server investigation revealed that even Claude needed structured guidance—official documentation often contradicted assumptions, and best practices evolved faster than implementations.

## Decision

Adopt a **Blueprint Development Methodology** as the core workflow for significant features:

### Three-Phase Workflow

```
PRD → PRP → Work Order
```

1. **PRD (Product Requirements Document)**: What we're building and why
2. **PRP (Product Refinement Proposal)**: How we'll build it, with technical details
3. **Work Order**: Executable tasks derived from PRP

### Blueprint Plugin Components

| Component | Type | Purpose |
|-----------|------|---------|
| `/blueprint-init` | Command | Initialize blueprint structure in project |
| `/blueprint-generate-commands` | Command | Create project-specific commands from PRD |
| `/blueprint-generate-skills` | Command | Create project-specific skills from PRP |
| `/blueprint-work-order` | Command | Generate work order from PRP |
| `/prp-create` | Command | Create new PRP from PRD |
| `/prp-execute` | Command | Execute PRP with progress tracking |
| `blueprint-development` | Skill | Methodology guidance and templates |
| `confidence-scoring` | Skill | Confidence assessment framework |
| `requirements-documentation` | Agent | PRD creation specialist |

### Document Flow

```
blueprints/
├── .manifest.json           # Version tracking, configuration
├── PRD-feature-name.md      # Requirements document
├── PRP-feature-name.md      # Technical proposal
├── WO-feature-name.md       # Work order (generated)
└── .claude/
    └── commands/
        └── project/         # Generated project-specific commands
```

### Manifest Tracking (v1.1.0)

The `.manifest.json` tracks:
- Blueprint format version
- Creation/update timestamps
- Project configuration (type, rules mode)
- Generated artifacts list
- Upgrade path detection

## Consequences

### Advantages

- **Structured planning**: Complex features get proper design phase
- **Clear success criteria**: PRD defines "done"
- **Preserved context**: Documents survive session boundaries
- **Reproducible**: Work orders can be re-executed
- **Version awareness**: Manifest enables format upgrades
- **Auto-generated artifacts**: Commands and skills created from blueprints

### Disadvantages

- **Overhead for small changes**: Simple bug fixes don't need PRDs
- **Learning curve**: Team must understand methodology
- **Template maintenance**: Blueprint templates evolve
- **Potential rigidity**: Some tasks resist structured planning

### When to Use Blueprints

| Use Blueprint | Skip Blueprint |
|---------------|----------------|
| New features | Bug fixes |
| Significant refactors | Documentation updates |
| Architecture changes | Config changes |
| Multi-session work | Single-file edits |
| Team collaboration | Solo exploration |

### Confidence Scoring

The methodology includes confidence assessment:

```
High (80-100%): Direct experience, verified patterns
Medium (50-79%): Reasonable inference, some uncertainty
Low (0-49%): Speculation, needs validation
```

## Alternatives Considered

### 1. Informal Planning

Use ad-hoc notes or conversation history for planning.

**Rejected**: Context lost between sessions; no standard format.

### 2. Issue-Only Workflow

Rely solely on GitHub issues for requirements.

**Rejected**: Issues lack technical depth; not designed for implementation planning.

### 3. External Tools

Use Notion, Confluence, or similar for documentation.

**Rejected**: Context switching; not integrated with Claude Code.

### 4. Inline Comments

Document plans in code comments.

**Rejected**: Scattered across files; not discoverable.

## Related Decisions

- ADR-0001: Plugin-Based Architecture (blueprint-plugin structure)
- ADR-0006: FVH Standards Enforcement (standards integration)
- Dotfiles ADR-0006: Documentation-First Development (predecessor methodology)
