---
model: sonnet
created: 2026-01-23
modified: 2026-02-10
reviewed: 2026-01-30
description: Configure .claude/settings.json and GitHub Actions workflows to use the laurigates/claude-plugins marketplace
allowed-tools: Glob, Grep, Read, Write, Edit, Bash(mkdir *), Bash(test *), Bash(ls *), Bash(git remote *), AskUserQuestion, TodoWrite
argument-hint: "[--check-only] [--fix] [--plugins <plugin1,plugin2,...>]"
name: configure-claude-plugins
---

# /configure:claude-plugins

Configure a project to use the `laurigates/claude-plugins` Claude Code plugin marketplace. Sets up `.claude/settings.json` permissions and GitHub Actions workflows (`claude.yml`, `claude-code-review.yml`) with the marketplace pre-configured.

## When to Use This Skill

| Use this skill when... | Use another approach when... |
|------------------------|------------------------------|
| Onboarding a new project to use Claude Code plugins | Configuring Claude Code settings unrelated to plugins |
| Setting up `claude.yml` and `claude-code-review.yml` workflows | Creating general GitHub Actions workflows (`/configure:workflows`) |
| Adding the `laurigates/claude-plugins` marketplace to a repo | Installing individual plugins manually |
| Merging plugin permissions into existing `.claude/settings.json` | Debugging Claude Code action failures (check GitHub Actions logs) |
| Selecting recommended plugins based on project type | Developing new plugins (see CLAUDE.md plugin lifecycle) |

## Context

- Settings file exists: !`find . -maxdepth 1 -name \'.claude/settings.json\' 2>/dev/null`
- Workflows: !`find .github/workflows -maxdepth 1 -name 'claude*.yml' 2>/dev/null`
- Git remote: !`git remote get-url origin 2>/dev/null`
- Project type indicators: !`find . -maxdepth 1 \( -name 'package.json' -o -name 'pyproject.toml' -o -name 'Cargo.toml' -o -name 'Dockerfile' \) 2>/dev/null`
- Existing workflows dir: !`find . -maxdepth 1 -type d -name \'.github/workflows\' 2>/dev/null`

## Parameters

Parse from command arguments:

| Parameter | Description |
|-----------|-------------|
| `--check-only` | Report current configuration status without changes |
| `--fix` | Apply configuration automatically |
| `--plugins` | Comma-separated list of plugins to install (default: all recommended) |

## Execution

Execute this Claude plugins configuration workflow:

### Step 1: Detect current state

1. Check for existing `.claude/settings.json`
2. Check for existing `.github/workflows/claude.yml`
3. Check for existing `.github/workflows/claude-code-review.yml`
4. Detect project type (language, framework) from file indicators

### Step 2: Configure .claude/settings.json

Create or merge into `.claude/settings.json` the following permissions structure:

```json
{
  "permissions": {
    "allow": [
      "Bash(git status *)",
      "Bash(git diff *)",
      "Bash(git log *)",
      "Bash(git branch *)",
      "Bash(git add *)",
      "Bash(git commit *)",
      "Bash(git push *)",
      "Bash(git remote *)",
      "Bash(git checkout *)",
      "Bash(git fetch *)",
      "Bash(gh pr *)",
      "Bash(gh run *)",
      "Bash(gh issue *)",
      "Bash(pre-commit *)",
      "Bash(gitleaks *)",
      "mcp__context7",
      "mcp__sequential-thinking"
    ]
  }
}
```

If `.claude/settings.json` already exists, MERGE the `permissions.allow` array without duplicating entries. Preserve any existing `hooks`, `env`, or other fields.

### Step 3: Configure .github/workflows/claude.yml

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

### Step 4: Configure .github/workflows/claude-code-review.yml

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

### Step 5: Select plugins

If `--plugins` is not specified, select recommended plugins based on detected project type:

| Project Indicator | Recommended Plugins |
|-------------------|---------------------|
| `package.json` | `git-plugin`, `typescript-plugin`, `testing-plugin`, `code-quality-plugin` |
| `pyproject.toml` / `setup.py` | `git-plugin`, `python-plugin`, `testing-plugin`, `code-quality-plugin` |
| `Cargo.toml` | `git-plugin`, `rust-plugin`, `testing-plugin`, `code-quality-plugin` |
| `Dockerfile` | Above + `container-plugin` |
| `.github/workflows/` | Above + `github-actions-plugin` |
| Default (any) | `git-plugin`, `code-quality-plugin`, `testing-plugin`, `tools-plugin` |

### Step 6: Report results

Print a status report:

```
Claude Plugins Configuration Report
=====================================
Repository: <repo-name>

.claude/settings.json:
  Status:          <CREATED|UPDATED|EXISTS>
  Permissions:     <N> allowed patterns configured

.github/workflows/claude.yml:
  Status:          <CREATED|UPDATED|EXISTS>
  Marketplace:     laurigates/claude-plugins
  Plugins:         <list>

.github/workflows/claude-code-review.yml:
  Status:          <CREATED|UPDATED|EXISTS>
  Trigger:         PR opened/synchronize/reopened
  Plugins:         <list>

Next Steps:
  1. Add CLAUDE_CODE_OAUTH_TOKEN to repository secrets
     Settings > Secrets and variables > Actions > New repository secret
  2. Commit and push the new workflow files
  3. Test by mentioning @claude in a PR comment
```

## Agentic Optimizations

| Context | Command |
|---------|---------|
| Quick status check | `/configure:claude-plugins --check-only` |
| Auto-configure all | `/configure:claude-plugins --fix` |
| Specific plugins only | `/configure:claude-plugins --fix --plugins git-plugin,testing-plugin` |
| Verify settings exist | `test -f .claude/settings.json && echo "EXISTS"` |
| List Claude workflows | `find .github/workflows -name 'claude*.yml' 2>/dev/null` |

## Flags

| Flag | Description |
|------|-------------|
| `--check-only` | Report current status without making changes |
| `--fix` | Apply all configuration automatically |
| `--plugins` | Override automatic plugin selection |

## Important Notes

- The `CLAUDE_CODE_OAUTH_TOKEN` secret must be added manually to the repository
- If using AWS Bedrock or Google Vertex AI, adjust the authentication section accordingly
- The plugin marketplace URL uses HTTPS Git format: `https://github.com/laurigates/claude-plugins.git`
- Plugins are referenced as `<plugin-name>@laurigates-claude-plugins` (marketplace name from marketplace.json)

## See Also

- `/configure:workflows` - General GitHub Actions workflow configuration
- `/configure:all` - Run all compliance checks
- `claude-security-settings` skill - Claude Code security settings
