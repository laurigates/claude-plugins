---
model: haiku
description: Identify workflow waste patterns and suggest fixes - skipped runs, bot triggers, missing concurrency
args: "[repo]"
allowed-tools: Bash(gh api *), Bash(gh workflow *), Bash(gh repo *), Read, Grep, Glob, Edit, TodoWrite
argument-hint: Optional repo (owner/name format, defaults to current repo)
created: 2025-01-30
modified: 2025-01-30
reviewed: 2025-01-30
name: finops-waste
---

# /finops:waste

Identify GitHub Actions waste patterns and provide actionable fix suggestions. Analyzes skipped runs, bot triggers, missing concurrency groups, and missing path filters.

## Context

- Current repo: !`gh repo view --json nameWithOwner --jq '.nameWithOwner' 2>/dev/null`
- Workflow files: !`find .github/workflows -maxdepth 1 \( -name '*.yml' -o -name '*.yaml' \) 2>/dev/null`

## Parameters

| Parameter | Description | Default |
|-----------|-------------|---------|
| `repo` | Repository in owner/name format | Current repository |

## Execution

**1. Determine repository:**

```bash
REPO="${1:-$(gh repo view --json nameWithOwner --jq '.nameWithOwner')}"
echo "=== Waste Analysis: $REPO ==="
echo ""
```

**2. Skipped runs analysis:**

```bash
echo "=== Skipped Runs ==="
SKIPPED_DATA=$(gh api "/repos/$REPO/actions/runs?per_page=100" \
  --jq '{
    total: (.workflow_runs | length),
    skipped: [.workflow_runs[] | select(.conclusion == "skipped")] | length,
    by_workflow: ([.workflow_runs[] | select(.conclusion == "skipped")] |
                  group_by(.name) |
                  map({workflow: .[0].name, count: length}) |
                  sort_by(-.count))
  }')

echo "$SKIPPED_DATA" | jq -r '"Total runs: \(.total)\nSkipped: \(.skipped) (\(.skipped * 100 / .total | floor)%)"'
echo ""
echo "By workflow:"
echo "$SKIPPED_DATA" | jq -r '.by_workflow[] | "  \(.workflow): \(.count) skipped"'
```

**3. Bot-triggered runs:**

```bash
echo ""
echo "=== Bot-Triggered Runs ==="
gh api "/repos/$REPO/actions/runs?per_page=100" \
  --jq '{
    total: (.workflow_runs | length),
    bot_triggered: [.workflow_runs[] | select(.triggering_actor.type == "Bot")] | length,
    bots: ([.workflow_runs[] | select(.triggering_actor.type == "Bot")] |
           group_by(.triggering_actor.login) |
           map({bot: .[0].triggering_actor.login, count: length}) |
           sort_by(-.count))
  }' | jq -r '"Bot-triggered: \(.bot_triggered)/\(.total) runs\n\nBy bot:"'

gh api "/repos/$REPO/actions/runs?per_page=100" \
  --jq '[.workflow_runs[] | select(.triggering_actor.type == "Bot")] |
        group_by(.triggering_actor.login) |
        map({bot: .[0].triggering_actor.login, count: length}) |
        sort_by(-.count)[] |
        "  \(.bot): \(.count) runs"'
```

**4. Workflow file analysis:**

```bash
echo ""
echo "=== Workflow File Analysis ==="

# Check each workflow file
for f in .github/workflows/*.yml .github/workflows/*.yaml 2>/dev/null; do
  [ -f "$f" ] || continue
  name=$(basename "$f")
  issues=""

  # Check for concurrency
  if ! grep -q "concurrency:" "$f"; then
    issues="${issues}missing-concurrency "
  fi

  # Check for path filters (on push/pull_request without paths)
  if grep -qE "^\s*(push|pull_request):" "$f" && ! grep -q "paths:" "$f"; then
    issues="${issues}no-path-filter "
  fi

  # Check for bot filter
  if ! grep -q "github.event.sender.type" "$f" && ! grep -q "github.actor" "$f"; then
    issues="${issues}no-bot-filter "
  fi

  # Check for cancel-in-progress
  if grep -q "pull_request:" "$f" && ! grep -q "cancel-in-progress:" "$f"; then
    issues="${issues}no-cancel-in-progress "
  fi

  if [ -n "$issues" ]; then
    echo "  $name: $issues"
  else
    echo "  $name: OK"
  fi
done
```

**5. Duplicate/concurrent runs:**

```bash
echo ""
echo "=== Potential Duplicate Runs ==="
# Find runs on same commit that could have been deduplicated
gh api "/repos/$REPO/actions/runs?per_page=100" \
  --jq '.workflow_runs | group_by(.head_sha) |
        map(select(length > 1)) |
        map({
          sha: .[0].head_sha[0:7],
          runs: length,
          workflows: [.[].name] | unique
        }) |
        .[0:5][] |
        "  Commit \(.sha): \(.runs) runs (\(.workflows | join(", ")))"'
```

**6. High-frequency workflows without path filters:**

```bash
echo ""
echo "=== High-Frequency Workflows ==="
gh api "/repos/$REPO/actions/runs?per_page=100" \
  --jq '.workflow_runs | group_by(.name) |
        map(select(length > 30)) |
        map({workflow: .[0].name, count: length}) |
        sort_by(-.count)[] |
        "  \(.workflow): \(.count) runs in sample - review trigger conditions"'
```

## Fix Suggestions

After analysis, provide specific fixes based on findings:

### Fix: Missing Concurrency Group

```yaml
# Add to workflow file at top level or per-job
concurrency:
  group: ${{ github.workflow }}-${{ github.ref }}
  cancel-in-progress: true  # For PR workflows
```

### Fix: Bot Trigger Filter

```yaml
jobs:
  build:
    # Skip if triggered by a bot
    if: github.event.sender.type != 'Bot'
    runs-on: ubuntu-latest
    steps: ...
```

Or for specific bots:
```yaml
    if: github.actor != 'dependabot[bot]' && github.actor != 'renovate[bot]'
```

### Fix: Add Path Filters

```yaml
on:
  push:
    branches: [main]
    paths:
      - 'src/**'
      - 'package.json'
      - 'package-lock.json'
    paths-ignore:
      - '**.md'
      - 'docs/**'
      - '.github/**'
  pull_request:
    paths:
      - 'src/**'
      - 'package.json'
```

### Fix: Cancel Duplicate PR Runs

```yaml
concurrency:
  group: ${{ github.workflow }}-${{ github.head_ref || github.ref }}
  cancel-in-progress: true
```

## Output Format

```
=== Waste Analysis: org/repo ===

=== Skipped Runs ===
Total runs: 100
Skipped: 15 (15%)

By workflow:
  CI: 10 skipped
  CodeQL: 5 skipped

=== Bot-Triggered Runs ===
Bot-triggered: 25/100 runs

By bot:
  dependabot[bot]: 15 runs
  renovate[bot]: 10 runs

=== Workflow File Analysis ===
  ci.yml: missing-concurrency no-path-filter
  deploy.yml: OK
  codeql.yml: no-bot-filter

=== Potential Duplicate Runs ===
  Commit abc1234: 3 runs (CI, CodeQL, Security)

=== High-Frequency Workflows ===
  CI: 67 runs in sample - review trigger conditions
```

## Post-actions

1. **Offer to apply fixes**: For each issue found, offer to edit the workflow file directly
2. **Prioritize by impact**: Focus on high-frequency workflows first
3. **Test recommendations**: Suggest testing changes on a feature branch first
4. **Create tracking issue**: Optionally create a GitHub issue to track optimization work
