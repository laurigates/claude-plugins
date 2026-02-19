# Git Repo Agent — Design Plan

A Claude Agent SDK application that onboards and maintains git repositories using the claude-plugins ecosystem.

## Problem Statement

Today, setting up a repo with the full blueprint methodology, project standards, and quality tooling requires manually invoking many skills in sequence (`/blueprint:init`, `/blueprint:derive-*`, `/configure:*`, etc.). Ongoing maintenance (stale docs, missing tests, security issues) requires remembering to run checks periodically.

This agent automates both workflows:
- **Onboarding**: Analyze a repo and bootstrap it with blueprint structure, documentation, standards, and CI/CD
- **Maintenance**: Periodically audit code quality, docs freshness, test coverage, dependencies, and security

---

## Architecture Overview

```
┌─────────────────────────────────────────────────────┐
│                  git-repo-agent                      │
│              (Claude Agent SDK app)                   │
│                                                       │
│  ┌─────────────┐  ┌──────────────┐  ┌─────────────┐ │
│  │ Orchestrator │──│ Custom Tools  │──│   Hooks     │ │
│  │   (Opus)     │  │ (MCP Server)  │  │ (Safety)    │ │
│  └──────┬───────┘  └──────────────┘  └─────────────┘ │
│         │                                             │
│  ┌──────┴─────────────────────────────┐               │
│  │           Subagents                 │               │
│  ├─────────────┬────────────┬─────────┤               │
│  │ blueprint   │ configure  │ quality │               │
│  │ (sonnet)    │ (haiku)    │ (opus)  │               │
│  ├─────────────┼────────────┼─────────┤               │
│  │ docs        │ test-runner│ security│               │
│  │ (haiku)     │ (haiku)    │ (opus)  │               │
│  └─────────────┴────────────┴─────────┘               │
└─────────────────────────────────────────────────────┘
                        │
              ┌─────────┴─────────┐
              │   Target Repo     │
              │   (cwd)           │
              └───────────────────┘
```

---

## Technology Choice: Python

**Why Python over TypeScript:**
- `pip install claude-agent-sdk` bundles the CLI — no separate install
- Simpler deployment for CLI tools (`pipx install`, single entry point)
- `@tool` decorator for custom MCP tools is cleaner than TS equivalent
- Most repos being managed will have Python available (or can install via pipx)

---

## Project Structure

```
git-repo-agent/
├── .claude-plugin/
│   └── plugin.json
├── src/
│   ├── __init__.py
│   ├── main.py              # CLI entry point (click/typer)
│   ├── orchestrator.py      # Main agent orchestration
│   ├── agents/              # Subagent definitions
│   │   ├── __init__.py
│   │   ├── blueprint.py     # Blueprint lifecycle subagent
│   │   ├── configure.py     # Standards/tooling subagent
│   │   ├── quality.py       # Code quality subagent
│   │   ├── docs.py          # Documentation subagent
│   │   ├── test_runner.py   # Test execution subagent
│   │   └── security.py      # Security audit subagent
│   ├── tools/               # Custom MCP tools
│   │   ├── __init__.py
│   │   ├── repo_analyzer.py # Repo detection and analysis
│   │   ├── health_check.py  # Health scoring
│   │   └── report.py        # Report generation
│   ├── hooks/               # Safety hooks
│   │   ├── __init__.py
│   │   └── safety.py        # Destructive action prevention
│   └── prompts/             # System prompts as text files
│       ├── orchestrator.md
│       ├── onboard.md
│       └── maintain.md
├── skills/                   # Plugin skills for this agent
│   └── repo-agent-run/
│       └── SKILL.md
├── agents/                   # Agent definition for plugin system
│   └── repo-agent.md
├── pyproject.toml
├── README.md
└── CHANGELOG.md
```

---

## Modes of Operation

### 1. Onboard Mode (`git-repo-agent onboard`)

Full first-time setup for a repository.

```bash
git-repo-agent onboard /path/to/repo [--dry-run] [--skip-ci] [--skip-blueprint]
```

**Workflow:**

