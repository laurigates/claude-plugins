---
created: 2026-01-23
modified: 2026-04-19
reviewed: 2026-04-14
description: |
  Configure .claude/settings.json (permissions, marketplace enrollment, enabledPlugins)
  and GitHub Actions workflows to use the laurigates/claude-plugins marketplace.
  Use when onboarding a new project to Claude Code plugins, setting up claude.yml
  and claude-code-review.yml workflows, adding the laurigates/claude-plugins
  marketplace to a repo, or merging plugin permissions into existing settings.
  Natural triggers: "set up claude plugins", "add claude marketplace", "install claude.yml workflow".
allowed-tools: Glob, Grep, Read, Write, Edit, Bash(mkdir *), Bash(test *), Bash(ls *), Bash(git remote *), AskUserQuestion, TodoWrite
args: "[--check-only] [--fix] [--plugins <plugin1,plugin2,...>]"
argument-hint: "[--check-only] [--fix] [--plugins <plugin1,plugin2,...>]"
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
- Workflows: !`find .github/workflows -maxdepth 1 -name 'claude*.yml'`
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

## Execution

Execute this Claude plugins configuration workflow:

### Step 1: Detect current state and project stack

1. Check for existing `.claude/settings.json`
2. Check for existing `.github/workflows/claude.yml`
3. Check for existing `.github/workflows/claude-code-review.yml`
4. Detect project type (language, framework) from file indicators

### Step 2: Select plugins

If `--plugins` is not specified, select recommended plugins based on detected project type:

| Project Indicator | Recommended Plugins |
|-------------------|---------------------|
| `package.json` | `git-plugin`, `typescript-plugin`, `testing-plugin`, `code-quality-plugin` |
| `pyproject.toml` / `setup.py` | `git-plugin`, `python-plugin`, `testing-plugin`, `code-quality-plugin` |
| `Cargo.toml` | `git-plugin`, `rust-plugin`, `testing-plugin`, `code-quality-plugin` |
| `Dockerfile` | Above + `container-plugin` |
| `.github/workflows/` | Above + `github-actions-plugin` |
| `idf_component.yml` / `sdkconfig` | `git-plugin`, `code-quality-plugin`, `testing-plugin`, `container-plugin` |
| ESPHome yaml | `git-plugin`, `python-plugin`, `code-quality-plugin` |
| Default (any) | `git-plugin`, `code-quality-plugin`, `testing-plugin`, `tools-plugin` |

Always include: `configure-plugin`, `health-plugin`, `hooks-plugin`.

### Step 3: Configure .claude/settings.json

Create or merge into `.claude/settings.json`. The permissions baseline includes common entries plus stack-aware expansions. The stanza also enrolls the marketplace so web sessions retain plugin access.

#### Stack-aware `permissions.allow` baseline

Always include these common entries:

```json
"Bash(git:*)", "Bash(gh:*)", "Bash(pre-commit:*)", "Bash(gitleaks:*)", "Bash(python3:*)"
```

Add stack-specific entries based on detected project type:

| Stack | Additional allow entries |
|---|---|
| Python (uv + ruff + ty) | `"Bash(uv:*)"`, `"Bash(uvx:*)"`, `"Bash(ruff:*)"`, `"Bash(ty:*)"`, `"Bash(pytest:*)"` |
| Node / TypeScript | `"Bash(npm:*)"`, `"Bash(pnpm:*)"`, `"Bash(bun:*)"`, `"Bash(tsc:*)"`, `"Bash(eslint:*)"`, `"Bash(prettier:*)"`, `"Bash(vitest:*)"` |
| Go | `"Bash(go:*)"`, `"Bash(gofmt:*)"`, `"Bash(golangci-lint:*)"` |
| Rust | `"Bash(cargo:*)"`, `"Bash(rustc:*)"`, `"Bash(clippy:*)"`, `"Bash(rustfmt:*)"` |
| ESP-IDF / embedded | `"Bash(idf.py:*)"`, `"Bash(esptool:*)"`, `"Bash(clang-format:*)"`, `"Bash(cppcheck:*)"`, `"Bash(docker:*)"`, `"Bash(docker compose:*)"`, `"Bash(just:*)"`, `"Bash(make:*)"` |
| ESPHome | `"Bash(esphome:*)"`, `"Bash(uv:*)"`, `"Bash(uvx:*)"` |

Use granular patterns only — do not add `Bash(bash *)` for CLI tools.

#### Full settings.json stanza to merge

```json
{
  "permissions": {
    "allow": [
      "Bash(git:*)",
      "Bash(gh:*)",
      "Bash(pre-commit:*)",
      "Bash(gitleaks:*)",
      "Bash(python3:*)"
      // ... plus stack-specific entries from the table above
    ]
  },
  "extraKnownMarketplaces": {
    "claude-plugins": {
      "source": { "source": "github", "repo": "laurigates/claude-plugins" },
      "autoUpdate": true
    }
  },
  "enabledPlugins": {
    "<selected-plugin-1>@claude-plugins": true,
    "<selected-plugin-2>@claude-plugins": true
  }
}
```

