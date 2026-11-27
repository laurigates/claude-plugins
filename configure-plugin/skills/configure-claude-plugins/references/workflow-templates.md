# Claude GitHub Actions Workflow Templates

Used by Step 4 (`claude.yml`) and Step 5 (`claude-code-review.yml`) of `/configure:claude-plugins` when the decision is **scaffold**.

## Choose the layout: reusable caller or inline

Some owners publish reusable Claude workflows in their `.github` repository, so their repos carry a short caller instead of the action wiring. Take `<owner>` from the git remote (`github.com[:/]<owner>/<repo>`) and list that repository's workflows with one call:

```bash
gh api repos/<owner>/.github/contents/.github/workflows --jq '.[].name'
```

| Probe result | `claude.yml` (Step 4) | `claude-code-review.yml` (Step 5) |
|---|---|---|
| Lists `reusable-claude.yml` | [Caller](#claudeyml-step-4) | — |
| Lists `reusable-claude-review.yml` | — | [Caller](#claude-code-reviewyml-step-5) |
| Lacks that workflow's file, returns 404, or the remote is not on GitHub | [Inline](#standalone-inline-template) | [Inline](#standalone-inline-template) |

Decide each workflow on its own row, and record the layout in the Step 6 report. A 404 also covers an owner with no `.github` repository and a private one the token cannot read.

## Reusable callers

Before writing a caller, read the reusable workflow's live inputs and `permissions:`; they change:

```bash
gh api repos/<owner>/.github/contents/.github/workflows/reusable-claude.yml --jq .content | base64 -d | sed -n 1,120p
gh api repos/<owner>/.github/contents/.github/workflows/reusable-claude-review.yml --jq .content | base64 -d | sed -n 1,140p
```

What a reusable workflow of this shape owns, so the caller does not repeat it: the `@claude` trigger filter and the human-sender check, the skip rules (bot and release-please authors), concurrency, the action version pin, timeouts, the turn budget and the default tool allow-list. The caller supplies triggers, `permissions:`, the plugin list and the secret. If the live file does not own one of these, keep it in the caller.

Give each caller job its own `permissions:` block granting at least what the called workflow's top-level `permissions:` declares. GitHub rejects a caller that grants less at parse time, and on a repo whose default workflow token is read-only a caller with no block fails with `startup_failure`. The templates below assume `contents: write` for `reusable-claude.yml`, `contents: read` for `reusable-claude-review.yml`, plus `pull-requests: write`, `issues: write`, `id-token: write` and `actions: read` for both; copy the live values instead where they differ.

Call the reusable workflows at `@main`, the owner's own branch; that is the one exception to pinning third-party actions to a SHA.

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

jobs:
  claude:
    uses: <owner>/.github/.github/workflows/reusable-claude.yml@main
    permissions:
      contents: write
      pull-requests: write
      issues: write
      id-token: write
      actions: read
    with:
      plugin_marketplaces: |
        https://github.com/laurigates/claude-plugins.git
      plugins: |
        PLUGINS_LIST
    secrets:
      CLAUDE_CODE_OAUTH_TOKEN: ${{ secrets.CLAUDE_CODE_OAUTH_TOKEN }}
```

Replace `<owner>` with the probed owner and `PLUGINS_LIST` with the selected plugins as `plugin-name@laurigates-claude-plugins`, one per line, indented to match. The suffix is the marketplace `name` in `laurigates/claude-plugins/.claude-plugin/marketplace.json`, the same value as the `extraKnownMarketplaces` key in `.claude/settings.json` (Step 3). Keep comments outside the `plugins: |` block: inside a block scalar a `#` line is content, and the action rejects it with `Invalid plugin name format`.

### claude-code-review.yml (Step 5)

```yaml
name: Claude Code Review

on:
  pull_request:
    types: [opened, synchronize, reopened]

jobs:
  review:
    uses: <owner>/.github/.github/workflows/reusable-claude-review.yml@main
    permissions:
      contents: read
      pull-requests: write
      issues: write
      id-token: write
      actions: read
    with:
      plugin_marketplaces: |
        https://github.com/laurigates/claude-plugins.git
      plugins: |
        code-quality-plugin@laurigates-claude-plugins
        testing-plugin@laurigates-claude-plugins
    secrets:
      CLAUDE_CODE_OAUTH_TOKEN: ${{ secrets.CLAUDE_CODE_OAUTH_TOKEN }}
```

A reusable review of this shape skips release-please and bot-authored PRs by default (inputs such as `skip_release_please`, `skip_bots`, `allowed_bots`), so the caller needs no `if:` on the actor; check the live inputs, and add the standalone template's `if:` to the caller job if the reusable has no such skip. Leave `--max-turns` to the reusable's default unless the live file sets it below 50.

## Standalone inline template

When the probe finds no reusable workflow, the repo carries the action wiring in the file. Resolve both action pins to full commit SHAs before writing them (`gh api repos/<owner>/<repo>/git/ref/tags/<tag>`; an annotated tag is dereferenced with `gh api repos/<owner>/<repo>/git/tags/<sha> --jq .object.sha`) and keep the version in a trailing comment. `claude-code-action` needs `id-token: write`; without it the job fails with `Could not fetch an OIDC token` before Claude runs. Keep `--model` and `--effort` explicit in `claude_args`: effort level names do not map across model generations, so the pin makes the cost visible. The review sets `--max-turns 50`: `--max-turns 5` died with `error_max_turns` at `num_turns 6` on nearly every PR.

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

The standalone review workflow keeps a job-level `if:` on the actor, because the action refuses a Bot actor not listed in `allowed_bots`:

```yaml
name: Claude Code Review (standalone)

on:
  pull_request:
    types: [opened, synchronize, reopened]

concurrency:
  group: claude-review-${{ github.event.pull_request.number }}
  cancel-in-progress: true

permissions:
  contents: read
  pull-requests: write
  issues: write
  id-token: write

jobs:
  review:
    if: github.event.pull_request.user.type != 'Bot'
    runs-on: ubuntu-latest
    steps:
      - name: Checkout repository
        uses: actions/checkout@<FULL_SHA> # <tag>
        with:
          fetch-depth: 1

      - name: Run Claude Code Review
        uses: anthropics/claude-code-action@<FULL_SHA> # <tag>
        with:
          claude_code_oauth_token: ${{ secrets.CLAUDE_CODE_OAUTH_TOKEN }}
          prompt: Review this pull request for correctness, security and test coverage.
          claude_args: "--model opus --effort medium --max-turns 50"
          plugin_marketplaces: |
            https://github.com/laurigates/claude-plugins.git
          plugins: |
            PLUGINS_LIST
```
