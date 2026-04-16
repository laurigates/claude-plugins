# git-repo-agent

Claude Agent SDK application for automated repository onboarding and maintenance.

## Overview

git-repo-agent analyzes a repository's technology stack, initializes blueprint methodology structure, configures project standards, runs quality and security audits, and sets up documentation — all orchestrated by Claude through the Agent SDK.

## Installation

```bash
# From this repo
uv tool install -e ./git-repo-agent

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

### Diagnose Pipeline Failures

Collect diagnostics from multiple GitOps sources, correlate errors, and optionally create a GitHub issue.

```bash
# Auto-detect available sources, display diagnostics
git-repo-agent diagnose /path/to/repo --dry-run

# Specify sources and Kubernetes namespace
git-repo-agent diagnose /path/to/repo --sources kubectl,argocd,actions --namespace production

# Create a GitHub issue with findings
git-repo-agent diagnose /path/to/repo --create-issue

# Target a specific ArgoCD application
git-repo-agent diagnose /path/to/repo --sources argocd --app my-app --namespace prod
```

**Diagnostic sources:**

| Source | CLI Required | Data Collected |
|--------|-------------|----------------|
| kubectl | `kubectl` | Pod status, restart counts, warning/error events |
| argocd | `argocd` | Sync status, health, conditions, deployment history |
| actions | `gh` | Workflow run failures, failed job/step details |
| packages | `gh` | Package versions, tagging consistency |
| sentry | Sentry MCP | Error events, stack traces (if MCP server configured) |
| chrome | Chrome DevTools MCP | Console errors, network failures (if MCP server configured) |

kubectl and argocd operations are **strictly read-only** — safety hooks block any mutating commands.

### Scheduled / Non-Interactive Runs

`onboard`, `maintain`, and `diagnose` all support a non-interactive mode
designed for Claude Code desktop scheduled jobs, cron, and GitHub Actions.
See `docs/adr/005-non-interactive-scheduled-execution.md` for the full
contract.

```bash
# Daily maintenance with auto-PR, exits 3 if an earlier scheduled run is still
# holding the lock, exit 2 on config error, exit 4 if a safety hook blocks an op.
git-repo-agent maintain /repo \
  --fix --non-interactive \
  --auto-pr=on-changes --on-duplicate=skip \
  --refresh-base --log-format=json

# Report-only: creates de-duplicated GitHub issues, never commits.
git-repo-agent maintain /repo \
  --report-only --non-interactive \
  --auto-issues=on-findings --log-format=json
```

**Key flags**

| Flag | Values | Use |
|------|--------|-----|
| `--non-interactive` | — | Required when stdin is not a TTY |
| `--auto-pr` | `always`, `never`, `on-changes` | Policy for PR creation |
| `--auto-issues` | `always`, `never`, `on-findings` | Policy for issue creation |
| `--on-duplicate` | `skip`, `append`, `new` | Behaviour if an open PR already exists for this workflow |
| `--refresh-base` | flag | `git fetch` + ff the base before starting |
| `--log-format` | `text`, `json`, `plain` | Output style (auto-selects `plain` when piped) |
| `--max-cost-usd` | float | Warn if session cost exceeds this |

**Exit codes**

| Code | Meaning |
|------|---------|
| 0 | Success |
| 1 | Unexpected runtime error |
| 2 | Config error (missing flag, bad value, missing `gh` auth, non-TTY without `--non-interactive`) |
| 3 | Locked — another run holds the advisory lock |
| 4 | Blocked by a safety hook |

**GitHub Actions snippet**

```yaml
name: Scheduled maintenance
on:
  schedule:
    - cron: "0 5 * * *"
  workflow_dispatch:
jobs:
  maintain:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: astral-sh/setup-uv@v3
      - run: uv tool install git+https://github.com/laurigates/claude-plugins#subdirectory=git-repo-agent
      - env:
          GH_TOKEN: ${{ secrets.GITHUB_TOKEN }}
          ANTHROPIC_API_KEY: ${{ secrets.ANTHROPIC_API_KEY }}
        run: |
          git-repo-agent maintain . \
            --fix --non-interactive \
            --auto-pr=on-changes --on-duplicate=skip \
            --refresh-base --log-format=json