```
Step 1: Analyze Repository (parallel)
├── Detect language/framework (package.json, pyproject.toml, Cargo.toml, go.mod)
├── Detect existing tooling (linters, formatters, test frameworks)
├── Detect existing documentation (README, docs/, CLAUDE.md)
├── Detect CI/CD (GitHub Actions, .gitlab-ci.yml)
├── Detect existing blueprint artifacts (docs/blueprint/, docs/prds/)
└── Git history analysis (commit style, branch patterns)

Step 2: Plan Onboarding (orchestrator decides)
├── What's missing vs what exists
├── What standards to apply (based on language/framework)
├── What blueprint artifacts to derive
└── Present plan to user → AskUserQuestion for approval

Step 3: Execute Blueprint Init
├── Initialize blueprint structure if missing
├── Derive PRDs from existing docs/README
├── Derive ADRs from codebase architecture
├── Sync document IDs
└── Generate rules from PRDs

Step 4: Configure Standards (parallel subagents)
├── Linting (biome/eslint/ruff based on language)
├── Formatting (prettier/biome/ruff based on language)
├── Testing (vitest/jest/pytest/cargo-test setup)
├── Pre-commit hooks
├── Coverage thresholds
└── CI workflows (GitHub Actions)

Step 5: Documentation
├── Update/create CLAUDE.md
├── Generate README if missing
├── Create contributing guide
└── Set up docs structure

Step 6: Commit & Report
├── Create onboarding branch
├── Commit all changes (conventional commits)
├── Generate summary report
└── Optionally create PR
```

### 2. Maintain Mode (`git-repo-agent maintain`)

Periodic health check and maintenance.

```bash
git-repo-agent maintain /path/to/repo [--fix] [--report-only] [--focus=docs,tests,security]
```

**Workflow:**

```
Step 1: Health Check (parallel subagents)
├── Blueprint sync (stale docs, missing cross-refs)
├── Test coverage analysis
├── Documentation freshness (modified dates, accuracy)
├── Dependency audit (CVEs, outdated)
├── Security scan (secrets, vulnerabilities)
├── Code quality metrics (complexity, duplication)
└── ADR validation (relationships, conflicts)

Step 2: Score & Prioritize
├── Generate health score (0-100)
├── Categorize issues by severity
├── Rank by effort-to-impact ratio
└── Present findings

Step 3: Fix (if --fix)
├── Update stale documentation
├── Fix blueprint cross-references
├── Update dependency versions (non-breaking)
├── Fix code quality issues (auto-fixable)
└── Each fix = separate commit

Step 4: Report
├── Health scorecard
├── Issues found vs fixed
├── Recommendations for manual fixes
└── Comparison to previous run (if available)
```

### 3. Watch Mode (`git-repo-agent watch`)

Continuous monitoring via scheduled runs.

```bash
git-repo-agent watch /path/to/repo --interval=daily --focus=security,tests
```

**Implementation:** Generates a cron job or GitHub Action that invokes `maintain` periodically.

---

## Subagent Definitions

### Blueprint Subagent (sonnet)

```python
AgentDefinition(
    description="Blueprint lifecycle management. Initialize, derive, sync, and maintain "
                "blueprint artifacts (PRDs, ADRs, PRPs, work orders, manifest).",
    prompt=BLUEPRINT_PROMPT,  # Loaded from prompts/
    tools=["Read", "Write", "Edit", "Bash", "Glob", "Grep"],
    model="sonnet",
)
```

**Responsibilities:**
- Run `/blueprint:init` equivalent logic
- Derive PRDs from existing docs (`/blueprint:derive-prd`)
- Derive ADRs from codebase (`/blueprint:derive-adr`)
- Sync document IDs (`/blueprint:sync-ids`)
- Check for stale content (`/blueprint:sync`)
- Validate ADR relationships (`/blueprint:adr-validate`)
- Update manifest and feature tracker

### Configure Subagent (haiku)

```python
AgentDefinition(
    description="Project standards configuration. Set up linting, formatting, testing, "
                "pre-commit hooks, CI/CD workflows, and code coverage.",
    prompt=CONFIGURE_PROMPT,
    tools=["Read", "Write", "Edit", "Bash", "Glob", "Grep"],
    model="haiku",
)
```

**Responsibilities:**
- Detect language/framework and select appropriate tools
- Configure linting (`/configure:linting` equivalent)
- Configure formatting (`/configure:formatting`)
- Configure testing (`/configure:tests`)
- Configure pre-commit (`/configure:pre-commit`)
- Configure CI workflows (`/configure:workflows`)
- Configure coverage thresholds (`/configure:coverage`)

### Quality Subagent (opus)

