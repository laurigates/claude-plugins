---
created: 2026-01-23
modified: 2026-10-05
compatibility: claude-code
reviewed: 2026-09-02
description: "Claude plugins marketplace setup: .claude/settings.json, GitHub Actions, plugin pinning. Use when onboarding to claude-plugins, setting up claude.yml, pinning plugins, or overriding global plugins."
allowed-tools: Glob, Grep, Read, Write, Edit, Bash(ls *), Bash(git remote *), Bash(gh api *), Bash(jq *), AskUserQuestion, TodoWrite
args: "[--check-only] [--fix] [--exhaustive] [--plugins <plugin1,plugin2,...>] [--workflows] [--no-workflows]"
argument-hint: "[--check-only] [--fix] [--exhaustive] [--plugins <plugin1,plugin2,...>] [--workflows] [--no-workflows]"
name: configure-claude-plugins
---

# /configure:claude-plugins

Configure a project to use the `laurigates/claude-plugins` Claude Code plugin marketplace. Sets up `.claude/settings.json` with permissions, marketplace enrollment, and `enabledPlugins`; and GitHub Actions workflows (`claude.yml`, `claude-code-review.yml`) with the marketplace pre-configured.

## When to Use This Skill

| Use this skill when... | Use another approach when... |
|------------------------|------------------------------|
| Onboarding a new project to use Claude Code plugins | Configuring Claude Code settings unrelated to plugins |
| Setting up `claude.yml` and `claude-code-review.yml` workflows | Creating general GitHub Actions workflows (`/configure:workflows`) |
| Adding the `laurigates/claude-plugins` marketplace to a repo | Installing individual plugins manually |
| Merging plugin permissions into existing `.claude/settings.json` | Debugging Claude Code action failures (check GitHub Actions logs) |
| Selecting recommended plugins based on project type | Developing new plugins (see CLAUDE.md plugin lifecycle) |

## Context

- Settings file exists: !`find . -maxdepth 3 -name 'settings.json' -path '*/.claude/*'`
- Workflows: !`find . -path '*/.github/workflows/*' -maxdepth 3 -name 'claude*.yml'`
- Git remotes: !`git remote -v`
- Project type indicators: !`find . -maxdepth 1 \( -name 'package.json' -o -name 'pyproject.toml' -o -name 'Cargo.toml' -o -name 'go.mod' -o -name 'Dockerfile' -o -name 'justfile' -o -name 'Justfile' \)`
- ESP/embedded indicators: !`find . -maxdepth 2 \( -name 'idf_component.yml' -o -name 'sdkconfig' -o -name 'CMakeLists.txt' \)`
- ESPHome indicators: !`find . -maxdepth 2 -name '*.yaml' -path '*/esphome/*'`

## Parameters

Parse from command arguments:

| Parameter | Description |
|-----------|-------------|
| `--check-only` | Report current configuration status without changes |
| `--fix` | Apply configuration automatically |
| `--plugins` | Comma-separated list of plugins to install (default: all recommended) |
| `--exhaustive` | Pin every marketplace plugin as explicit `true`/`false` (see Flags) |
| `--workflows` | Force-scaffold workflows without a git remote (see Flags) |
| `--no-workflows` | Skip workflow scaffolding (see Flags) |

## Execution

### Step 1: Detect current state and project stack

1. Check for existing `.claude/settings.json`
2. Check for existing `.github/workflows/claude.yml`
3. Check for existing `.github/workflows/claude-code-review.yml`
4. Detect project type (language, framework) from file indicators
5. Check for a git remote with `git remote -v`: `has_remote = true` when non-empty, else `false`. This gates workflow scaffolding in Steps 4 and 5 (no remote → no GitHub Actions → do not scaffold by default).

### Step 2: Select plugins

If `--plugins` is not specified, map each detected indicator (`package.json`, `pyproject.toml`, `Cargo.toml`, `Dockerfile`, `.github/workflows/`, ESP-IDF, ESPHome, CMake) to its recommended plugin set using the table in [references/plugin-selection.md](references/plugin-selection.md); with no indicator, use the default set (`git-plugin`, `code-quality-plugin`, `testing-plugin`, `tools-plugin`).

Always include: `configure-plugin`, `health-plugin`, `hooks-plugin`.

### Step 3: Configure .claude/settings.json

Create or merge into `.claude/settings.json` (permissions, marketplace enrollment so web sessions retain plugin access, `enabledPlugins`).

