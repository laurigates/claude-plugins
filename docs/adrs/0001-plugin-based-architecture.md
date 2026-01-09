# ADR-0001: Plugin-Based Architecture

## Status

Accepted

## Date

2024-12 (retroactively documented 2025-12)

## Context

Claude Code configurations (commands, skills, agents) were originally maintained within the [laurigates/dotfiles](https://github.com/laurigates/dotfiles) repository, managed by Chezmoi. As the collection grew to 103+ skills, 76 commands, and 22 agents, several problems emerged:

1. **Monolithic coupling**: All configurations lived in a single `exact_dot_claude/` directory, making it difficult to share subsets of functionality
2. **Personal-only distribution**: Dotfiles repositories are inherently personal; sharing required copying entire directory structures
3. **No selective installation**: Users couldn't choose which capabilities they wanted without manual file management
4. **Discovery challenges**: Finding relevant commands/skills within a massive configuration was increasingly difficult
5. **Version coupling**: All configurations shared a single version, making independent updates impossible

The Claude Code plugin specification introduced a modular approach where capabilities could be packaged as installable plugins with defined boundaries.

## Decision

Create a standalone repository (`claude-plugins`) organized as a **plugin marketplace** where:

1. Each plugin is a self-contained directory with its own manifest, commands, skills, and agents
2. Plugins are domain-scoped (language, infrastructure, methodology, etc.)
3. A central `marketplace.json` provides discovery and installation metadata
4. Plugins can be installed independently via `/plugin install`
5. Configurations migrate from dotfiles to logical plugin groupings

### Directory Structure

```
claude-plugins/
├── marketplace.json              # Central registry
├── blueprint-plugin/             # Methodology plugin
│   ├── .claude-plugin/
│   │   └── plugin.json          # Plugin manifest
│   ├── commands/
│   ├── skills/
│   └── agents/
├── python-plugin/                # Language plugin
├── configure-plugin/             # Infrastructure plugin
└── ...
```

## Consequences

### Advantages

- **Selective installation**: Users install only plugins relevant to their work
- **Independent versioning**: Each plugin can evolve at its own pace
- **Shareable**: The repository can be public; anyone can install plugins
- **Discoverable**: Marketplace metadata enables browsing by category, keyword, or purpose
- **Maintainable**: Domain experts can own specific plugins
- **Composable**: Plugins can recommend companion plugins without hard dependencies

### Disadvantages

- **Migration overhead**: Existing configurations required reorganization and testing
- **Potential duplication**: Some skills may logically belong to multiple domains
- **Learning curve**: Users must understand plugin installation vs. global configuration
- **Coordination**: Cross-plugin changes require more careful coordination

### Migration Strategy

1. Prioritize high-value, self-contained plugins (blueprint, configure, git, testing)
2. Track migration status in `MIGRATION.md`
3. Document companion relationships in plugin READMEs
4. Deprecate dotfiles versions once plugins are stable

## Alternatives Considered

### 1. Monorepo with Shared CLAUDE.md

Keep everything in dotfiles but with better organization via layered CLAUDE.md files.

**Rejected**: Doesn't solve sharing or selective installation.

### 2. Multiple Dotfiles Repositories

Split into multiple dotfiles repositories (e.g., `claude-python-dotfiles`).

**Rejected**: Chezmoi complexity; users would need multiple source directories.

### 3. Git Submodules

Use git submodules to include plugins in dotfiles.

**Rejected**: Submodule management is notoriously difficult; doesn't provide clean installation UX.

## Related Decisions

- ADR-0002: Domain-Driven Plugin Organization
- ADR-0003: Auto-Discovery Component Pattern
- ADR-0004: Marketplace Registry Model
- Dotfiles ADR-0007: Layered Knowledge Distribution (predecessor approach)
