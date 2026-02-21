# git-repo-agent

Claude Agent SDK application for automated repository onboarding and maintenance.

## Overview

git-repo-agent analyzes a repository's technology stack, initializes blueprint methodology structure, configures project standards, runs quality and security audits, and sets up documentation — all orchestrated by Claude through the Agent SDK.

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

### Maintain a Repository

```bash
# Report-only mode (no changes)
git-repo-agent maintain /path/to/repo --report-only

# Auto-fix safe issues
git-repo-agent maintain /path/to/repo --fix

# Focus on specific categories
git-repo-agent maintain /path/to/repo --focus docs,security
```

### Quick Health Check

Runs locally without LLM calls — direct Python scoring.

```bash
git-repo-agent health /path/to/repo
```

## Architecture

```
git-repo-agent/
├── src/git_repo_agent/
│   ├── main.py                # CLI entry point (Typer)
│   ├── orchestrator.py        # Core agent orchestration
│   ├── agents/
│   │   ├── blueprint.py       # Blueprint lifecycle (sonnet)
│   │   ├── configure.py       # Project standards (haiku)
│   │   ├── docs.py            # Documentation health (haiku)
│   │   ├── quality.py         # Code quality analysis (opus)
│   │   ├── security.py        # Security audit (opus)
│   │   └── test_runner.py     # Test execution (haiku)
│   ├── tools/
│   │   ├── repo_analyzer.py   # repo_analyze MCP tool
│   │   ├── health_check.py    # health_score MCP tool
│   │   └── report.py          # report_generate MCP tool
│   ├── hooks/
│   │   └── safety.py          # Destructive command prevention
│   └── prompts/
│       ├── orchestrator.md    # Orchestrator system prompt
│       ├── onboard.md         # Onboard workflow
│       ├── maintain.md        # Maintain workflow
│       ├── health.md          # Health command reference
│       ├── blueprint.md       # Blueprint subagent prompt
│       ├── configure.md       # Configure subagent prompt
│       ├── docs.md            # Docs subagent prompt
│       ├── quality.md         # Quality subagent prompt
│       ├── security.md        # Security subagent prompt
│       ├── test_runner.md     # Test runner subagent prompt
│       └── generated/         # Compiled skill prompts
├── scripts/
│   └── compile_prompts.py     # Skill compilation pipeline
└── pyproject.toml
```

### Subagents

| Agent | Model | Purpose |
|-------|-------|---------|
| **blueprint** | sonnet | Initialize and maintain blueprint methodology (PRDs, ADRs, PRPs, manifest) |
| **configure** | haiku | Set up linting, formatting, testing, pre-commit hooks, CI/CD, coverage |
| **docs** | haiku | Check and improve README, CLAUDE.md, API docs, blueprint docs |
| **quality** | opus | Review code for complexity, duplication, anti-patterns, lint compliance |
| **security** | opus | Scan for exposed secrets, dependency CVEs, insecure configurations |
| **test_runner** | haiku | Detect test framework, execute tests, return pass/fail summary |

### MCP Tools

| Tool | Description |
|------|-------------|
| **repo_analyze** | Detect language, framework, package manager, test/lint/format tools, CI system |
| **health_score** | Score 5 categories (docs, tests, security, quality, ci) each 0–20, total 0–100 |
| **report_generate** | Format health findings as markdown, JSON, or terminal output |

### Safety Hooks

The safety module prevents destructive commands during agent execution:
- Blocks `git push --force`, `git reset --hard`, `rm -rf`
- Prevents modification of `.env` files and credentials
- Logs blocked commands for review

### Skill Compilation Pipeline

Subagents receive domain knowledge compiled from plugin skills:

```bash
# Generate compiled skill prompts
python scripts/compile_prompts.py

# Verify output is up-to-date
python scripts/compile_prompts.py --check
```

The compiler strips Claude Code metadata (frontmatter, `allowed-tools`, `AskUserQuestion` references) and keeps domain knowledge sections, producing self-contained prompt fragments for each subagent.

## Technology Stack Detection

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

# Quick health check (no API calls)
uv run --directory git-repo-agent git-repo-agent health .
```

## Implementation Phases

| Phase | Status | Features |
|-------|--------|----------|
| Phase 1 | Done | CLI, orchestrator, repo_analyze, blueprint subagent, onboard command |
| Phase 2 | Done | Configure/docs subagents, health_score, safety hooks, maintain command, skill compilation |
| Phase 3 | Done | Quality/security/test-runner subagents, report_generate, health command |
| Phase 4 | Planned | Watch mode, trend tracking, GitHub Action template |
