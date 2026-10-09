---
created: 2025-12-16
modified: 2026-10-09
reviewed: 2026-09-02
name: claude-code-github-workflows
description: "Claude Code GitHub Actions workflow patterns — PR reviews, issue triage, CI/CD integration. Use when creating or modifying workflows that integrate Claude Code."
user-invocable: false
allowed-tools: Bash, Read, Write, Edit, Grep, Glob, WebFetch, mcp__github
---

# Claude Code GitHub Workflows

## When to Use This Skill

| Use this skill when... | Use the linked sibling instead when... |
|---|---|
| Designing a new `anthropics/claude-code-action@v1` workflow (PR review, issue triage, CI auto-fix) | Configuring the auth method or hardening permissions — see github-actions-auth-security |
| Choosing trigger events (`issue_comment`, `pull_request`, `workflow_run`) and `if:` guards | Wiring MCP servers and `--allowedTools` patterns — see github-actions-mcp-config |
| Adding path filters, custom trigger phrases, or external-contributor flows | Debugging a failing workflow run — see github-actions-inspection |
| Authoring the `prompt:` block (review focus areas, triage labelling, auto-fix instructions) | Building a self-hosted reusable auto-fix workflow — see github-workflow-auto-fix `--reusable` |

Expert knowledge for designing GitHub Actions workflows that integrate Claude Code for automated code assistance, PR reviews, and issue triage.

## Core Expertise

**Workflow Design Patterns**
- Automated pull request reviews with inline comments
- Issue triage and automated responses
- CI failure auto-fix workflows
- Custom trigger configurations and event handling

**Trigger Configurations**
- Issue comment triggers (`@claude` mentions)
- Pull request events (opened, synchronize, ready_for_review)
- Workflow run triggers (CI failure handling)
- Path-filtered reviews for specific directories

## Display name convention

Every workflow's `name:` follows `<Domain>: <Action> [<target>]` (quoted, since YAML treats `:` as a key separator). Use the `Claude:` domain for Claude Code-driven workflows; use `Auto-fix:` for `workflow_run`-triggered remediation. See `.claude/rules/workflow-naming.md` for the canonical rule and active domains. The example snippets below dogfood the convention.

When a workflow's `on.workflow_run.workflows` lists another workflow's display name, the listed string must match the target workflow's `name:` exactly — update both sides in the same change.

## Essential Workflow Template

```yaml
name: "Claude: @mentions"

on:
  issue_comment:
    types: [created]
  pull_request_review_comment:
    types: [created]
  issues:
    types: [opened, assigned]

jobs:
  claude:
    if: |
      (github.event_name == 'issue_comment' && contains(github.event.comment.body, '@claude')) ||
      (github.event_name == 'issues' && contains(github.event.issue.body, '@claude'))
    runs-on: ubuntu-latest
    permissions:
      contents: write
      pull-requests: write
      issues: write
      id-token: write
      actions: read
    steps:
      - name: Checkout repository
        uses: actions/checkout@v5
        with:
          fetch-depth: 1

      - name: Run Claude Code
        uses: anthropics/claude-code-action@v1
        with:
          anthropic_api_key: ${{ secrets.ANTHROPIC_API_KEY }}
          claude_args: |
            --model opus
            --effort medium
```

## Automation Patterns

When you need a complete template beyond the essential one above, open [references/automation-patterns.md](references/automation-patterns.md): comprehensive PR review, CI failure auto-fix (`workflow_run`), issue triage and labeling, path-filtered review, custom trigger phrase, and external-contributor handling. Read the `pull_request_target` security caveat there before using the external-contributor template.

## claude-code-action v1 Gotchas

