---
name: ci-autofix-reusable
description: |
  Generate a reusable GitHub Actions workflow for automated CI failure detection
  and fixing with Claude Code. Use when you want a workflow_call-based reusable
  workflow that multiple repos or caller workflows can invoke with custom inputs.
allowed-tools: Bash(gh run *), Bash(gh pr *), Bash(gh issue *), Bash(git status *), Bash(git diff *), Bash(git log *), Read, Write, Edit, Grep, Glob, TodoWrite
args: "[--setup] [--caller] [--workflows <names>] [--dry-run]"
argument-hint: --setup to create reusable workflow, --caller to create caller workflow
disable-model-invocation: true
created: 2026-03-07
modified: 2026-03-07
reviewed: 2026-03-07
---

# Reusable CI Auto-Fix Workflow

Generate a reusable GitHub Actions workflow for automated CI failure analysis and remediation.

## When to Use This Skill

| Use this skill when... | Use something else when... |
|------------------------|---------------------------|
| Setting up a reusable auto-fix workflow for multiple repos | Setting up auto-fix for a single repo (`/workflow:auto-fix`) |
| Creating a caller workflow that invokes the reusable template | Fixing a single PR's checks (`/git:fix-pr`) |
| Customizing auto-fix inputs for different project types | Inspecting workflow runs manually (`/workflow:inspect`) |

## Context

- Reusable workflow exists: !`find .github/workflows -maxdepth 1 -name 'reusable-ci-autofix.yml' -type f`
- Caller workflow exists: !`find .github/workflows -maxdepth 1 -name 'auto-fix.yml' -type f`
- Current workflows: !`find .github/workflows -maxdepth 1 -name '*.yml' -type f`
- Claude secrets configured: !`gh secret list`

## Parameters

Parse from `$ARGUMENTS`:

- `--setup`: Create or update the reusable workflow in `.github/workflows/reusable-ci-autofix.yml`
- `--caller`: Create the caller workflow in `.github/workflows/auto-fix.yml`
- `--workflows <names>`: Comma-separated workflow names to monitor (for caller; default: auto-detect CI workflows)
- `--dry-run`: Show what would be created without writing files

## Execution

Execute this workflow generation process:

### Step 1: Detect current state

1. Check if `.github/workflows/reusable-ci-autofix.yml` already exists
2. Check if `.github/workflows/auto-fix.yml` already exists
3. List all current workflow files and their `name:` fields
4. Check if `CLAUDE_CODE_OAUTH_TOKEN` or `ANTHROPIC_API_KEY` secret is configured

### Step 2: Select workflows to monitor (for caller)

If `--workflows` provided, use those. Otherwise, auto-detect:

**Good candidates:**
- CI/test workflows (lint, test, build, type-check)
- Code quality checks (formatting, style)

**Skip:**
- Release/deploy workflows
- Claude-powered workflows (avoid recursive triggers)
- Scheduled/audit workflows

### Step 3: Generate the reusable workflow

If `--setup` or reusable workflow is missing, create `.github/workflows/reusable-ci-autofix.yml` using the template from [REFERENCE.md](REFERENCE.md) § Reusable Workflow.

Key customization points:
1. Set the `auto_fixable_criteria` and `not_auto_fixable_criteria` defaults to match the project's tech stack
2. Set the `verification_commands` default to match the project's linter/formatter commands
3. Adjust `max_turns` if needed (default: 50)

### Step 4: Generate the caller workflow

If `--caller` or caller workflow is missing, create `.github/workflows/auto-fix.yml` using the template from [REFERENCE.md](REFERENCE.md) § Caller Workflow.

Key customization points:
1. Set the monitored workflow names in the `workflows:` list
2. Configure `auto_fixable_criteria` override if the project has specific fixable patterns
3. Configure `verification_commands` for the project's tools

### Step 5: Validate and report

1. Verify both workflow YAML files are valid
2. List the monitored workflows
3. Check that required secrets exist (`CLAUDE_CODE_OAUTH_TOKEN` or `ANTHROPIC_API_KEY`)
4. Report any missing prerequisites

## Architecture

```
Caller Workflow                    Reusable Workflow
(.github/workflows/auto-fix.yml)  (.github/workflows/reusable-ci-autofix.yml)

  workflow_run (failure)
  workflow_dispatch (pr_number)
        |
        v
  fan-out (if "all")
        |
        v
  jobs.auto-fix ──calls──────────> on: workflow_call
                                       |
                                       v
                                   Resolve PR branch
                                       |
                                       v
                                   Checkout + Gather context
                                       |
                                       v
                                   Dedup check (max 2 open auto-fix PRs)
                                       |
                                       v
                                   Claude Code Action
                                       |
                                   +---+---+
                                   |       |
                                   v       v
                                 Fixable  Complex
                                   |       |
                                   v       v
                                 Fix PR   Open issue
```

## Safety Guards

| Guard | Purpose |
|-------|---------|
| `!startsWith(commit, 'fix(auto):')` | Prevent recursive auto-fix loops |
| `head_branch != 'main'` (caller) | Never auto-fix protected branches |
| Max 2 open auto-fix PRs | Prevent PR flooding |
| Concurrency group per branch | One auto-fix at a time per branch |
| `max-turns` limit | Cap Claude's iteration count |
| `timeout-minutes: 30` | Prevent runaway jobs |

## Prerequisites

| Requirement | How to set up |
|-------------|---------------|
| `CLAUDE_CODE_OAUTH_TOKEN` or `ANTHROPIC_API_KEY` | Repository or org secret |
| `contents: write` | Included in workflow permissions |
| `pull-requests: write` | Included in workflow permissions |
| `issues: write` | For creating issues on complex failures |

## Agentic Optimizations

| Context | Command |
|---------|---------|
| Check workflow exists | `test -f .github/workflows/reusable-ci-autofix.yml` |
| List CI workflows | `grep -h '^name:' .github/workflows/*.yml` |
| Check secrets | `gh secret list` |
| Recent failures | `gh run list --status failure --json name,headBranch -L 10` |
| Validate YAML | `python3 -c "import yaml; yaml.safe_load(open('.github/workflows/reusable-ci-autofix.yml'))"` |
