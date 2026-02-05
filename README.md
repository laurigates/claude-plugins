# Claude Plugins

A collection of Claude Code plugins providing specialized skills, commands, and agents for various development workflows.

## Plugins

| Plugin | Category | Description |
|--------|----------|-------------|
| **accessibility-plugin** | ux | Accessibility and UX implementation - WCAG, ARIA, design tokens |
| **agent-patterns-plugin** | ai | Multi-agent coordination and orchestration patterns |
| **agents-plugin** | ai | Task-focused agents for test, review, debug, docs, and CI workflows |
| **api-plugin** | development | API integration and testing - REST endpoints, client generation |
| **bevy-plugin** | gamedev | Bevy game engine development - ECS, rendering, game architecture |
| **blog-plugin** | documentation | Blog post creation - project logs, technical write-ups, personal documentation |
| **blueprint-plugin** | development | Blueprint Development methodology - PRD/PRP workflow with version tracking |
| **code-quality-plugin** | quality | Code review, refactoring, linting, and static analysis |
| **command-analytics-plugin** | utilities | Track command and skill usage analytics across all projects |
| **communication-plugin** | communication | External communication formatting - Google Chat, ticket drafting |
| **configure-plugin** | infrastructure | Project infrastructure standards - pre-commit, CI/CD, Docker, testing |
| **container-plugin** | infrastructure | Container development and deployment - Docker, registry, Skaffold |
| **documentation-plugin** | documentation | Documentation generation - API docs, README, knowledge graphs |
| **git-plugin** | version-control | Git workflows - commits, branches, PRs, and repository management |
| **github-actions-plugin** | ci-cd | GitHub Actions CI/CD - workflows, authentication, inspection |
| **hooks-plugin** | automation | Claude Code hooks for enforcing best practices and workflow automation |
| **kubernetes-plugin** | infrastructure | Kubernetes and Helm operations - deployments, charts, releases |
| **langchain-plugin** | ai | LangChain JS/TS development - agents, chains, LangGraph, Deep Agents |
| **networking-plugin** | infrastructure | Network diagnostics, reconnaissance, monitoring, and HTTP load testing |
| **project-plugin** | development | Project initialization, management, and maintenance |
| **python-plugin** | language | Python development ecosystem - uv, ruff, pytest, packaging |
| **rust-plugin** | language | Rust development - cargo, clippy, testing, memory safety |
| **sync-plugin** | integration | External system synchronization - GitHub, Podio integration |
| **terraform-plugin** | infrastructure | Terraform and Terraform Cloud - infrastructure as code |
| **testing-plugin** | testing | Test execution, TDD workflow, and testing strategies |
| **tools-plugin** | utilities | General utilities - fd, rg, jq, shell, imagemagick |
| **typescript-plugin** | language | TypeScript development - strict types, ESLint, Biome |

> **Note:** This table is generated from `.claude-plugin/marketplace.json`. To regenerate:
> ```bash
> jq -r '.plugins[] | "| **\(.name)** | \(.category) | \(.description) |"' .claude-plugin/marketplace.json
> ```

## Installation

Install plugins from this collection:

```bash
claude plugin install laurigates-claude-plugins/<plugin-name>
```

For example:
```bash
claude plugin install laurigates-claude-plugins/git-plugin
claude plugin install laurigates-claude-plugins/python-plugin
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