```python
AgentDefinition(
    description="Code quality analysis. Review code for quality, complexity, duplication, "
                "and adherence to project standards. Provides severity-ranked findings.",
    prompt=QUALITY_PROMPT,
    tools=["Read", "Glob", "Grep", "Bash"],
    model="opus",
)
```

### Docs Subagent (haiku)

```python
AgentDefinition(
    description="Documentation health. Check freshness, accuracy, completeness of "
                "README, CLAUDE.md, API docs, and blueprint documents.",
    prompt=DOCS_PROMPT,
    tools=["Read", "Write", "Edit", "Glob", "Grep"],
    model="haiku",
)
```

### Test Runner Subagent (haiku)

```python
AgentDefinition(
    description="Run tests and report results. Detects framework, executes with "
                "optimized flags, returns concise pass/fail summary.",
    prompt=TEST_RUNNER_PROMPT,
    tools=["Read", "Glob", "Grep", "Bash"],
    model="haiku",
)
```

### Security Subagent (opus)

```python
AgentDefinition(
    description="Security audit. Scan for exposed secrets, dependency vulnerabilities, "
                "injection risks, and insecure configurations.",
    prompt=SECURITY_PROMPT,
    tools=["Read", "Glob", "Grep", "Bash"],
    model="opus",
)
```

---

## Custom MCP Tools

### `repo_analyze`

Analyzes a repository and returns structured metadata.

```python
@tool("repo_analyze", "Analyze repository structure and technology stack", {
    "path": str,  # Repository path
})
async def repo_analyze(args):
    # Returns: language, framework, package_manager, test_framework,
    #          linter, formatter, ci_system, doc_structure,
    #          blueprint_status, git_info
```

### `health_score`

Computes a numeric health score from subagent findings.

```python
@tool("health_score", "Compute repository health score from findings", {
    "findings": dict,  # Categorized findings from subagents
})
async def health_score(args):
    # Returns: overall_score (0-100), category_scores,
    #          trend (vs previous), grade (A-F)
```

### `report_generate`

Generates a formatted health report.

```python
@tool("report_generate", "Generate formatted health report", {
    "scores": dict,
    "findings": dict,
    "format": str,  # "markdown" | "json" | "terminal"
})
async def report_generate(args):
    # Returns: formatted report string
```

---

## Hooks (Safety Gates)

```python
hooks = {
    "PreToolUse": [
        HookMatcher(
            matcher="Bash",
            hooks=[prevent_destructive_git_ops]
        ),
        HookMatcher(
            matcher="Write|Edit",
            hooks=[prevent_env_file_modification]
        ),
    ],
    "PostToolUse": [
        HookMatcher(
            matcher="Bash",
            hooks=[log_git_operations]
        ),
    ],
}
```

**Safety rules:**
- Block `git push --force` to main/master
- Block modifications to `.env`, credentials files
- Block `rm -rf` on non-build directories
- Log all git write operations for audit trail

---

## CLI Interface

```bash
# Onboard a new repo
git-repo-agent onboard /path/to/repo
git-repo-agent onboard /path/to/repo --dry-run          # Preview only
git-repo-agent onboard /path/to/repo --skip-ci           # Skip CI setup
git-repo-agent onboard /path/to/repo --branch=setup/init # Custom branch

# Maintain an existing repo
git-repo-agent maintain /path/to/repo
git-repo-agent maintain /path/to/repo --fix              # Auto-fix issues
git-repo-agent maintain /path/to/repo --report-only      # No changes
git-repo-agent maintain /path/to/repo --focus=docs,tests # Specific areas

# Generate watch schedule
git-repo-agent watch /path/to/repo --interval=daily
git-repo-agent watch /path/to/repo --github-action       # Generate GH Action

# Check health score
git-repo-agent health /path/to/repo                      # Quick health check
```

**Implementation:** Python CLI using `click` or `typer`:

```python
# main.py
import typer
from .orchestrator import run_onboard, run_maintain, run_health

app = typer.Typer()

@app.command()
def onboard(
    repo: str,
    dry_run: bool = False,
    skip_ci: bool = False,
    skip_blueprint: bool = False,
    branch: str = "setup/onboard",
):
    """Onboard a repository with blueprint structure and standards."""
    asyncio.run(run_onboard(repo, dry_run, skip_ci, skip_blueprint, branch))

@app.command()
def maintain(
    repo: str,
    fix: bool = False,
    report_only: bool = False,
    focus: list[str] = None,
):
    """Run maintenance checks and optionally fix issues."""
    asyncio.run(run_maintain(repo, fix, report_only, focus))

@app.command()
def health(repo: str):
    """Quick health score for a repository."""
    asyncio.run(run_health(repo))
```

