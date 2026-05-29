---
name: github-workflow-auto-fix
description: "Set up automated CI fixing with Claude Code. Use when adding a workflow that analyzes failures, applies fixes, and files issues; pass --reusable for a multi-repo workflow_call template."
allowed-tools: Bash(gh run *), Bash(gh pr *), Bash(gh issue *), Bash(git status *), Bash(git diff *), Bash(git log *), Read, Write, Edit, Grep, Glob, TodoWrite
args: "[--setup] [--reusable] [--caller] [--workflows <names>] [--dry-run]"
argument-hint: --setup for single-repo inline, --reusable for a workflow_call template
disable-model-invocation: true
created: 2026-02-18
modified: 2026-05-29
reviewed: 2026-05-29
---

# GitHub Workflow Auto-Fix

Automated CI failure analysis and remediation using Claude Code Action.

Two shapes, selected by flag:

| Shape | Flag | Output | Use for |
|-------|------|--------|---------|
| **Single-repo inline** (default) | `--setup` | One self-contained `github-workflow-auto-fix.yml` | A single repo that owns its auto-fix logic |
| **Reusable `workflow_call`** | `--reusable` (+ `--caller`) | A `reusable-ci-autofix.yml` definition plus a thin `auto-fix.yml` caller | Multiple repos invoking one shared template |

## When to Use This Skill

| Use this skill when... | Use something else when... |
|------------------------|---------------------------|
| Setting up auto-fix for a single repo (default) | Fixing a single PR's checks (`/git:fix-pr`) |
| Setting up a reusable template multiple repos invoke (`--reusable`) | Inspecting workflow runs manually (`/workflow:inspect`) |
| Customizing which workflows trigger auto-fix | Writing new workflows from scratch (`/workflow:dev`) |

## Context

- Inline workflow exists: !`find .github/workflows -maxdepth 1 -name 'github-workflow-auto-fix.yml'`
- Reusable workflow exists: !`find .github/workflows -maxdepth 1 -name 'reusable-ci-autofix.yml' -type f`
- Caller workflow exists: !`find .github/workflows -maxdepth 1 -name 'auto-fix.yml' -type f`
- Current workflows: !`find .github/workflows -maxdepth 1 -name '*.yml' -type f`
- Claude secrets configured: !`gh secret list`

## Parameters

Parse from `$ARGUMENTS`:

- `--setup`: Create or update the single-repo inline workflow in `.github/workflows/github-workflow-auto-fix.yml`
- `--reusable`: Create or update the reusable `workflow_call` definition in `.github/workflows/reusable-ci-autofix.yml` (see Step 5)
- `--caller`: Create the thin caller workflow in `.github/workflows/auto-fix.yml` that invokes the reusable definition (see Step 5)
- `--workflows <names>`: Comma-separated workflow names to monitor (default: auto-detect CI workflows)
- `--dry-run`: Show what would be created without writing files

Default (no `--reusable`/`--caller`) generates the single-repo inline workflow described in Steps 1–4. `--reusable`/`--caller` switch to the reusable variant in Step 5.

## Execution

Execute this workflow setup process:

### Step 1: Assess current state

1. Check if `.github/workflows/github-workflow-auto-fix.yml` already exists
2. List all current workflow files and their `name:` fields
3. Check if `CLAUDE_CODE_OAUTH_TOKEN` secret is configured

### Step 2: Select workflows to monitor

If `--workflows` provided, use those. Otherwise, auto-detect suitable workflows:

**Good candidates for auto-fix monitoring:**
- CI/test workflows (lint, test, build, type-check)
- Code quality checks (formatting, style)
- Config validation workflows

**Skip these (not suitable for auto-fix):**
- Release workflows (release-please, deploy)
- Claude-powered workflows (avoid recursive triggers)
- Scheduled audit workflows
- Reusable workflow definitions

### Step 3: Generate workflow file

If `--setup` or workflow is missing, create `.github/workflows/github-workflow-auto-fix.yml`.

The workflow's display name follows `<Domain>: <Action>` (`Auto-fix:` is the canonical domain for `workflow_run`-triggered remediation; quote the value because YAML treats `:` as a key separator). The strings under `workflows:` must match the **display names** of the target workflows exactly — update both sides whenever a target's `name:` changes. See `.claude/rules/workflow-naming.md`.

