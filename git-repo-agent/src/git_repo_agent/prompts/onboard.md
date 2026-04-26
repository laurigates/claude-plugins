# Onboard Workflow

Execute this 6-step onboarding workflow for the target repository.

## Operating Modes

The workflow has two phases driven by the orchestrator. Mode is signalled
by the `INTERACTIVE_MODE` environment variable and the wording of the
user prompt you receive:

| Mode | Condition | Behavior |
|------|-----------|----------|
| **Interactive — planning phase** | `INTERACTIVE_MODE` = "True" AND no Phase 2 Override section in your system prompt | Steps 1–2: present a numbered plan and end your response. The orchestrator prompts the user, then opens a new session for execution. |
| **Interactive — execution phase** | `INTERACTIVE_MODE` = "True" AND your system prompt includes a "Phase 2 Override (execution)" section | Receive the embedded plan + user selections in your user prompt; execute Steps 4–6. Do NOT re-plan. |
| **Direct execution** | `INTERACTIVE_MODE` = "False" AND `DRY_RUN` = "False" | Run Steps 1–6 in a single session without stopping for plan review. |
| **Dry run** | `DRY_RUN` = "True" | Report what would be done; make no changes. |

`AskUserQuestion` is not in your tool list — it does not work in SDK
subprocess mode (ADR-003/008). Do not attempt to call it; the orchestrator
manages user interaction in Python.

## Step 1: Review Repository Analysis

Review the pre-computed `repo_analyze` and `health_score` results in your system prompt.
Key data points to consider:
- Language and framework
- Package manager
- Existing tooling (linter, formatter, test framework)
- CI/CD system
- Blueprint status (has_claude_md, has_blueprint)
- Git information
- Health score category breakdown and findings

## Step 2: Plan Onboarding

Based on the analysis, determine what's needed:

> Blueprint initialization runs before this session via the Python
> ``BlueprintDriver`` (see ADR-006). By the time you start, `docs/blueprint/`
> should already exist unless the user passed `--skip-blueprint`. Do not try
> to delegate blueprint work.

| Component | Condition | Action |
|-----------|-----------|--------|
| CLAUDE.md | `has_claude_md == false` | Generate project-specific CLAUDE.md |
| README | `has_readme == false` | Generate README.md |
| Linter | `linter == "none"` | Configure appropriate linter |
| Formatter | `formatter == "none"` | Configure appropriate formatter |
| Tests | `test_framework == "none"` | Set up testing |
| CI/CD | `ci_system == "none"` | Create GitHub Actions workflows |
| Pre-commit | `has_pre_commit == false` | Set up pre-commit hooks |

Present the plan as a numbered list of actionable steps. For each step include:

- **Number** (sequential, starting at 1)
- **Component** in brackets: `[claude-md]`, `[readme]`, `[linter]`, `[formatter]`, `[tests]`, `[ci]`, `[pre-commit]`
- **Description** of what will be added or configured

Example output format:

```
1. [claude-md] Generate CLAUDE.md with project description, tech stack, and lint/test commands
2. [readme] Generate README.md with quick-start guide
3. [linter] Configure Ruff with default rules
4. [formatter] Configure Ruff format
5. [pre-commit] Set up pre-commit hooks for ruff and gitleaks
```

After the numbered plan, list what already exists and will be preserved
(existing docs, configurations, CI workflows).

**In the planning phase only: end your response after presenting the
numbered plan.** Do NOT use `AskUserQuestion` (it is not in your tool
list). The orchestrator will collect the user's selection in Python and
start a new session for the execution phase with the plan and the
selection embedded in its user prompt. This "stop after presenting plan"
instruction does NOT apply when you see a "Phase 2 Override (execution)"
section in your system prompt.

In **direct execution mode** (`INTERACTIVE_MODE` = "False"), skip the
planning stop and proceed directly to Step 4.

## Step 3: Blueprint Already Initialized

Blueprint initialization is handled by the Python ``BlueprintDriver``
before this session runs (ADR-006). Confirm that `docs/blueprint/` exists
and proceed. If it does not and `SKIP_BLUEPRINT` is "False", report the
anomaly — the driver failed and should be investigated — but continue
with remaining steps. Do not invoke any blueprint-related subagent.

## Step 4: Configure Standards

In the **interactive execution phase** you will receive a **fresh user
prompt** from the orchestrator containing (a) the full numbered plan
from the planning phase and (b) the user's selection (e.g., `1,3,5`,
`all`, or `none`). Treat the embedded plan as authoritative. Apply
exactly the steps corresponding to the user's selection by making real
tool calls (Edit, Write, Bash). Do NOT re-plan; do NOT present the plan
again; do NOT ask the user anything.

For each missing tool, configure it based on the detected language:

| Language | Linter | Formatter | Test |
|----------|--------|-----------|------|
| TypeScript/JavaScript | Biome or ESLint | Biome or Prettier | Vitest |
| Python | Ruff | Ruff | pytest |
| Rust | Clippy | rustfmt | cargo-test |
| Go | golangci-lint | gofmt | go-test |

Note: Full configuration automation is Phase 2. For Phase 1, document what should be configured.

## Step 5: Documentation

1. Create or update `CLAUDE.md` with:
   - Project description
   - Tech stack
   - Build/test/lint commands
   - Development workflow
   - Project conventions

2. Create `README.md` if missing with:
   - Project title and description
   - Quick start guide
   - Development setup

## Step 6: Commit & Report

If not in dry-run mode:
1. Stage and commit changes with conventional commit messages to the current branch. When committing dependency changes, always include lock files (uv.lock, package-lock.json, yarn.lock, pnpm-lock.yaml, bun.lockb, Cargo.lock, poetry.lock, go.sum).
2. Do NOT create branches or push — the orchestrator manages the worktree and PR creation
3. Generate a summary report of all changes made

If in dry-run mode:
1. Report what would be changed
2. Show the analysis results
3. List recommended actions

## Environment Variables

- `DRY_RUN` — if "True", report only, make no changes
- `SKIP_CI` — if "True", skip CI/CD setup
- `SKIP_BLUEPRINT` — if "True", skip blueprint initialization
- `ONBOARD_BRANCH` — branch name for changes (default: "setup/onboard")
- `INTERACTIVE_MODE` — if "True", stop after Step 2 (planning); the orchestrator restarts a fresh session with user selections for Steps 4–6
