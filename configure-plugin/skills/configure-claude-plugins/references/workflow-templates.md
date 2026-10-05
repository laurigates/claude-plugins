# Claude GitHub Actions Workflow Templates

Used by Step 4 (`claude.yml`) and Step 5 (`claude-code-review.yml`) of `/configure:claude-plugins` when the decision is **scaffold**.

## claude.yml (Step 4)

When the decision is **scaffold**, create `.github/workflows/claude.yml` with the Claude Code action configured to use the plugin marketplace. Workflow `plugins:` entries use the `@laurigates-claude-plugins` suffix — the marketplace `name` from `marketplace.json`, NOT the `extraKnownMarketplaces` key used in Step 3:

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
        uses: actions/checkout@v6
        with:
          fetch-depth: 0

      - name: Run Claude Code
        uses: anthropics/claude-code-action@v1
        with:
          claude_code_oauth_token: ${{ secrets.CLAUDE_CODE_OAUTH_TOKEN }}
          claude_args: "--model opus --effort high"
          plugin_marketplaces: |
            https://github.com/laurigates/claude-plugins.git
          plugins: |
            # suffix matches marketplace `name` in marketplace.json (NOT extraKnownMarketplaces key)
            PLUGINS_LIST
```

Replace `PLUGINS_LIST` with the selected plugins in the format `plugin-name@laurigates-claude-plugins`, one per line. The suffix is the marketplace `name` field from `laurigates/claude-plugins/.claude-plugin/marketplace.json` — distinct from the `@claude-plugins` suffix used in `.claude/settings.json` (Step 3).

Pin `--model` (an alias — `opus` is the current Opus, `fable` the current Fable) and `--effort` explicitly: the harness default effort is `high` for every model, and effort level names do not map across model generations, so an explicit pin is what makes the cost visible.

## claude-code-review.yml (Step 5)

When the decision is **scaffold**, create `.github/workflows/claude-code-review.yml` for automatic PR reviews:

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
        uses: actions/checkout@v6
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
          claude_args: "--model opus --effort medium --max-turns 5"
          plugin_marketplaces: |
            https://github.com/laurigates/claude-plugins.git
          plugins: |
            # suffix matches marketplace `name` in marketplace.json (NOT extraKnownMarketplaces key)
            code-quality-plugin@laurigates-claude-plugins
            testing-plugin@laurigates-claude-plugins
```
