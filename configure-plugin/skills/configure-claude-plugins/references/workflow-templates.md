# Claude GitHub Actions Workflow Templates

Used by Step 4 (`claude.yml`) and Step 5 (`claude-code-review.yml`) of `/configure:claude-plugins` when the decision is **scaffold**.

## Prefer the org reusable workflows

A repo under `laurigates/` calls the reusable workflows in `laurigates/.github` rather than carrying its own copy of the action wiring (CI logic is not duplicated inline). Read the live inputs before writing the caller; they change:

```bash
gh api repos/laurigates/.github/contents/.github/workflows --jq '.[].name' | grep -i claude
gh api repos/laurigates/.github/contents/.github/workflows/reusable-claude.yml --jq .content | base64 -d | sed -n 1,120p
gh api repos/laurigates/.github/contents/.github/workflows/reusable-claude-review.yml --jq .content | base64 -d | sed -n 1,140p
```

What the reusable workflows own, so the caller does not repeat it: the `@claude` trigger filter and the human-sender check, the skip rules (bot and release-please authors, Claude-config-only PRs), concurrency, the action version pin, timeouts and the default tool allow-list. The caller supplies triggers, `permissions:`, the plugin list and the secret.

A caller's `permissions:` must grant at least what the called workflow's top-level `permissions:` declares, or GitHub rejects the run at parse time. At the time of writing that is `contents: write` for `reusable-claude.yml`, `contents: read` for `reusable-claude-review.yml`, plus `pull-requests: write`, `issues: write`, `id-token: write` and `actions: read` for both. Re-read them from the live files.

Call the reusable workflows at `@main`; that is the one exception to pinning third-party actions to a SHA.

### claude.yml (Step 4)

```yaml
name: Claude Code

on:
  issue_comment:
    types: [created]
  pull_request_review_comment:
    types: [created]
  pull_request_review:
    types: [submitted]
  issues:
    types: [opened, assigned]

permissions:
  contents: write
  pull-requests: write
  issues: write
  id-token: write
  actions: read

jobs:
  claude:
    uses: laurigates/.github/.github/workflows/reusable-claude.yml@main
    with:
      plugin_marketplaces: |
        https://github.com/laurigates/claude-plugins.git
      plugins: |
        PLUGINS_LIST
    secrets:
      CLAUDE_CODE_OAUTH_TOKEN: ${{ secrets.CLAUDE_CODE_OAUTH_TOKEN }}
```

Replace `PLUGINS_LIST` with the selected plugins as `plugin-name@laurigates-claude-plugins`, one per line, indented to match. The suffix is the marketplace `name` in `laurigates/claude-plugins/.claude-plugin/marketplace.json`, the same value as the `extraKnownMarketplaces` key in `.claude/settings.json` (Step 3). Keep comments outside the `plugins: |` block: inside a block scalar a `#` line is content, and the action rejects it with `Invalid plugin name format`.

### claude-code-review.yml (Step 5)

```yaml
name: Claude Code Review

on:
  pull_request:
    types: [opened, synchronize, reopened]

permissions:
  contents: read
  pull-requests: write
  issues: write
  id-token: write
  actions: read

jobs:
  review:
    uses: laurigates/.github/.github/workflows/reusable-claude-review.yml@main
    with:
      plugin_marketplaces: |
        https://github.com/laurigates/claude-plugins.git
      plugins: |
        code-quality-plugin@laurigates-claude-plugins
        testing-plugin@laurigates-claude-plugins
    secrets:
      CLAUDE_CODE_OAUTH_TOKEN: ${{ secrets.CLAUDE_CODE_OAUTH_TOKEN }}
```

The reusable review skips release-please and bot-authored PRs by default (`skip_release_please`, `skip_bots`, `allowed_bots`), so the caller needs no `if:` on the actor.

## Standalone inline template (repos outside `laurigates/`)

A repo that cannot call `laurigates/.github` (another owner, a private fork) needs the action wiring in the file. Resolve both action pins to full commit SHAs before writing them (`gh api repos/<owner>/<repo>/git/ref/tags/<tag>`; an annotated tag is dereferenced with `gh api repos/<owner>/<repo>/git/tags/<sha> --jq .object.sha`) and keep the version in a trailing comment. `claude-code-action` needs `id-token: write`; without it the job fails with `Could not fetch an OIDC token` before Claude runs. Keep `--model` and `--effort` explicit in `claude_args`: effort level names do not map across model generations, so the pin makes the cost visible.

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
        uses: actions/checkout@<FULL_SHA> # <tag>
        with:
          fetch-depth: 0

      - name: Run Claude Code
        uses: anthropics/claude-code-action@<FULL_SHA> # <tag>
        with:
          claude_code_oauth_token: ${{ secrets.CLAUDE_CODE_OAUTH_TOKEN }}
          claude_args: "--model opus --effort high"
          plugin_marketplaces: |
            https://github.com/laurigates/claude-plugins.git
          plugins: |
            PLUGINS_LIST
```

The review workflow is the same shape with `on: pull_request`, `permissions: contents: read`, a `prompt:`, `claude_args: "--model opus --effort medium --max-turns 5"`, and a job-level `if: github.event.pull_request.user.type != 'Bot'` (the action refuses a Bot actor not listed in `allowed_bots`). Add a `concurrency:` group keyed on the PR number with `cancel-in-progress: true`.