```yaml
name: "Auto-fix: CI failures"

on:
  workflow_run:
    workflows:
      # List monitored workflows by display name (must match their `name:` exactly)
      - "Test: Suite"
      - "Plugin: Lint skills"
    types: [completed]

concurrency:
  group: auto-fix-${{ github.event.workflow_run.head_branch }}
  cancel-in-progress: false

permissions:
  contents: write
  pull-requests: write
  issues: write
  actions: read
  id-token: write

jobs:
  auto-fix:
    if: >-
      github.event.workflow_run.conclusion == 'failure' &&
      github.event.workflow_run.actor.type != 'Bot' &&
      github.event.workflow_run.head_branch != 'main' &&
      github.event.workflow_run.head_branch != 'master'
    runs-on: ubuntu-latest
    steps:
      - name: Checkout failed branch
        uses: actions/checkout@v4
        with:
          ref: ${{ github.event.workflow_run.head_branch }}
          fetch-depth: 0

      - name: Gather failure context
        id: context
        env:
          GH_TOKEN: ${{ secrets.GITHUB_TOKEN }}
        run: |
          RUN_ID="${{ github.event.workflow_run.id }}"
          gh run view "$RUN_ID" --log-failed 2>&1 | tail -500 > .auto-fix-failed-logs.txt
          gh run view "$RUN_ID" --json conclusion,status,name,headBranch,headSha,jobs > .auto-fix-run-summary.json
          PR_NUMBER=$(gh pr list --head "${{ github.event.workflow_run.head_branch }}" --json number --jq '.[0].number' 2>/dev/null || echo "")
          echo "pr_number=$PR_NUMBER" >> "$GITHUB_OUTPUT"
          echo "run_id=$RUN_ID" >> "$GITHUB_OUTPUT"
          RECENT_FIX=$(git log --oneline -5 --format='%s' | grep -c 'fix:.*resolve CI failure' || true)
          echo "recent_fix_count=$RECENT_FIX" >> "$GITHUB_OUTPUT"

      - name: Skip if already attempted
        if: steps.context.outputs.recent_fix_count != '0'
        run: echo "::notice::Skipping - recent auto-fix commit exists"

      - name: Analyze and fix with Claude
        if: steps.context.outputs.recent_fix_count == '0'
        uses: anthropics/claude-code-action@v1
        with:
          claude_code_oauth_token: ${{ secrets.CLAUDE_CODE_OAUTH_TOKEN }}
          direct_prompt: |
            <analysis-and-fix-prompt>
          additional_permissions: |
            Read
            Write
            Edit
            Grep
            Glob
            Bash(git *)
            Bash(gh *)
```

### Step 4: Validate and report

1. Verify the workflow YAML is valid
2. List the monitored workflows
3. Check that required secrets exist
4. Report any missing prerequisites

### Step 5: Reusable variant (`--reusable` / `--caller`)

When `--reusable` or `--caller` is passed, generate the `workflow_call` shape instead of the single-repo inline workflow. The full templates live in [REFERENCE.md](REFERENCE.md).

1. **`--reusable`** — create `.github/workflows/reusable-ci-autofix.yml` from [REFERENCE.md](REFERENCE.md) § Reusable Workflow. Customize:
   - `auto_fixable_criteria` / `not_auto_fixable_criteria` defaults to match the project's tech stack
   - `verification_commands` default to match the project's linter/formatter commands
   - `max_turns` (default: 50)
2. **`--caller`** — create `.github/workflows/auto-fix.yml` from [REFERENCE.md](REFERENCE.md) § Caller Workflow. Customize:
   - The monitored workflow `name:` strings in the `workflows:` list (display names — must match each target's `name:` exactly)
   - `auto_fixable_criteria` / `verification_commands` overrides for the project's tools
3. **Display-name convention** — the caller's `name:` follows `<Domain>: <Action>` (`Auto-fix: CI failures` is canonical; the reusable definition itself uses `Reusable: CI auto-fix`). Quote values containing colons. See `.claude/rules/workflow-naming.md`.
4. Validate both YAML files, list the monitored workflows, and confirm `CLAUDE_CODE_OAUTH_TOKEN` or `ANTHROPIC_API_KEY` exists.

The reusable variant adds dedup (max 2 open auto-fix PRs), `workflow_dispatch` with a `pr_number` input, and fan-out — see the Architecture and Safety Guards below, and REFERENCE.md for the rationale.

## Architecture

Single-repo inline (default):

```
workflow_run (failure)
        |
        v
  Gather logs & context
        |
        v
  Claude analyzes failure
        |
    +---+---+
    |       |
    v       v
  Fixable  Complex/External
    |       |
    v       v
  Fix &    Open issue
  push     with analysis
    |       |
    v       v
  Comment  Comment on PR
  on PR    linking issue
```

The reusable variant wraps the same analyze→fix/issue core in a `workflow_call` definition fronted by a thin caller (`workflow_run` + `workflow_dispatch` with fan-out and a dedup gate). See [REFERENCE.md](REFERENCE.md) § Reusable Workflow and § Cross-Repository Usage for the full templates.

## Safety Guards

| Guard | Variant | Purpose |
|-------|---------|---------|
| `actor.type != 'Bot'` | both | Prevent bot-triggered loops |
| `head_branch != 'main'` | both | Never auto-fix main branch directly |
| Recent fix check / `!startsWith(commit, 'fix(auto):')` | both | Skip if auto-fix already attempted; prevent recursive loops |
| Concurrency group per branch | both | One auto-fix per branch at a time |
| `max-turns` limit | both | Limit Claude's iteration count (inline 30, reusable 50 default) |
| Max 2 open auto-fix PRs | reusable | Prevent PR flooding across repos |
| `timeout-minutes: 30` | reusable | Prevent runaway jobs |

## Prerequisites

| Requirement | How to set up |
|-------------|---------------|
| `CLAUDE_CODE_OAUTH_TOKEN` | Repository secret with Claude Code OAuth token |
| `contents: write` permission | Included in workflow permissions |
| `pull-requests: write` permission | Included in workflow permissions |
| `issues: write` permission | For creating issues on complex failures |

## Agentic Optimizations

| Context | Command |
|---------|---------|
| Check recent failures | `gh run list --status failure --json name,headBranch,conclusion -L 10` |
| Get failed logs | `gh run view <id> --log-failed \| tail -500` |
| Run summary | `gh run view <id> --json conclusion,status,jobs` |
| Find associated PR | `gh pr list --head <branch> --json number --jq '.[0].number'` |
| List workflow names | `grep -h '^name:' .github/workflows/*.yml` |
