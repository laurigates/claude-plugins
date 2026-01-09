# ADR-0002: Domain-Driven Plugin Organization

## Status

Accepted

## Date

2024-12 (retroactively documented 2025-12)

## Context

With the decision to create a plugin-based architecture (ADR-0001), we needed a strategy for organizing 100+ skills, 76 commands, and 22 agents into coherent plugins. Several organizational approaches were considered:

1. **Functional grouping**: By what they do (search, edit, test, deploy)
2. **Workflow grouping**: By development phase (planning, coding, reviewing, deploying)
3. **Technology grouping**: By specific tool (ruff, pytest, helm, docker)
4. **Domain grouping**: By problem domain (language, infrastructure, methodology)

The challenge was balancing granularity (too many small plugins = fragmentation) against comprehensiveness (too few large plugins = back to monolith).

## Decision

Organize plugins by **problem domain**, creating cohesive units that represent a developer's mental model of their work:

### Domain Categories

| Category | Plugins | Purpose |
|----------|---------|---------|
| **Language Ecosystems** | python, typescript, rust, bevy | Language-specific development tools |
| **Development Methodology** | blueprint, project, agent-patterns | Structured development workflows |
| **Quality & Testing** | testing, code-quality | Test execution and code analysis |
| **Infrastructure** | configure, container, kubernetes, terraform, github-actions | DevOps and CI/CD |
| **System Integration** | git, api, sync, communication | External system interaction |
| **Utilities** | tools, documentation | Cross-cutting utilities |
| **Specialized** | graphiti, accessibility, dotfiles | Domain-specific expertise |

### Plugin Boundaries

Each plugin should:

1. **Own a coherent domain**: All Python development tools in `python-plugin`, not scattered
2. **Be independently useful**: A user can install just `git-plugin` and get value
3. **Have clear boundaries**: If unsure where something belongs, it probably needs its own plugin
4. **Reference companions**: Document which plugins work well together (e.g., `testing-plugin` + `python-plugin`)

### Example: Python Ecosystem

Rather than separate plugins for `ruff-plugin`, `pytest-plugin`, `uv-plugin`:

```
python-plugin/
├── skills/
│   ├── python-development/
│   ├── ruff-linting/
│   ├── ruff-formatting/
│   ├── pytest-advanced/
│   ├── uv-project-management/
│   └── basedpyright-type-checking/
└── agents/
    └── python-development.md
```

This mirrors how developers think: "I'm doing Python work" not "I'm doing ruff work then pytest work."

## Consequences

### Advantages

- **Mental model alignment**: Plugin names match how developers describe their work
- **Reduced fragmentation**: 23 plugins instead of 100+ micro-plugins
- **Discoverability**: Category-based browsing in marketplace
- **Cohesive updates**: Language ecosystem updates happen in one place
- **Companion clarity**: Easy to say "install python-plugin + testing-plugin"

### Disadvantages

- **Larger plugins**: Some plugins (python, configure) have many components
- **Cross-domain skills**: Some skills (e.g., `ast-grep`) could belong to multiple domains
- **Subjective boundaries**: "Does API testing belong in testing-plugin or api-plugin?"

### Cross-Domain Handling

For skills that span domains:

1. **Primary location**: Place in most natural domain
2. **Documentation**: Reference in related plugin READMEs
3. **Duplication if necessary**: Some skills may exist in multiple plugins with context-specific variations

## Alternatives Considered

### 1. Technology-Specific Plugins

One plugin per tool (ruff-plugin, pytest-plugin, helm-plugin).

**Rejected**: Too granular; users would need 10+ plugins for basic Python development.

### 2. Workflow-Based Plugins

Plugins for planning, coding, testing, deploying phases.

**Rejected**: Crosses too many technologies; a "testing" plugin would include Python, TypeScript, Rust test tools.

### 3. Single Language Plugin

One `languages-plugin` containing all language ecosystems.

**Rejected**: Too monolithic; Python and Rust developers have very different needs.

## Related Decisions

- ADR-0001: Plugin-Based Architecture
- ADR-0003: Auto-Discovery Component Pattern
- Dotfiles ADR-0004: Subagent-First Delegation Strategy (influences agent organization)
