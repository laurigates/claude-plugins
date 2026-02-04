# Blueprint

This directory contains [Blueprint Development](https://github.com/laurigates/claude-plugins/tree/main/blueprint-plugin) system state for this project.

## What is Blueprint?

Blueprint Development is a structured, documentation-first methodology for AI-assisted development. It provides:

- **PRDs** (`docs/prds/`) - Product Requirements Documents
- **ADRs** (`docs/adrs/`) - Architecture Decision Records
- **PRPs** (`docs/prps/`) - Product Requirement Prompts (implementation-ready task definitions)

## Directory Structure

```
docs/blueprint/
├── README.md            # This file
├── manifest.json        # Version tracking, project configuration
├── feature-tracker.json # FR code tracking and progress (optional)
├── work-orders/         # Task packages for subagent execution
│   ├── completed/
│   └── archived/
└── ai_docs/             # Curated documentation for AI context
    ├── libraries/       # External library docs
    └── project/         # Project-specific patterns
```

## Key Files

| File | Purpose |
|------|---------|
| `manifest.json` | Tracks blueprint version, enabled features, and generated content metadata |
| `feature-tracker.json` | Maps requirement codes (FR1, FR1.1) to implementation status, tracks current phase and tasks |

## Related Locations

| Location | Content |
|----------|---------|
| `docs/prds/` | Product Requirements Documents |
| `docs/adrs/` | Architecture Decision Records |
| `docs/prps/` | Product Requirement Prompts |
| `.claude/rules/` | Behavior rules (manual and generated from PRDs) |

## Commands

| Command | Purpose |
|---------|---------|
| `/blueprint:status` | Show version and configuration |
| `/blueprint:derive-prd` | Derive PRD from existing documentation |
| `/blueprint:derive-adr` | Derive ADRs from codebase analysis |
| `/blueprint:derive-plans` | Derive docs from git history |
| `/blueprint:derive-rules` | Derive rules from git commit decisions |
| `/blueprint:prp-create` | Create a Product Requirement Prompt |
| `/blueprint:prp-execute` | Execute a PRP with TDD workflow |
| `/blueprint:work-order` | Create a task package for subagent |
| `/blueprint:generate-rules` | Generate rules from PRDs |
| `/blueprint:sync` | Check for stale generated content |
| `/blueprint:upgrade` | Upgrade to latest blueprint version |

## Generated Rules

The `/blueprint:generate-rules` command extracts patterns from your PRDs and creates rules in `.claude/rules/`:

- `architecture-patterns.md` - Project architecture conventions
- `testing-strategies.md` - Test patterns and requirements
- `implementation-guides.md` - How to implement features
- `quality-standards.md` - Code quality expectations

These are behavioral guidelines that help Claude understand your project's conventions. The manifest tracks which rules were generated (vs. manually created) via content hashes.

## Two-Layer Architecture

1. **Plugin Layer** - Generic commands from blueprint-plugin (auto-updated)
2. **Project Layer** - Your rules, skills, and commands in `.claude/`

Project layer takes precedence, allowing you to override any plugin behavior.

## Learn More

- [Blueprint Plugin Documentation](https://github.com/laurigates/claude-plugins/tree/main/blueprint-plugin)
- [ADR-0005: Blueprint Development Methodology](../adrs/0005-blueprint-development-methodology.md)
- [ADR-0011: Blueprint State in docs/ Directory](../adrs/0011-blueprint-state-in-docs-directory.md)