---

## Orchestrator Flow (Core Logic)

```python
# orchestrator.py
from claude_agent_sdk import query, ClaudeAgentOptions, AgentDefinition
from .agents import blueprint, configure, quality, docs, test_runner, security
from .tools import repo_analyzer, health_check, report
from .hooks import safety

async def run_onboard(repo_path, dry_run, skip_ci, skip_blueprint, branch):
    tools_server = create_sdk_mcp_server(
        name="repo-tools",
        version="1.0.0",
        tools=[repo_analyzer.repo_analyze, health_check.health_score, report.report_generate],
    )

    options = ClaudeAgentOptions(
        system_prompt=load_prompt("orchestrator") + "\n" + load_prompt("onboard"),
        cwd=repo_path,
        max_turns=50,
        allowed_tools=[
            "Read", "Write", "Edit", "Bash", "Glob", "Grep",
            "Task", "AskUserQuestion", "TodoWrite",
            "mcp__repo-tools__repo_analyze",
            "mcp__repo-tools__health_score",
            "mcp__repo-tools__report_generate",
        ],
        permission_mode="acceptEdits",
        mcp_servers={"repo-tools": tools_server},
        agents={
            "blueprint": blueprint.definition,
            "configure": configure.definition,
            "quality": quality.definition,
            "docs": docs.definition,
            "test-runner": test_runner.definition,
            "security": security.definition,
        },
        hooks=safety.hooks,
        env={
            "DRY_RUN": str(dry_run),
            "SKIP_CI": str(skip_ci),
            "SKIP_BLUEPRINT": str(skip_blueprint),
            "ONBOARD_BRANCH": branch,
        },
    )

    async for message in query(
        prompt=f"Onboard this repository at {repo_path}. "
               f"Analyze the repo, initialize blueprint structure, "
               f"configure project standards, and set up documentation. "
               f"{'DRY RUN - do not make changes, only report.' if dry_run else ''}",
        options=options,
    ):
        if hasattr(message, "content"):
            for block in message.content:
                if hasattr(block, "text"):
                    print(block.text)
```

---

## System Prompts (Key Excerpts)

### Orchestrator Prompt

```markdown
You are a Git Repository Agent that onboards and maintains code repositories.

You have access to specialized subagents:
- **blueprint**: Blueprint lifecycle (PRDs, ADRs, PRPs, manifest)
- **configure**: Project standards (linting, formatting, testing, CI/CD)
- **quality**: Code quality analysis
- **docs**: Documentation health
- **test-runner**: Test execution
- **security**: Security scanning

## Principles
- Always analyze before acting (use repo_analyze first)
- Present a plan to the user before making changes
- Use parallel subagents for independent tasks
- Each change gets its own conventional commit
- Never force-push, never modify .env files
- Prefer small, incremental changes over big-bang rewrites
```

### Onboard Prompt

```markdown
## Onboard Workflow

1. Use `repo_analyze` tool to detect language, framework, existing tooling
2. Based on analysis, plan which subagents to invoke:
   - Always: blueprint (init + derive)
   - Always: docs (CLAUDE.md, README)
   - If no linter: configure (linting)
   - If no formatter: configure (formatting)
   - If no tests: configure (testing)
   - If no CI: configure (workflows)
   - If no pre-commit: configure (pre-commit)
3. Present plan to user via AskUserQuestion
4. Launch subagents in parallel where possible:
   - Parallel group 1: blueprint init + docs
   - Parallel group 2: configure (all standards)
   - Sequential: blueprint derive (needs docs to exist first)
5. Create onboarding branch, commit all changes
6. Generate health report showing before/after scores
```

---

## Integration with Plugin Ecosystem

The agent's subagent prompts embed the knowledge from existing plugin skills. Rather than invoking `/blueprint:init` as a slash command (which requires Claude Code CLI interactively), the subagent prompts contain the equivalent logic extracted from the skill files.

**How skill knowledge flows into the agent:**

