# ADR-0007: Namespace-Based Command Organization

## Status

Accepted

## Date

2024-12 (retroactively documented 2025-12)

## Context

As the command collection grew to 76+ commands across all plugins, usability problems emerged:

1. **Naming conflicts**: Multiple domains wanted `/status`, `/run`, `/check`
2. **Poor discoverability**: Users couldn't find commands in flat lists
3. **Cognitive overload**: Tab completion showed dozens of options
4. **No grouping**: Related commands weren't visually associated
5. **Ambiguity**: `/test` could mean test execution, test setup, or test review

The dotfiles repository addressed this (see Dotfiles ADR-0005), and the pattern was adopted for plugins.

## Decision

Organize commands into **namespaces** using colon-separated syntax:

### Namespace Convention

```
/namespace:command
```

### Directory Structure

```
commands/
├── simple-command.md        # → /simple-command (no namespace)
└── configure/               # Namespace via subdirectory
    ├── pre-commit.md        # → /configure:pre-commit
    ├── tests.md             # → /configure:tests
    └── workflows.md         # → /configure:workflows
```

### Plugin Namespaces

| Namespace | Plugin | Commands |
|-----------|--------|----------|
| `/git:*` | git-plugin | commit, issue, issues, fix-pr, maintain |
| `/configure:*` | configure-plugin | pre-commit, tests, workflows, dockerfile, ... |
| `/test:*` | testing-plugin | run, quick, full, setup, consult, report |
| `/code:*` | code-quality-plugin | review, refactor, antipatterns |
| `/project:*` | project-plugin | init, new, modernize, continue |
| `/blueprint:*` | blueprint-plugin | init, status, upgrade, rules |

### Root-Level Commands

Some commands remain at root level for discoverability:

- `/blueprint-init` - High-frequency entry point
- `/prp-create` - Direct access to PRP creation
- `/handoffs` - Cross-cutting utility

## Consequences

### Advantages

- **Scoped naming**: Each namespace owns its commands; no conflicts
- **Logical grouping**: Related commands are visually associated
- **Tab completion**: Type `/configure:` then tab for subcommands
- **Scalability**: Supports 200+ commands without chaos
- **Self-documenting**: Namespace hints at command purpose

### Disadvantages

- **Longer invocation**: `/configure:pre-commit` vs `/pre-commit`
- **Learning curve**: Users must learn namespace prefixes
- **Migration**: Existing references to flat commands break
- **Inconsistency**: Some commands at root, some namespaced

### Namespace Selection Guidelines

| Pattern | Use When |
|---------|----------|
| Namespace | Plugin has 3+ related commands |
| Root level | Command is high-frequency entry point |
| Root level | Command is unique, unlikely to conflict |

### Migration Pattern

When consolidating commands:

```
# Before (flat)
/project-continue
/project-test-loop

# After (namespaced)
/project:continue
/project:test-loop
```

## Alternatives Considered

### 1. Plugin-Prefixed Commands

Use plugin name as prefix: `/git-plugin:commit`.

**Rejected**: Too verbose; "plugin" redundant in command context.

### 2. Flat with Unique Names

Keep flat structure; make all names unique: `/git-commit`, `/test-run`.

**Rejected**: Doesn't scale; names become very long.

### 3. Slash-Based Nesting

Use slashes: `/configure/pre-commit`.

**Rejected**: Conflicts with path conventions; less distinct.

### 4. Dot-Based Nesting

Use dots: `/configure.pre-commit`.

**Rejected**: Less readable; dots overloaded in programming.

## Related Decisions

- ADR-0003: Auto-Discovery Component Pattern (directory conventions)
- Dotfiles ADR-0005: Namespace-Based Command Organization (original decision)
