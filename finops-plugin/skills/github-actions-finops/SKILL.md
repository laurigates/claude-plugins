---
name: github-actions-finops
description: "GitHub Actions billing, workflow efficiency, and waste analysis at org or repo level. Use when investigating CI/CD costs, wasted runs, or optimizing triggers."
user-invocable: false
allowed-tools: Bash(bash *), Bash(gh api *), Bash(gh repo *), Bash(gh workflow *), Bash(gh run *), Read, Grep, Glob, TodoWrite
created: 2025-01-30
modified: 2026-06-10
reviewed: 2026-06-10
---

# GitHub Actions FinOps

Analyze GitHub Actions usage, costs, and efficiency across organizations and repositories.

## When to Use This Skill

| Use this skill when... | Use X instead when... |
|------------------------|----------------------|
| Analyzing CI/CD costs and billing | Debugging a specific failed workflow -- use gh-workflow-monitoring |
| Identifying wasted workflow runs | Setting up new workflows -- use github-actions-workflows |
| Investigating workflow trigger patterns | Managing cache keys -- use github-actions-cache-optimization |
| Comparing efficiency across repos | Monitoring a single run -- use gh-workflow-monitoring |

## Context

- Current repo URL: !`git remote get-url origin`
- Workflow files: !`find .github/workflows -maxdepth 1 -name '*.yml' -o -name '*.yaml'`
- Active workflows: !`gh workflow list --json id,name,state`

## Execution

Execute this GitHub Actions FinOps analysis:

### Step 1: Determine scope

Read the Context values above. Parse `$OWNER` and `$REPO` from the current repo URL (e.g., `https://github.com/OWNER/REPO.git`). Run `gh api repos/$OWNER/$REPO --jq '.owner.type'` to determine if the owner is an "Organization" or "User". If Organization, set `$GITHUB_ORG` to the repo owner for org-level billing queries.

If no repo context is available, ask the user for the target organization or repository.

### Step 2: Gather billing, run, and waste data

Run the deterministic data-gathering script. It fetches org-level Actions
billing, groups workflow runs and aggregates per-workflow durations, counts
the waste indicators (skipped / bot-triggered / high-frequency), compares them
against the red-flag thresholds, and emits a static fix suggestion per flagged
pattern:

```bash
bash "${CLAUDE_SKILL_DIR}/scripts/github-actions-finops.sh" --home-dir "$HOME" --project-dir "$(pwd)"
```

Pass `--repo $OWNER/$REPO` (and `--org $GITHUB_ORG`) when the script can't infer
the target from the current checkout. Parse `STATUS=` and `ISSUES:` from the
output — `STATUS=WARN` plus the `SEVERITY=WARN TYPE=...` rows are the flagged
waste patterns with their suggested fixes. `BILLING_AVAILABLE=false` means org
admin access was unavailable (not an error).

### Step 3: Analyze workflow files

Read each workflow file from `.github/workflows/` and check for:

1. Missing `concurrency:` groups
2. Missing `paths:` filters on push/PR triggers
3. Missing bot-trigger guards (`if: github.event.sender.type != 'Bot'`)

### Step 4: Report findings

Synthesize a summary from the script output (Step 2) and the workflow-file
findings (Step 3):

1. **Billing summary** (if `BILLING_AVAILABLE=true`): minutes used, paid minutes
2. **Workflow run counts**: from the `WORKFLOW_RUNS=` / `WORKFLOW_DURATION_SECONDS=` lines
3. **Waste indicators**: the `SEVERITY=WARN TYPE=...` rows (skipped ratio, bot triggers, high-frequency) plus the workflow-file gaps from Step 3 (missing concurrency / path filters / bot guards)
4. **Recommendations**: the script's per-pattern fix suggestions, plus the workflow-YAML fixes you identified by reading the files

## API Reference

| Endpoint | Purpose | Admin Required |
|----------|---------|----------------|
| `/orgs/{org}/settings/billing/actions` | Minutes usage | Yes |
| `/orgs/{org}/settings/billing/packages` | Package bandwidth | Yes |
| `/orgs/{org}/settings/billing/shared-storage` | Storage billing | Yes |
| `/orgs/{org}/actions/cache/usage` | Org cache stats | No |
| `/repos/{owner}/{repo}/actions/runs` | Workflow runs | No |
| `/repos/{owner}/{repo}/actions/workflows` | Workflow definitions | No |

## Agentic Optimizations

| Context | Command |
|---------|---------|
| Org billing | `gh api /orgs/$ORG/settings/billing/actions --jq '{included_minutes, total_minutes_used}'` |
| List repos | `gh repo list $ORG --json nameWithOwner --limit 100` |
| Workflow runs | `gh api "/repos/$O/$R/actions/runs?per_page=100" --jq '.workflow_runs' --jq 'length'` |
| Skipped count | `gh api "..." --jq '[.workflow_runs[] | select(.conclusion == "skipped")] | length'` |
| Bot triggers | `gh api "..." --jq '[.workflow_runs[] | select(.triggering_actor.type == "Bot")] | length'` |

## See Also

- **github-actions-cache-optimization** - Cache-specific analysis and cleanup
- **gh-workflow-monitoring** - Watching individual workflow runs
