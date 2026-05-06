---
created: 2026-01-23
modified: 2026-05-06
reviewed: 2026-05-06
description: |
  Configure .claude/settings.json (permissions, marketplace enrollment, enabledPlugins)
  and GitHub Actions workflows to use the laurigates/claude-plugins marketplace.
  Use when onboarding a new project to Claude Code plugins, setting up claude.yml
  and claude-code-review.yml workflows, adding the laurigates/claude-plugins
  marketplace to a repo, pinning a project's plugin set deterministically against
  global drift, or merging plugin permissions into existing settings.
  Natural triggers: "set up claude plugins", "add claude marketplace", "install claude.yml workflow", "pin plugins for this repo".
allowed-tools: Glob, Grep, Read, Write, Edit, Bash(mkdir *), Bash(test *), Bash(ls *), Bash(git remote *), Bash(gh api *), Bash(jq *), AskUserQuestion, TodoWrite
args: "[--check-only] [--fix] [--exhaustive] [--plugins <plugin1,plugin2,...>]"
argument-hint: "[--check-only] [--fix] [--exhaustive] [--plugins <plugin1,plugin2,...>]"
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
| `--exhaustive` | Enumerate every marketplace plugin in `enabledPlugins` — recommended ones as `true`, the rest as `false`. Pins the project's plugin set against global toggles. |

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

#### Why `enabledPlugins` merge semantics matter

`enabledPlugins` is a **per-key merging map** across the settings hierarchy: a project entry overrides the matching global entry, but global entries the project does not mention still take effect. There is no `enabledPluginsExclusive` flag. So if a user has accidentally toggled an unwanted plugin globally (easy to do via the plugins UI), it leaks into every repo that does not explicitly set it to `false`.

| Mode | Project `enabledPlugins` contents | Behaviour vs global toggles |
|------|------------------------------------|------------------------------|
| Default (no flag) | Recommended plugins as `true` only | Lean. Vulnerable to global drift — any plugin the user toggled on globally is also active here. |
| `--exhaustive` | Every marketplace plugin enumerated as `true` or `false` | Deterministic. Project pin overrides every global toggle. Re-run when the marketplace adds plugins. |

Pick `--exhaustive` for repos that need a self-documenting, drift-resistant plugin set (infrastructure repos, repos shared with teammates / CI, repos sensitive to context tax from unrelated plugins). Use the default for personal scratch repos where global toggles are intentional.

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

#### Exhaustive enumeration (when `--exhaustive` is set)

Build the full `enabledPlugins` map by reading every plugin name from the two relevant marketplaces, then writing each one with the appropriate boolean. The recommended set from Step 2 becomes `true`; everything else becomes `false`.

1. **Read the laurigates marketplace** in priority order:
   - If a local clone is present (e.g. inside this repo or a sibling checkout), parse `.claude-plugin/marketplace.json`:
     ```bash
     jq -r '.plugins[].name' .claude-plugin/marketplace.json
     ```
   - Otherwise fetch over the GitHub API:
     ```bash
     gh api repos/laurigates/claude-plugins/contents/.claude-plugin/marketplace.json --jq '.content' | base64 -d | jq -r '.plugins[].name'
     ```
   - Suffix each name with `@claude-plugins` to match the existing stanza format.

2. **Add the official LSP plugins** (`@claude-plugins-official`). The currently shipped names are: `pyright`, `typescript-language-server`, `rust-analyzer`, `gopls`, `swift-language-server`, `clangd`. Mark the LSP that matches the detected stack as `true`, the rest as `false`. If none match (no detectable stack), leave them all `false`.

3. **Compose the map** with all entries, alphabetised within each marketplace block:

```json
{
  "enabledPlugins": {
    "accessibility-plugin@claude-plugins": false,
    "agent-patterns-plugin@claude-plugins": false,
    "agents-plugin@claude-plugins": false,
    "...": "...",
    "code-quality-plugin@claude-plugins": true,
    "configure-plugin@claude-plugins": true,
    "git-plugin@claude-plugins": true,
    "health-plugin@claude-plugins": true,
    "hooks-plugin@claude-plugins": true,
    "testing-plugin@claude-plugins": true,
    "typescript-plugin@claude-plugins": true,
    "...": "...",

    "clangd@claude-plugins-official": false,
    "gopls@claude-plugins-official": false,
    "pyright@claude-plugins-official": false,
    "rust-analyzer@claude-plugins-official": false,
    "swift-language-server@claude-plugins-official": false,
    "typescript-language-server@claude-plugins-official": true
  }
}
```

4. **Drop unknown global entries.** If the project's existing `enabledPlugins` (or a merged-in copy of the user's global file) contains plugin names that are not in either marketplace listing, surface them in the report and ask whether to keep them. They may belong to a third marketplace the user has enrolled.

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
  Mode:                <DEFAULT|EXHAUSTIVE>
  Permissions:         <N> allowed patterns configured
  Marketplace:         laurigates/claude-plugins (extraKnownMarketplaces)
  Plugins pinned:      <N> total (<E> enabled, <D> disabled)   # exhaustive only
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
  4. (exhaustive mode) Re-run when the marketplace adds new plugins so they
     get an explicit `false` rather than inheriting the global toggle
```

## Agentic Optimizations

| Context | Command |
|---------|---------|
| Quick status check | `/configure:claude-plugins --check-only` |
| Auto-configure all | `/configure:claude-plugins --fix` |
| Specific plugins only | `/configure:claude-plugins --fix --plugins git-plugin,testing-plugin` |
| Pin against global drift | `/configure:claude-plugins --fix --exhaustive` |
| List marketplace plugin names | `jq -r '.plugins[].name' .claude-plugin/marketplace.json` |
| Verify settings exist | `find .claude -maxdepth 1 -name 'settings.json'` |
| List Claude workflows | `find .github/workflows -name 'claude*.yml'` |

## Flags

| Flag | Description |
|------|-------------|
| `--check-only` | Report current status without making changes |
| `--fix` | Apply all configuration automatically |
| `--plugins` | Override automatic plugin selection |
| `--exhaustive` | Enumerate every marketplace plugin (recommended ones `true`, the rest `false`). Pins the project's plugin set deterministically against global toggles. |

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
