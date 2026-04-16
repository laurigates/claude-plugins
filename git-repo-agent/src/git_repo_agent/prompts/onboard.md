# Onboard Workflow

Execute this 6-step onboarding workflow for the target repository.

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

Present the plan to the user via AskUserQuestion. Include:
- What exists and will be preserved
- What will be added
- Estimated scope of changes

## Step 3: Blueprint Already Initialized

Blueprint initialization is handled by the Python ``BlueprintDriver``
before this session runs (ADR-006). Confirm that `docs/blueprint/` exists
and proceed. If it does not and `SKIP_BLUEPRINT` is "False", report the
anomaly — the driver failed and should be investigated — but continue
with remaining steps. Do not invoke any blueprint-related subagent.

## Step 4: Configure Standards

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
