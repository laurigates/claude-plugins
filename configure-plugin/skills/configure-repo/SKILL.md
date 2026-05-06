---
name: configure-repo
description: |
  End-to-end repo config driver. Produces a working .claude/ directory
  (settings.json with marketplace enrollment + permissions), a SessionStart
  hook, and scripts/install_pkgs.sh — all staged for commit. Use when
  onboarding any repo to Claude Code with the laurigates/claude-plugins
  marketplace. Runs /configure:claude-plugins, /configure:web-session,
  /health:check, and optionally prompts for migration offers (mypy→ty, etc.).
allowed-tools: Glob, Grep, Read, Write, Edit, Bash(git add *), Bash(git status *), Bash(git diff *), Bash(find *), Bash(mkdir *), Bash(test *), AskUserQuestion, TodoWrite, SlashCommand
args: "[--check-only] [--skip-health] [--skip-migrations]"
argument-hint: "[--check-only] [--skip-health] [--skip-migrations]"
created: 2026-04-14
modified: 2026-04-14
reviewed: 2026-05-06
---

# /configure:repo

End-to-end driver that brings any repo's Claude Code configuration to a healthy baseline in one command. Produces committed-ready files: `.claude/settings.json` (permissions + marketplace enrollment), a `SessionStart` hook, and `scripts/install_pkgs.sh`.

## When to Use This Skill

| Use this skill when... | Use another approach when... |
|------------------------|------------------------------|
| Onboarding a new repo to Claude Code from scratch | Changing a single setting — use `/configure:claude-plugins` or `/configure:web-session` directly |
| Updating an existing repo to the latest baseline config | Diagnosing a specific hook or plugin issue — use `/health:check` directly |
| Checking what would change before committing | Running a health-only audit — use `/health:check` |
| Setting up a repo for ephemeral web sessions (claude.ai/code) | Managing plugins on an already-configured repo |

## Context

Detect current state and project stack:

- Existing settings: !`find .claude -maxdepth 1 -name 'settings.json' -type f`
- Install script: !`find . -name 'install_pkgs.sh' -path '*/scripts/*'`
- Workflows: !`find .github/workflows -maxdepth 1 -name 'claude*.yml'`
- Project files: !`find . -maxdepth 1 \( -name 'package.json' -o -name 'pyproject.toml' -o -name 'Cargo.toml' -o -name 'go.mod' -o -name 'justfile' -o -name 'Justfile' \)`
- ESP indicators: !`find . -maxdepth 2 \( -name 'idf_component.yml' -o -name 'sdkconfig' \)`
- Pre-commit config: !`find . -maxdepth 1 -name '.pre-commit-config.yaml'`
- Git remote: !`git remote -v`

## Parameters