```

The two-phase interactive `maintain` (no `--fix`, no `--report-only`)
requires a human and cannot be run non-interactively — the CLI exits
with code 2 in that case.

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
│   ├── blueprint_driver.py    # Blueprint state machine (ADR-006)
│   ├── agents/
│   │   ├── configure.py       # Project standards (haiku)
│   │   ├── diagnose.py        # Pipeline diagnostics (sonnet)
│   │   ├── docs.py            # Documentation health (haiku)
│   │   ├── quality.py         # Code quality analysis (opus)
│   │   ├── security.py        # Security audit (opus)
│   │   └── test_runner.py     # Test execution (haiku)
│   ├── tools/
│   │   ├── repo_analyzer.py   # repo_analyze MCP tool
│   │   ├── health_check.py    # health_score MCP tool
│   │   ├── pipeline_collector.py # Pipeline diagnostics collector
│   │   └── report.py          # report_generate MCP tool
│   ├── hooks/
│   │   └── safety.py          # Destructive command prevention
│   └── prompts/
│       ├── orchestrator.md    # Orchestrator system prompt
│       ├── onboard.md         # Onboard workflow
│       ├── maintain.md        # Maintain workflow
│       ├── diagnose.md        # Diagnose subagent prompt
│       ├── diagnose_workflow.md # Diagnose workflow
│       ├── health.md          # Health command reference
│       ├── configure.md       # Configure subagent prompt
│       ├── docs.md            # Docs subagent prompt
│       ├── quality.md         # Quality subagent prompt
│       ├── security.md        # Security subagent prompt
│       ├── test_runner.md     # Test runner subagent prompt
│       └── compiler.py        # Runtime skill compilation
├── scripts/
│   └── compile_prompts.py     # Debug/inspection CLI for compiled prompts
└── pyproject.toml
```

### Subagents

| Agent           | Model  | Skills | Purpose                                                                    |
| --------------- | ------ | ------ | -------------------------------------------------------------------------- |
| **configure**   | haiku  | 9      | Set up linting, formatting, testing, pre-commit, CI/CD, coverage, release-please, containers, Sentry |
| **diagnose**    | sonnet | 3      | Correlate pipeline failures using kubectl debugging, GitHub Actions inspection, systematic diagnostics |
| **docs**        | haiku  | 5      | Check and improve README, CLAUDE.md, blueprint docs, doc quality analysis  |
| **quality**     | opus   | 6      | Review code for complexity, duplication, anti-patterns, silent degradation, lint compliance |
| **security**    | opus   | 3      | Scan for exposed secrets, dependency CVEs, insecure configurations, GitHub Actions auth |
| **test_runner** | haiku  | 5      | Detect test framework, execute tests, analyze failures, assess test quality |

### Blueprint Driver

The blueprint lifecycle runs as a deterministic Python state machine
(`blueprint_driver.py`), not a subagent. Each phase loads exactly one
compiled skill into its own `ClaudeSDKClient` session. See ADR-006 for
rationale.

CLI surface (`git-repo-agent blueprint <subcommand>`):

| Subcommand | Phases | Purpose |
|---|---|---|
| `status` | `blueprint-status` → `feature-tracker-status` | Report version, docs, tracker stats |
| `upgrade` | `blueprint-upgrade` → `sync-ids` → `adr-validate` | Migrate to latest format |
| `sync` | `blueprint-sync` | Detect stale generated content |
| `scan` | `workspace-scan` → `feature-tracker-sync` → `feature-tracker-status` | Refresh monorepo rollups |
| `adr-list` | `blueprint-adr-list` | List ADRs as markdown table |
| `derive-plans` | `blueprint-derive-plans` | Derive PRDs/ADRs/PRPs from git |
| `generate-rules` | `blueprint-generate-rules` | Auto-generate project rules |
| `promote <target>` | `blueprint-promote` | Preserve custom edits |
| `prp-create <feature>` | `blueprint-prp-create` | Create a PRP for a feature |
| `prp-execute <prp-name>` | `blueprint-prp-execute` | Execute PRP with TDD gates |
| `work-order [--from-issue N]` | `blueprint-work-order` | Create isolated work order |

The `onboard` command also runs a 9-phase onboarding sequence before the
LLM orchestrator takes over.

### MCP Tools

| Tool                | Description                                                                    |
| ------------------- | ------------------------------------------------------------------------------ |
| **repo_analyze**    | Detect language, framework, package manager, test/lint/format tools, CI system |
| **health_score**    | Score 5 categories (docs, tests, security, quality, ci) each 0–20, total 0–100 |
| **report_generate** | Format health findings as markdown, JSON, or terminal output                   |

### Safety Hooks

The safety module prevents destructive commands during agent execution:

- Blocks `git push --force`, `git reset --hard`, `rm -rf`
- Prevents modification of `.env` files and credentials
- Enforces read-only `kubectl` and `argocd` operations (allowlist approach)
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

# Pipeline diagnostics (dry run)
uv run --directory git-repo-agent git-repo-agent diagnose . --dry-run
```

## Implementation Phases

| Phase   | Status  | Features                                                                                  |
| ------- | ------- | ----------------------------------------------------------------------------------------- |
| Phase 1 | Done    | CLI, orchestrator, repo_analyze, blueprint driver (ADR-006), onboard command              |
| Phase 2 | Done    | Configure/docs subagents, health_score, safety hooks, maintain command, skill compilation |
| Phase 3 | Done    | Quality/security/test-runner subagents, report_generate, health command                   |
| Phase 4 | In progress | Non-interactive / scheduled execution (ADR-005); watch mode and trend tracking planned |
| Phase 5 | Done    | Pipeline diagnostics (kubectl, ArgoCD, GitHub Actions, Sentry, Chrome DevTools)           |