Replace `<selected-plugin-N>` with the plugin names selected in Step 2.

If `.claude/settings.json` already exists, **MERGE** without duplicating entries. Preserve any existing `hooks`, `env`, or other fields.

### Step 4: Configure .github/workflows/claude.yml

Create `.github/workflows/claude.yml` with the Claude Code action configured to use the plugin marketplace:

```yaml
name: Claude Code

on:
  issue_comment:
    types: [created]
  pull_request_review_comment:
    types: [created]
  issues:
    types: [opened, assigned]

permissions:
  contents: write
  pull-requests: write
  issues: write
  id-token: write

jobs:
  claude:
    if: |
      (github.event_name == 'issue_comment' && contains(github.event.comment.body, '@claude')) ||
      (github.event_name == 'pull_request_review_comment' && contains(github.event.comment.body, '@claude')) ||
      (github.event_name == 'issues' && contains(github.event.issue.body, '@claude'))
    runs-on: ubuntu-latest
    steps:
      - name: Checkout repository
        uses: actions/checkout@v4
        with:
          fetch-depth: 0

      - name: Run Claude Code
        uses: anthropics/claude-code-action@v1
        with:
          claude_code_oauth_token: ${{ secrets.CLAUDE_CODE_OAUTH_TOKEN }}
          plugin_marketplaces: |
            https://github.com/laurigates/claude-plugins.git
          plugins: |
            PLUGINS_LIST
```

Replace `PLUGINS_LIST` with the selected plugins in the format `plugin-name@laurigates-claude-plugins`, one per line.

### Step 5: Configure .github/workflows/claude-code-review.yml

Create `.github/workflows/claude-code-review.yml` for automatic PR reviews:

```yaml
name: Claude Code Review

on:
  pull_request:
    types: [opened, synchronize, reopened]

permissions:
  contents: read
  pull-requests: write
  issues: write

jobs:
  review:
    runs-on: ubuntu-latest
    steps:
      - name: Checkout repository
        uses: actions/checkout@v4
        with:
          fetch-depth: 0

      - name: Claude Code Review
        uses: anthropics/claude-code-action@v1
        with:
          claude_code_oauth_token: ${{ secrets.CLAUDE_CODE_OAUTH_TOKEN }}
          prompt: |
            Review this pull request. Focus on:
            - Code quality and best practices
            - Potential bugs or security issues
            - Test coverage gaps
            - Documentation needs
          claude_args: "--max-turns 5"
          plugin_marketplaces: |
            https://github.com/laurigates/claude-plugins.git
          plugins: |
            code-quality-plugin@laurigates-claude-plugins
            testing-plugin@laurigates-claude-plugins
```

### Step 6: Report results

Print a status report:

```
Claude Plugins Configuration Report
=====================================
Repository: <repo-name>

.claude/settings.json:
  Status:              <CREATED|UPDATED|EXISTS>
  Permissions:         <N> allowed patterns configured
  Marketplace:         laurigates/claude-plugins (extraKnownMarketplaces)
  Enabled plugins:     <list>

.github/workflows/claude.yml:
  Status:              <CREATED|UPDATED|EXISTS>
  Marketplace:         laurigates/claude-plugins
  Plugins:             <list>

.github/workflows/claude-code-review.yml:
  Status:              <CREATED|UPDATED|EXISTS>
  Trigger:             PR opened/synchronize/reopened

Next Steps:
  1. Add CLAUDE_CODE_OAUTH_TOKEN to repository secrets
     Settings > Secrets and variables > Actions > New repository secret
  2. Commit and push the new/updated files
  3. Test by mentioning @claude in a PR comment
```

## Agentic Optimizations

| Context | Command |
|---------|---------|
| Quick status check | `/configure:claude-plugins --check-only` |
| Auto-configure all | `/configure:claude-plugins --fix` |
| Specific plugins only | `/configure:claude-plugins --fix --plugins git-plugin,testing-plugin` |
| Verify settings exist | `find .claude -maxdepth 1 -name 'settings.json'` |
| List Claude workflows | `find .github/workflows -name 'claude*.yml'` |

## Flags

| Flag | Description |
|------|-------------|
| `--check-only` | Report current status without making changes |
| `--fix` | Apply all configuration automatically |
| `--plugins` | Override automatic plugin selection |

## Important Notes

- The `CLAUDE_CODE_OAUTH_TOKEN` secret must be added manually to the repository
- `extraKnownMarketplaces` in `.claude/settings.json` is the key to surviving ephemeral web sessions — without it, the marketplace is only enrolled via CI
- `enabledPlugins` entries use `plugin-name@claude-plugins` format (marketplace key from the `extraKnownMarketplaces` stanza)
- Plugins are referenced in workflows as `<plugin-name>@laurigates-claude-plugins` (marketplace `name` from marketplace.json)

## See Also

- `/configure:repo` - Full end-to-end driver (runs this skill + web-session + health check)
- `/configure:web-session` - SessionStart hook for infrastructure tools
- `/configure:all` - Run all compliance checks
- `claude-security-settings` skill - Claude Code security settings
