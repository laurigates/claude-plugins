---
model: sonnet
name: github-workflow-auto-fix
description: |
  Set up automated CI failure detection and fixing using Claude Code. Use when
  you want to create a GitHub Actions workflow that automatically analyzes workflow
  failures, applies fixes for common issues, and opens issues for complex problems.
allowed-tools: Bash(gh run *), Bash(gh pr *), Bash(gh issue *), Bash(git status *), Bash(git diff *), Bash(git log *), Read, Write, Edit, Grep, Glob, TodoWrite
args: "[--setup] [--workflows <names>] [--dry-run]"
argument-hint: --setup to create workflow, or --dry-run to preview
created: 2026-02-18
modified: 2026-02-19
reviewed: 2026-02-18
---

# GitHub Workflow Auto-Fix

Automated CI failure analysis and remediation using Claude Code Action.

## When to Use This Skill

| Use this skill when... | Use something else when... |
|------------------------|---------------------------|
| Setting up auto-fix workflow for a repo | Fixing a single PR's checks (`/git:fix-pr`) |
| Customizing which workflows trigger auto-fix | Inspecting workflow runs manually (`/workflow:inspect`) |
| Understanding the auto-fix pattern | Writing new workflows from scratch (`/workflow:dev`) |

## Context

- Workflow exists: !`find .github/workflows -maxdepth 1 -name 'github-workflow-auto-fix.yml' 2>/dev/null`
- Current workflows: !`find .github/workflows -maxdepth 1 -name '*.yml' -type f 2>/dev/null`
- Claude secrets configured: !`gh secret list 2>/dev/null`

## Parameters

Parse from `$ARGUMENTS`:

- `--setup`: Create or update the auto-fix workflow in `.github/workflows/`
- `--workflows <names>`: Comma-separated workflow names to monitor (default: auto-detect CI workflows)
- `--dry-run`: Show what would be created without writing files

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

If `--setup` or workflow is missing, create `.github/workflows/github-workflow-auto-fix.yml`:

```yaml
name: Auto-fix Workflow Failures

on:
  workflow_run:
    workflows:
      # List monitored workflows here
      - "CI"
      - "Lint"
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

## Architecture

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

## Safety Guards

| Guard | Purpose |
|-------|---------|
| `actor.type != 'Bot'` | Prevent bot-triggered loops |
| `head_branch != 'main'` | Never auto-fix main branch directly |
| Recent fix check | Skip if auto-fix already attempted |
| Concurrency group | One auto-fix per branch at a time |
| `max-turns 30` | Limit Claude's iteration count |

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