```
Plugin Skills (SKILL.md files)
        │
        ▼
Subagent Prompts (src/prompts/*.md)
        │  (skill logic embedded as instructions)
        ▼
AgentDefinition.prompt
        │
        ▼
Subagent executes the workflow
```

For example, the blueprint subagent's prompt includes the initialization steps from `blueprint-init/SKILL.md`, the derivation logic from `blueprint-derive-*/SKILL.md`, etc. — adapted for autonomous execution rather than interactive invocation.

---

## Packaging & Distribution

### As a Python Package

```toml
# pyproject.toml
[project]
name = "git-repo-agent"
version = "1.0.0"
description = "Claude Agent SDK app for repo onboarding and maintenance"
requires-python = ">=3.10"
dependencies = [
    "claude-agent-sdk>=0.2.0",
    "typer>=0.9.0",
    "rich>=13.0.0",
]

[project.scripts]
git-repo-agent = "git_repo_agent.main:app"
```

```bash
# Install
pipx install git-repo-agent

# Or from this repo
pip install -e ./git-repo-agent
```

### As a Plugin in This Repo

The agent also lives as a plugin in claude-plugins, providing:
- A user-invocable skill (`/repo-agent:onboard`, `/repo-agent:maintain`)
- An agent definition (`agents/repo-agent.md`) for use as a teammate/subagent
- The Python SDK app for standalone CLI usage

---

## Running the Agent

### Standalone CLI

```bash
# Set API key
export ANTHROPIC_API_KEY=sk-ant-...

# Onboard a repo
git-repo-agent onboard ~/projects/my-app

# Maintain a repo
git-repo-agent maintain ~/projects/my-app --fix

# Quick health check
git-repo-agent health ~/projects/my-app
```

### As a GitHub Action

```yaml
# .github/workflows/repo-maintain.yml
name: Repo Maintenance
on:
  schedule:
    - cron: '0 6 * * 1'  # Weekly Monday 6am
  workflow_dispatch:

jobs:
  maintain:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-python@v5
        with:
          python-version: '3.12'
      - run: pip install git-repo-agent
      - run: git-repo-agent maintain . --report-only --focus=security,deps
        env:
          ANTHROPIC_API_KEY: ${{ secrets.ANTHROPIC_API_KEY }}
```

### From Claude Code (via plugin skill)

```
User: /repo-agent:onboard
→ Runs the agent within the current Claude Code session
```

---

## Implementation Phases

### Phase 1: Foundation (MVP)
- [ ] Project scaffolding (pyproject.toml, src/ structure)
- [ ] CLI entry point with typer
- [ ] Orchestrator with `query()` and basic system prompt
- [ ] `repo_analyze` custom tool
- [ ] Blueprint subagent (init + derive)
- [ ] `onboard` command (basic flow)
- [ ] Plugin metadata (plugin.json, marketplace entry)

### Phase 2: Standards & Configuration
- [ ] Configure subagent (linting, formatting, testing, CI)
- [ ] Docs subagent (CLAUDE.md, README)
- [ ] Safety hooks (destructive action prevention)
- [ ] `maintain` command (basic health check)
- [ ] Health scoring tool

### Phase 3: Quality & Reporting
- [ ] Quality subagent (code review metrics)
- [ ] Security subagent (secrets, CVEs)
- [ ] Test runner subagent
- [ ] Report generation tool
- [ ] `health` command with scoring

### Phase 4: Automation
- [ ] `watch` command (cron/GH Action generation)
- [ ] Trend tracking (score history)
- [ ] GitHub Action template
- [ ] Session resumption for ongoing conversations

---

## Open Questions

1. **Skill embedding vs. skill invocation**: Should subagent prompts embed skill logic directly, or should they invoke skills via `SlashCommand` tool? Embedding is more portable but harder to keep in sync. Invoking requires the plugin to be installed.

2. **Scope of auto-fix**: How aggressively should `--fix` mode operate? Options:
   - Conservative: Only auto-fixable linting, doc date updates
   - Moderate: Above + dependency updates, missing test stubs
   - Aggressive: Above + code refactoring, architecture changes

3. **Multi-repo support**: Should the agent support batch operations across multiple repos? Could be a future phase.

4. **State persistence**: Where to store health history for trend tracking? Options:
   - `docs/blueprint/health-history.json` in the repo
   - `~/.git-repo-agent/` local directory
   - GitHub Action artifacts
