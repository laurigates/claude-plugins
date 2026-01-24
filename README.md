# Claude Plugins

A collection of Claude Code plugins providing specialized skills, commands, and agents for various development workflows.

## Plugins

| Plugin | Category | Description |
|--------|----------|-------------|
| **accessibility-plugin** | UX | WCAG compliance, ARIA patterns, design tokens |
| **agent-patterns-plugin** | AI | Multi-agent coordination and orchestration |
| **api-plugin** | Development | REST API integration and testing |
| **bevy-plugin** | Gamedev | Bevy game engine development with ECS |
| **blueprint-plugin** | Development | PRD/PRP workflow for structured feature development |
| **code-quality-plugin** | Quality | Code review, refactoring, linting, static analysis |
| **communication-plugin** | Communication | Google Chat formatting, ticket drafting |
| **configure-plugin** | Infrastructure | Pre-commit, CI/CD, Docker, testing configuration |
| **container-plugin** | Infrastructure | Docker, registry, Skaffold workflows |
| **documentation-plugin** | Documentation | API docs, README generation, knowledge graphs |
| **git-plugin** | Version Control | Commits, branches, PRs, repository management |
| **github-actions-plugin** | CI/CD | GitHub Actions workflows and automation |
| **kubernetes-plugin** | Infrastructure | Kubernetes and Helm operations |
| **project-plugin** | Development | Project initialization and management |
| **python-plugin** | Language | uv, ruff, pytest, Python packaging |
| **rust-plugin** | Language | Cargo, clippy, Rust development |
| **sync-plugin** | Integration | GitHub and Podio synchronization |
| **terraform-plugin** | Infrastructure | Terraform and infrastructure as code |
| **testing-plugin** | Testing | Test execution, TDD workflow, coverage |
| **tools-plugin** | Utilities | fd, rg, jq, shell utilities |
| **typescript-plugin** | Language | TypeScript, ESLint, Biome |

## Installation

Install plugins from this collection:

```bash
claude plugin install laurigates-plugins/<plugin-name>
```

For example:
```bash
claude plugin install laurigates-plugins/git-plugin
claude plugin install laurigates-plugins/python-plugin
```

## Structure

Each plugin follows the standard Claude Code plugin structure:

```
<plugin-name>/
├── README.md           # Plugin documentation
├── skills/             # Skill definitions (.md files)
├── commands/           # Slash commands (.md files)
└── agents/             # Agent definitions (.md files)
```

## License

MIT
