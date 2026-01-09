# Architecture Decision Records

This directory contains Architecture Decision Records (ADRs) documenting significant technical and architectural choices for the claude-plugins repository.

## Purpose

ADRs capture important architectural decisions along with their context, rationale, and consequences. They help current and future maintainers understand why the repository is structured the way it is.

## Background

This repository was created by migrating Claude Code plugin configurations from [laurigates/dotfiles](https://github.com/laurigates/dotfiles) to a standalone, shareable repository. Many architectural decisions were inherited or evolved from that migration, while others were made specifically for the plugin ecosystem.

## ADR Index

| ID | Title | Status | Date |
|----|-------|--------|------|
| [0001](0001-plugin-based-architecture.md) | Plugin-Based Architecture | Accepted | 2024-12 |
| [0002](0002-domain-driven-plugin-organization.md) | Domain-Driven Plugin Organization | Accepted | 2024-12 |
| [0003](0003-auto-discovery-component-pattern.md) | Auto-Discovery Component Pattern | Accepted | 2024-12 |
| [0004](0004-marketplace-registry-model.md) | Marketplace Registry Model | Accepted | 2024-12 |
| [0005](0005-blueprint-development-methodology.md) | Blueprint Development Methodology | Accepted | 2024-12 |
| [0006](0006-fvh-standards-enforcement.md) | FVH Standards Enforcement | Accepted | 2024-12 |
| [0007](0007-namespace-based-command-organization.md) | Namespace-Based Command Organization | Accepted | 2024-12 |
| [0008](0008-semantic-versioning-with-manifest.md) | Semantic Versioning with Manifest | Accepted | 2024-12 |
| [0009](0009-task-focused-agent-consolidation.md) | Task-Focused Agent Consolidation | Accepted | 2024-12 |
| [0010](0010-proactive-document-detection.md) | Proactive Document Detection | Proposed | 2026-01 |
| [0011](0011-blueprint-state-in-docs-directory.md) | Blueprint State in docs/ Directory | Proposed | 2026-01 |

## Categories

### Core Architecture
- ADR-0001: Plugin-Based Architecture
- ADR-0002: Domain-Driven Plugin Organization
- ADR-0003: Auto-Discovery Component Pattern
- ADR-0004: Marketplace Registry Model

### Development Methodology
- ADR-0005: Blueprint Development Methodology
- ADR-0006: FVH Standards Enforcement

### Organization & Versioning
- ADR-0007: Namespace-Based Command Organization
- ADR-0008: Semantic Versioning with Manifest
- ADR-0009: Task-Focused Agent Consolidation

### Documentation & Automation
- ADR-0010: Proactive Document Detection
- ADR-0011: Blueprint State in docs/ Directory

## ADR Format

Each ADR follows the [Michael Nygard format](https://cognitect.com/blog/2011/11/15/documenting-architecture-decisions):

```markdown
# ADR-NNNN: Title

## Status
[Proposed | Accepted | Deprecated | Superseded by ADR-NNNN]

## Date
YYYY-MM

## Context
The issue motivating this decision and any relevant context.

## Decision
The change being proposed or made.

## Consequences
What becomes easier or harder as a result of this decision.
```

## Related ADRs

The [laurigates/dotfiles](https://github.com/laurigates/dotfiles) repository contains additional ADRs that provide context for many decisions inherited by this repository:

- ADR-0003: Skill Activation via Trigger Keywords
- ADR-0004: Subagent-First Delegation Strategy
- ADR-0005: Namespace-Based Command Organization
- ADR-0006: Documentation-First Development
- ADR-0007: Layered Knowledge Distribution

## Adding New ADRs

1. Create a new file with the next sequential number: `NNNN-kebab-case-title.md`
2. Follow the ADR format template above
3. Update the index table in this README
4. Consider cross-references to related decisions
