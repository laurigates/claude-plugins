# git-repo-agent

Claude Agent SDK application for automated repository onboarding and maintenance.

## Overview

git-repo-agent analyzes a repository's technology stack, initializes blueprint methodology structure, configures project standards, and sets up documentation — all orchestrated by Claude through the Agent SDK.

## Installation

```bash
# From this repo
uv pip install -e ./git-repo-agent

# Or with pipx
pipx install ./git-repo-agent
```

## Usage

### Onboard a Repository

```bash
# Full onboarding
git-repo-agent onboard /path/to/repo

# Preview only (no changes)
git-repo-agent onboard /path/to/repo --dry-run

# Skip specific steps
git-repo-agent onboard /path/to/repo --skip-ci --skip-blueprint

# Custom branch name
git-repo-agent onboard /path/to/repo --branch setup/init
```

### Maintenance (Phase 2)

```bash
git-repo-agent maintain /path/to/repo --fix
git-repo-agent maintain /path/to/repo --report-only
```

### Health Check (Phase 3)

```bash
git-repo-agent health /path/to/repo
```

## Architecture

```
git-repo-agent/
├── src/git_repo_agent/
│   ├── main.py              # CLI entry point (Typer)
│   ├── orchestrator.py      # Core agent orchestration
│   ├── agents/
│   │   └── blueprint.py     # Blueprint lifecycle subagent
│   ├── tools/
│   │   └── repo_analyzer.py # Repository analysis MCP tool
│   └── prompts/
│       ├── orchestrator.md   # Orchestrator system prompt
│       ├── onboard.md        # Onboard workflow instructions
│       └── blueprint.md      # Blueprint subagent prompt
└── pyproject.toml
```

### Components

| Component | Role |
|-----------|------|
| **Orchestrator** | Coordinates subagents, manages workflow |
| **repo_analyze** | MCP tool for detecting tech stack |
| **Blueprint subagent** | Initializes docs/blueprint/ structure |

### Technology Stack Detection

The `repo_analyze` tool detects:
- Language (Python, TypeScript, JavaScript, Rust, Go, Java)
- Framework (React, Next.js, Django, FastAPI, Axum, etc.)
- Package manager (uv, npm, bun, cargo, etc.)
- Test framework (pytest, vitest, jest, cargo-test)
- Linter and formatter
- CI/CD system
- Blueprint and documentation status

## Development

```bash
# Install in development mode
uv sync --directory git-repo-agent

# Run CLI
uv run --directory git-repo-agent git-repo-agent --help

# Test with dry run
uv run --directory git-repo-agent git-repo-agent onboard /tmp/test-repo --dry-run
```

## Implementation Phases

| Phase | Status | Features |
|-------|--------|----------|
| Phase 1 | Current | CLI, orchestrator, repo_analyze, blueprint subagent, onboard command |
| Phase 2 | Planned | Configure subagent, docs subagent, safety hooks, maintain command |
| Phase 3 | Planned | Quality/security subagents, health scoring, reports |
| Phase 4 | Planned | Watch mode, trend tracking, GitHub Action template |
