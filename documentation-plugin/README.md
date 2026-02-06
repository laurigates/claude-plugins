# Documentation Plugin

Documentation generation, synchronization, and knowledge management for Claude Code projects.

## Overview

Comprehensive documentation tooling for generating API references, maintaining README files, synchronizing docs with codebase, creating decommission plans, and building knowledge graphs from technical documentation.

## Skills

| Skill | Description |
|-------|-------------|
| `/docs:sync` | Synchronize documentation with actual skills, commands, and agents in codebase |
| `/docs:generate` | Update project documentation from code annotations |
| `/docs:decommission` | Generate comprehensive service decommission documentation |
| `/docs:knowledge-graph` | Build knowledge graph from Obsidian vault documentation |
| `claude-blog-sources` | Access Claude Blog for latest features, patterns, and best practices |

## Agents

| Agent | Description |
|-------|-------------|
| `documentation` | Generate documentation from code annotations and API references |
| `research-documentation` | Perform documentation lookup and technical research |

## Usage Examples

### Sync Documentation

Keep your documentation in sync with the actual codebase:

```bash
# Sync all documentation
/docs:sync

# Sync only skills documentation
/docs:sync --scope skills

# Preview changes without modifying
/docs:sync --dry-run
```

### Generate Project Documentation

Create comprehensive documentation from your code:

```bash
# Generate all documentation
/docs:generate

# Generate API reference only
/docs:generate --api

# Update README from code analysis
/docs:generate --readme

# Generate changelog from git history
/docs:generate --changelog
```

### Create Decommission Plan

Generate a decommission checklist for a service:

```bash
/docs:decommission my-service-name
```

Creates `DECOMMISSION-my-service-name.md` with comprehensive checklists for:
- Infrastructure resources
- Data management
- Access and security
- DNS and networking
- Integration dependencies
- Monitoring cleanup
- Documentation archival

### Build Knowledge Graph

Create a searchable knowledge graph from technical documentation:

```bash
/docs:knowledge-graph
```

Processes Obsidian vault documentation and builds a comprehensive knowledge graph for semantic search and pattern recognition.

## Workflow Integration

### Documentation-First Development

1. Create documentation before implementation
2. Use `/docs:generate` to extract API docs from code
3. Keep docs in sync with `/docs:sync` after changes
4. Research patterns with `claude-blog-sources` skill

### Service Lifecycle

1. **Deployment**: Create decommission plan with `/docs:decommission`
2. **Development**: Generate docs with `/docs:generate`
3. **Maintenance**: Sync docs with `/docs:sync`
4. **Decommissioning**: Follow the decommission checklist

### Research Workflow

Use the `research-documentation` agent for:
- Finding up-to-date library documentation
- Searching implementation guides
- Retrieving technical specifications
- Comparing technologies

## Companion Plugins

Works well with:
- **project-plugin** - For project initialization and structure
- **git-plugin** - For committing documentation changes
- **testing-plugin** - For documenting test strategies

## Installation

```bash
/plugin install documentation-plugin@laurigates-claude-plugins
```

## License

MIT
