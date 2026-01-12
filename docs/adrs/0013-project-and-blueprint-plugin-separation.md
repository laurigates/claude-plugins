# ADR-0013: Project and Blueprint Plugin Separation

**Date**: 2026-01-12
**Status**: Accepted
**Deciders**: Plugin Maintainers

## Context

The repository contains two plugins that serve complementary purposes:

| Plugin | Version | Purpose |
|--------|---------|---------|
| **project-plugin** | 1.2.1 | Project discovery, initialization, and practical development workflows |
| **blueprint-plugin** | 3.0.0 | Structured feature development methodology (PRD/PRP workflow, rule generation) |

These plugins are designed to work together in a natural sequence:
1. Project Plugin: Discover/initialize project, understand tooling
2. Blueprint Plugin: Establish structured methodology for feature development

The question arose: should these be combined into a single plugin for better discoverability and clearer workflow?

### Current State

**Project Plugin** (6 commands, 1 skill):
- `/project:init` - Base project initialization
- `/project:continue` - Resume development with state analysis
- `/project:test-loop` - TDD cycle
- `project-discovery` skill - 5-phase orientation process

**Blueprint Plugin** (17 commands, 5 skills):
- PRD/PRP/Work-Order workflow
- Behavioral rule generation from requirements
- Feature tracking with hierarchical FR codes
- GitHub integration for work-orders

## Decision Drivers

- **Discoverability**: Would a shared namespace help users find related commands?
- **Separation of concerns**: Do these represent distinct mental models?
- **Adoption flexibility**: Should users be able to adopt one without the other?
- **Maintenance burden**: Does combining simplify or complicate updates?
- **Cognitive load**: Is one larger plugin easier or harder to understand?

## Considered Options

### Option 1: Combine into Single Plugin

Merge project-plugin into blueprint-plugin (or create new unified plugin).

**Pros**:
- Single namespace (`/project:*`) for all project lifecycle commands
- Clear workflow progression visible in one place
- Single install, no coordination needed
- Skills can reference each other directly

**Cons**:
- Creates very large plugin (23+ commands, 6+ skills)
- Conflates two distinct mental models (discovery vs methodology)
- Forces methodology adoption on users who only want discovery
- Different maturity levels (v3.0 vs v1.2) suggest different update cadences
- Blueprint is opinionated; project-plugin is tool-agnostic

### Option 2: Keep Separate, Document Relationship (Selected)

Maintain separate plugins with clear documentation of how they complement each other.

**Pros**:
- Clear separation of concerns (discovery ≠ methodology)
- À la carte adoption (use what you need)
- Smaller, focused plugins are easier to understand
- Independent versioning and release cycles
- Users who want lightweight discovery aren't burdened with methodology

**Cons**:
- Two plugins to discover and install
- Relationship not immediately obvious
- No shared namespace for discoverability

### Option 3: Shared Namespace, Separate Plugins

Both plugins use `/project:*` namespace but remain separate installations.

**Pros**:
- Discoverability through unified namespace
- Flexibility of separate installs
- Commands feel cohesive

**Cons**:
- Potential namespace conflicts
- Confusing to have same namespace from different plugins
- Harder to know which plugin provides which command

### Option 4: Meta-Plugin Bundle

Create `project-suite-plugin` that bundles both as dependencies.

**Pros**:
- Single install for users who want both
- Original plugins remain independent
- Clear that they work together

**Cons**:
- Third artifact to maintain
- Adds complexity to plugin ecosystem
- Version coordination challenges

## Decision Outcome

**Chosen option**: Option 2 - Keep separate, document relationship

The fundamental difference in purpose justifies separation:

| Aspect | Project Plugin | Blueprint Plugin |
|--------|---------------|------------------|
| **Mental model** | Discovery & tooling | Methodology & workflow |
| **Approach** | Bottom-up (observe patterns) | Top-down (from requirements) |
| **Opinionation** | Minimal (finds what exists) | High (prescribes structure) |
| **Scope** | Any project, any workflow | Projects using Blueprint methodology |

Users who want quick project orientation shouldn't need to understand PRD/PRP workflows. Conversely, teams already using Blueprint may have their own initialization processes.

### Documentation Improvements

To address discoverability concerns, both plugins should:
1. Reference each other in README "Related Plugins" section
2. Include recommended workflow combining both
3. Link to this ADR for architectural context

## Consequences

### Positive

- **Clear mental models**: Each plugin has focused, understandable purpose
- **Flexible adoption**: Teams choose what fits their workflow
- **Independent evolution**: Plugins can version and release separately
- **Lighter installs**: Users get only what they need

### Negative

- **Discovery overhead**: Users must know both plugins exist
- **Workflow documentation**: Relationship requires explicit documentation
- **No namespace cohesion**: Commands use different prefixes (`/project:*` vs `/blueprint-*`)

### Neutral

- Existing users are not impacted (no breaking changes)
- Plugin structure follows established patterns in repository

## Future Considerations

This decision can be revisited if:
1. User feedback indicates strong preference for combined plugin
2. The plugins converge in purpose over time
3. A clear namespace strategy for multi-plugin workflows emerges
4. Plugin bundling/dependency features are added to Claude Code

The Option 3 (shared namespace) or Option 4 (meta-plugin) approaches remain viable future paths if discoverability becomes a significant user friction point.

## Links

- Related: [ADR-0002: Domain-Driven Plugin Organization](0002-domain-driven-plugin-organization.md)
- Related: [ADR-0005: Blueprint Development Methodology](0005-blueprint-development-methodology.md)
- Related: [ADR-0007: Namespace-Based Command Organization](0007-namespace-based-command-organization.md)
- Plugin: [project-plugin/README.md](../../project-plugin/README.md)
- Plugin: [blueprint-plugin/README.md](../../blueprint-plugin/README.md)