> **Suffix forms are not interchangeable.** `enabledPlugins` uses `<plugin>@claude-plugins` (extraKnownMarketplaces key); workflow `plugins:` uses `<plugin>@laurigates-claude-plugins` (marketplace `name` in marketplace.json). Wrong suffix → entry silently ignored / run rejected. Table: [references/settings-json.md](references/settings-json.md#suffix-forms).

Pick the mode: the default writes only the recommended plugins as `true` (lean, but globally-toggled plugins leak in); `--exhaustive` pins every marketplace plugin as `true`/`false` (drift-resistant). Rationale and mode table: [references/settings-json.md](references/settings-json.md).

1. **Permissions** — always include the common baseline (`Bash(git:*)`, `Bash(gh:*)`, `Bash(pre-commit:*)`, `Bash(gitleaks:*)`, `Bash(python3:*)`) plus the stack-specific entries for the detected stack. Use granular patterns only — do not add `Bash(bash *)` for CLI tools. Per-stack table: same file.
2. **Marketplace + `enabledPlugins`** — merge the full stanza from the same file (`extraKnownMarketplaces` key `claude-plugins`, selected plugins as `<plugin>@claude-plugins: true`).
3. **Exhaustive mode** (`--exhaustive` only) — enumerate both marketplaces, derive each boolean from repo context, preserve existing project values, and show the diff before writing. Signal table, baseline set, LSP list, diff format: [references/exhaustive-mode.md](references/exhaustive-mode.md).

If `.claude/settings.json` already exists, **MERGE** without duplicating entries. Preserve any existing `hooks`, `env`, or other fields.

### Step 4: Configure .github/workflows/claude.yml

**Gate this step on a git remote being present.** Decide whether to scaffold using this table:

| `has_remote` (from Step 1) | Flag | Behaviour |
|---|---|---|
| `true` | _(default)_ or `--workflows` | Scaffold `claude.yml` |
| `true` | `--no-workflows` | Skip; record `STATUS=SKIPPED (--no-workflows)` |
| `false` | _(default)_ | **Default-skip** — prompt the user via `AskUserQuestion`: *"No git remote detected. `claude.yml` cannot run without GitHub Actions. Scaffold anyway (will sit dormant until a remote is added), or skip?"* Default to skip on `--check-only` (no prompt). |
| `false` | `--workflows` | Force-scaffold anyway (e.g. the user plans to add a remote later) |
| `false` | `--no-workflows` | Skip without prompting |

When the decision is **skip**, do not write the file, and surface `STATUS=SKIPPED (no git remote)` in the Step 6 report so the omission is visible.

When the decision is **scaffold**, create `.github/workflows/claude.yml` using the marketplace; `plugins:` entries use the `@laurigates-claude-plugins` suffix (marketplace `name`, NOT the Step 3 key). Pin `--model` and `--effort` explicitly. The full template is in [references/workflow-templates.md](references/workflow-templates.md#claudeyml-step-4).

### Step 5: Configure .github/workflows/claude-code-review.yml

**Apply the same git-remote gate from Step 4.** Reuse the user's answer (or the `--workflows` / `--no-workflows` flag) — do not re-prompt. If Step 4 skipped, skip Step 5 as well and record `STATUS=SKIPPED (no git remote)`.

When the decision is **scaffold**, create `.github/workflows/claude-code-review.yml` for automatic PR reviews from the template in [references/workflow-templates.md](references/workflow-templates.md#claude-code-reviewyml-step-5).

### Step 6: Report results

Print the status report (settings, git remote, each workflow's status incl. `SKIPPED` reasons, next steps) from [references/report-template.md](references/report-template.md).

## Agentic Optimizations

| Context | Command |
|---------|---------|
| Quick status check | `/configure:claude-plugins --check-only` |
| Auto-configure all | `/configure:claude-plugins --fix` |
| Specific plugins only | `/configure:claude-plugins --fix --plugins git-plugin,testing-plugin` |
| Pin against global drift | `/configure:claude-plugins --fix --exhaustive` |
| Settings only (local-only repo) | `/configure:claude-plugins --fix --no-workflows` |
| Pre-stage workflows before remote exists | `/configure:claude-plugins --fix --workflows` |
| List marketplace plugin names | `jq -r '.plugins[].name' .claude-plugin/marketplace.json` |
| Verify settings exist | `find .claude -maxdepth 1 -name 'settings.json'` |
| List Claude workflows | `find .github/workflows -name 'claude*.yml'` |
| Check for git remote | `git remote -v` |

## Flags

| Flag | Description |
|------|-------------|
| `--check-only` | Report current status without making changes |
| `--fix` | Apply all configuration automatically |
| `--plugins` | Override automatic plugin selection |
| `--exhaustive` | Enumerate every marketplace plugin as an explicit `true`/`false` so the project fully overrides global toggles. Triggered by "pin plugins" / "override global plugins for this project". |
| `--workflows` | Force-scaffold the `claude.yml` / `claude-code-review.yml` workflows even when no git remote is detected. |
| `--no-workflows` | Skip workflow scaffolding even when a git remote is present. Useful for local-only or vendored projects. |

## Important Notes

- The `CLAUDE_CODE_OAUTH_TOKEN` secret must be added manually to the repository.
- Never mix the two suffix forms (Step 3). Full notes: [references/settings-json.md](references/settings-json.md#important-notes).

## See Also

- `/configure:repo` - Full end-to-end driver (runs this skill + web-session + health check)
- `/configure:web-session` - SessionStart hook for infrastructure tools
- `/configure:all` - Run all compliance checks
- `claude-security-settings` skill - Claude Code security settings