Hard-won facts that produce silently-broken workflows (each cost real
debugging in production; see laurigates/.github#17–#19):

### Outputs are fixed — counts need `--json-schema`

The action exposes **only** `execution_file`, `branch_name`, `github_token`,
`structured_output`, and `session_id`. Referencing anything else
(`steps.scan.outputs.total`) evaluates to empty with no error — and prompting
Claude to print `TOTAL: <n>` in a comment does **not** create a step output.
Any metric a workflow needs out of a Claude step goes through structured
output:

```yaml
- id: scan
  uses: anthropics/claude-code-action@v1
  with:
    claude_args: >-
      --json-schema '{"type":"object","properties":{"total_issues":{"type":"integer"}},"required":["total_issues"]}'
    prompt: |
      ...analysis instructions...
      Report the count in the structured output field total_issues.

# Read it back — the || '{}' guard is REQUIRED: job outputs evaluate even
# when the step was skipped, and fromJSON('') errors.
outputs:
  issues: ${{ fromJSON(steps.scan.outputs.structured_output || '{}').total_issues }}
```

The same guarded expression works in `if:` gates
(`fromJSON(... || '{}').critical > 0`) — an unguarded comparison against a
missing output silently never fires.

The same law covers comment markers: anything CI greps for in an agent's output
must be written by a workflow step, not requested from the model — see
[REFERENCE.md](REFERENCE.md) § A marker the model has to emit.

### Bots are blocked by default

`allowed_bots` defaults to empty — **no** bot may trigger the action, so
bot-authored PRs (Renovate, release-please, Dependabot) fail with "Workflow
initiated by non-human actor". Pass `allowed_bots: "renovate[bot]"` (or a
comma-separated list) on workflows where bot PRs are the point, e.g.
dependency audits triggered by lockfile changes. Re-running a failed run does
not help: the replay keeps the original bot `sender`.

The same refusal hits a PR that a workflow pushed to with `github.token`: the
next run's `actor` is `github-actions[bot]`, GitHub holds it for approval, and
the approved attempt still fails here because `actor` stays the bot. The action
strips a trailing `[bot]` before comparing, so `allowed_bots: "github-actions"`
admits it; so does pushing with a PAT or App token instead. To recognise and
count these refusals in a repo's failed runs, see
`github-actions-plugin:ai-review-max-turns` (Cause 5, bot-actor refusal).

### A changed workflow can't be tested from a branch

When a `workflow_dispatch` runs a workflow file whose content differs from the
default branch's copy, the action exits before the agent starts:

```
Workflow validation failed. The workflow file must exist and have identical content to the version on the repository's default branch.
```

The step still reports **success**. Every later step then runs against no
output, and an `if: failure()` notifier fires on whichever step trips over the
gap: two branch runs of a fixed workflow each opened a spurious "summary
failed" issue. `steps.<id>.outputs.execution_file` is empty on such a run, so
gate the steps that consume the agent's output on it, and verify a workflow
change after merge with `gh workflow run <file>.yml` on the default branch, not
from the feature branch:

```yaml
- name: Publish the summary
  if: steps.claude.outputs.execution_file != ''
```

### Denials are a count

The printed result carries `permission_denials_count`, not the denied calls.
The full transcript, denials included, is written to
`$RUNNER_TEMP/claude-execution-output.json`. Read it with a fallback to that
fixed path, because `execution_file` can be empty (the validation skip leaves
it unset), and upload it so a run's tool calls stay readable afterwards:

```yaml
- name: Upload the execution log
  if: always()
  uses: actions/upload-artifact@v7
  with:
    name: claude-execution-output
    path: ${{ steps.claude.outputs.execution_file || format('{0}/claude-execution-output.json', runner.temp) }}
    if-no-files-found: ignore

- name: List denied tool calls
  if: always()
  env:
    EXEC_FILE: ${{ steps.claude.outputs.execution_file || format('{0}/claude-execution-output.json', runner.temp) }}
  run: |
    [ -f "$EXEC_FILE" ] || { echo "no execution file"; exit 0; }
    jq -r '.[] | select(.type == "result") | .permission_denials[]?
      | "\(.tool_name) \(.tool_input | tostring | .[0:160])"' "$EXEC_FILE"
```

A run can finish green with several denials and no published output; that mode
is in [REFERENCE.md](REFERENCE.md) § The family (green but unpublished).

### Deprecated inputs (removed in a future version)