| Parameter | Description |
|-----------|-------------|
| `--check-only` | Report what would change without modifying any files |
| `--skip-health` | Skip the final `/health:check` validation step |
| `--skip-migrations` | Skip migration detection (don't offer mypy→ty etc.) |

## Execution

Execute this end-to-end repository configuration workflow:

### Step 1: Detect project stack

Identify the stack from the context above. Produce a brief summary:

```
Stack detected:
  Language:   Python (uv + ruff) | Node/TypeScript | Rust | Go | ESP-IDF | ESPHome | ...
  Tools:      pre-commit, just, docker, ...
  Migrations: mypy→ty candidate | black→ruff-format candidate | flake8→ruff candidate | ESLint→Biome candidate
```

If `--check-only`, annotate all subsequent steps as "(would do)" rather than doing them.

### Step 2: Configure plugins, permissions, and marketplace enrollment

Invoke `/configure:claude-plugins --fix` using the SlashCommand tool.

This step:
- Selects recommended plugins based on detected stack
- Writes `permissions.allow` (common + stack-aware) to `.claude/settings.json`
- Writes `extraKnownMarketplaces` + `enabledPlugins` to `.claude/settings.json` (critical for web sessions)
- Creates/updates `.github/workflows/claude.yml` and `claude-code-review.yml`

### Step 3: Configure SessionStart hook and install script

Invoke `/configure:web-session --fix` using the SlashCommand tool.

This step generates `scripts/install_pkgs.sh` with idempotent tool installs gated on `CLAUDE_CODE_REMOTE=true`, and wires the `SessionStart` hook in `.claude/settings.json`.

If the project uses language-level deps (Python, Node, Rust, Go), also invoke `/hooks:session-start-hook --remote-only` using the SlashCommand tool to add dependency installation to the hook script.

### Step 4: Offer migrations (unless --skip-migrations)

Detect these migratable patterns and ask whether to run each migration via `AskUserQuestion`:

| Pattern detected | Migration to offer | Skill to invoke |
|------------------|--------------------|-----------------|
| `.pre-commit-config.yaml` contains `mirrors-mypy` or `[tool.mypy]` in pyproject.toml | mypy → ty | `/migration-patterns:mypy-to-ty` |
| `.pre-commit-config.yaml` contains `psf/black` | black → ruff-format | `/migration-patterns:black-to-ruff-format` |
| `.pre-commit-config.yaml` contains `pycqa/flake8` or `PyCQA/isort` | flake8/isort → ruff | `/migration-patterns:flake8-to-ruff` |
| `.eslintrc*` or `eslint.config.*` present, no `biome.json` | ESLint → Biome | `/migration-patterns:eslint-to-biome` |

For each detected pattern, ask: "Found [pattern] — offer to migrate? (y/n)". Only run the migration skill if the user confirms.

Migrations are **not** part of the happy path. If the user declines all migrations, continue to Step 5.

### Step 5: Validate with health check (unless --skip-health)

Invoke `/health:check` using the SlashCommand tool.

Parse the health check output. If any checks fail:
- Report the specific failures
- Suggest how to fix them
- Continue (do not abort — the config files are still staged)

### Step 6: Stage files and report

Run `git status` to list all created/modified files. Stage the relevant files:

```bash
git add .claude/settings.json
git add scripts/install_pkgs.sh        # if created
git add .github/workflows/claude.yml   # if created
git add .github/workflows/claude-code-review.yml  # if created
```

Print a summary:

```
configure-repo complete
=======================
Repository: <repo-name>

Files staged:
  .claude/settings.json             [CREATED | UPDATED]
  scripts/install_pkgs.sh           [CREATED | UPDATED | SKIPPED]
  .github/workflows/claude.yml      [CREATED | UPDATED | SKIPPED]
  .github/workflows/claude-code-review.yml  [CREATED | UPDATED | SKIPPED]

Marketplace enrollment:
  .claude/settings.json → extraKnownMarketplaces.claude-plugins  ✓
  .github/workflows/claude.yml → plugin_marketplaces             ✓

Health check: PASS | WARN (<N> warnings) | FAIL (<N> failures)

Next steps:
  1. Review the staged diff: git diff --cached
  2. Commit: git commit -m "chore(claude): configure repo for Claude Code"
  3. Add CLAUDE_CODE_OAUTH_TOKEN to repository secrets
  4. Push and test: mention @claude in a PR comment
```

If `--check-only` was set, prefix the summary with "DRY RUN — no files modified".

## Important Notes

- This skill is a thin orchestrator — it contains no business logic. All logic lives in its dependencies.
- Never auto-commit; always stage and let the user review with `git diff --cached`.
- `AskUserQuestion` is required for migration offers — this skill must not run on `haiku` model.
- `extraKnownMarketplaces` in `.claude/settings.json` is the key to surviving ephemeral web sessions.
- The SessionStart hook uses `CLAUDE_CODE_REMOTE` guard so it is a no-op in local sessions.

## Agentic Optimizations

| Context | Command |
|---------|---------|
| Full setup with health check | `/configure:repo` |
| Dry-run, no file changes | `/configure:repo --check-only` |
| Setup without migration prompts | `/configure:repo --skip-migrations` |
| Quick setup, skip health | `/configure:repo --skip-health --skip-migrations` |
| Stage and review | `git diff --cached` |

## Dependencies (driver freshness)

This skill orchestrates these dependencies. If any dependency's `modified:` date is newer than this skill's `reviewed:` date, run `scripts/check-driver-freshness.sh` and update this skill accordingly.

| Dependency | File |
|------------|------|
| `/configure:claude-plugins` | `configure-plugin/skills/configure-claude-plugins/SKILL.md` |
| `/configure:web-session` | `configure-plugin/skills/configure-web-session/SKILL.md` |
| `/hooks:session-start-hook` | `hooks-plugin/skills/hooks-session-start-hook/SKILL.md` |
| `/health:check` | `health-plugin/skills/health-check/SKILL.md` |
| `/migration-patterns:mypy-to-ty` | `migration-patterns-plugin/skills/mypy-to-ty/SKILL.md` |
| `/migration-patterns:black-to-ruff-format` | `migration-patterns-plugin/skills/black-to-ruff-format/SKILL.md` |
| `/migration-patterns:flake8-to-ruff` | `migration-patterns-plugin/skills/flake8-to-ruff/SKILL.md` |
| `/migration-patterns:eslint-to-biome` | `migration-patterns-plugin/skills/eslint-to-biome/SKILL.md` |

## See Also

- `/configure:claude-plugins` — Configure plugins, permissions, and marketplace enrollment
- `/configure:web-session` — SessionStart hook for infrastructure tools
- `/health:check` — Claude Code configuration health check
- `scripts/check-driver-freshness.sh` — Detect when this driver is out of sync with its dependencies