`direct_prompt`, `override_prompt`, `custom_instructions`, `max_turns`,
`model`, `fallback_model`, `allowed_tools`, `disallowed_tools`, `mcp_config`,
`claude_env`, `mode` are all deprecated. Use `prompt` plus `claude_args`
(`--model`, `--max-turns`, `--allowedTools`, `--disallowedTools`,
`--mcp-config`, `--system-prompt`) and `settings` (env). A deprecated input
may be silently ignored — a workflow using `direct_prompt` can run with no
prompt at all.

### Budget levers

`claude_args` supports `--max-turns` (turn count) and `--max-budget-usd`
(run-level spend cap); there is **no token-count budget**. Both fail the run
mid-flight when exhausted — they bound waste but don't prevent doomed runs on
oversized diffs; pre-gate on diff size for that. Turn-budget exhaustion is
recognizable by `error_max_turns` in the `execution_file` and by a *rotating*
set of failing AI jobs across re-runs of the same commit.

`--model` and `--effort` are the cost levers, not `--max-turns`. `--model`
takes an alias (`opus`, `sonnet`, `fable`, `best`) or a full id; aliases move
with each model generation, so record the alias you chose next to the effort.
`--effort low|medium|high|xhigh|max` overrides the harness default (`high`);
effort names do not map across model generations, so re-check the level when
the alias's target changes. `haiku` supports no `--effort` at all, so `opus
--effort low` is the cheap tier, not haiku. Every template — the Essential
Workflow Template and those in
[references/automation-patterns.md](references/automation-patterns.md) —
carries both, with effort picked by job shape, e.g.

```yaml
claude_args: |
  --model opus
  --effort medium
```

## Performance Optimization

### Checkout Optimization
```yaml
# Fast checkout for large repos
- uses: actions/checkout@v5
  with:
    fetch-depth: 1          # Shallow clone
    sparse-checkout: |      # Only needed paths
      .github
      src
      tests
```

### Conversation Limits
```yaml
# Control execution time and cost
claude_args: |
  --max-turns 10  # Limit back-and-forth exchanges
```

### Conditional Execution
```yaml
# Skip unnecessary runs
jobs:
  claude:
    if: |
      contains(github.event.comment.body, '@claude') &&
      !contains(github.event.comment.body, 'ignore')
```

## Repository Configuration

### CLAUDE.md Example

Create `CLAUDE.md` in repository root to define coding standards:

```markdown
# Repository Guidelines for Claude Code

## Code Standards
- Use TypeScript strict mode
- Follow Airbnb style guide
- Maintain 90%+ test coverage
- Document all public APIs

## Development Workflow
- Run tests before committing: `npm test`
- Format with Prettier: `npm run format`
- Lint with ESLint: `npm run lint`

## Commit Messages
Follow Conventional Commits:
- feat: New features
- fix: Bug fixes
- docs: Documentation changes
- refactor: Code refactoring

## Testing Requirements
- Unit tests for all functions
- Integration tests for APIs
- E2E tests for critical flows

## Security
- Never commit secrets
- Validate all user inputs
- Use parameterized queries
- Follow OWASP guidelines
```

## Quick Setup

1. **Install Claude GitHub App**: https://github.com/apps/claude
2. **Add API Key**: Repository Settings → Secrets → `ANTHROPIC_API_KEY`
3. **Create Workflow**: `.github/workflows/claude.yml` (use template above)
4. **Test**: Create issue and comment `@claude Hello!`
5. **(Optional)** Add `CLAUDE.md` in repo root for project standards

## Troubleshooting

### Workflow Not Triggering
- Check trigger conditions in `if:` clause
- Verify permissions (contents, pull-requests, issues)
- Check GitHub App installation

### Permission Denied
- Ensure proper permissions in workflow
- Check branch protection rules
- Verify repository access

For advanced configuration including MCP servers, tool permissions, and authentication methods, see the github-actions-mcp-config and github-actions-auth-security skills. For the secure-use baseline these templates follow (least-privilege permissions, script-injection indirection, `pull_request_target` hazards), see `.claude/rules/github-actions-security.md`.
