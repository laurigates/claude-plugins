---
model: haiku
description: Quick FinOps summary - org billing and current repo workflow/cache stats
args: "[org]"
allowed-tools: Bash(gh api *), Bash(gh repo *), Bash(gh workflow *), Read, TodoWrite
argument-hint: Optional org name (defaults to current repo's org)
created: 2025-01-30
modified: 2025-01-30
reviewed: 2026-02-08
name: finops-overview
---

# /finops:overview

Display a quick FinOps summary including org-level billing (if admin) and current repository workflow/cache statistics.

## Context

- Current repo: !`gh repo view --json nameWithOwner --jq '.nameWithOwner' 2>/dev/null`
- Repo org/owner: !`gh repo view --json owner --jq '.owner.login' 2>/dev/null`

## Parameters

| Parameter | Description | Default |
|-----------|-------------|---------|
| `org` | GitHub organization name | Current repo's owner |

## Execution

**1. Determine organization:**

If `$1` provided, use it. Otherwise extract from current repo:
```bash
ORG="${1:-$(gh repo view --json owner --jq '.owner.login')}"
```

**2. Org-level billing (may fail if not admin):**

```bash
echo "=== Org Billing: $ORG ==="
gh api /orgs/$ORG/settings/billing/actions \
  --jq '"Minutes: \(.total_minutes_used)/\(.included_minutes) included, \(.total_paid_minutes_used) paid"'
```

**3. Org-level cache usage:**

```bash
echo ""
echo "=== Org Cache Usage ==="
gh api /orgs/$ORG/actions/cache/usage \
  --jq '"\(.total_active_caches_count) caches, \(.total_active_caches_size_in_bytes / 1024 / 1024 | floor)MB total"'
```

**4. Current repo stats (if in a repo):**

```bash
REPO=$(gh repo view --json nameWithOwner --jq '.nameWithOwner')

echo ""
echo "=== Repo: $REPO ==="

# Cache usage
echo "Cache:"
gh api "/repos/$REPO/actions/cache/usage" \
  --jq '"  \(.active_caches_count) caches, \(.active_caches_size_in_bytes / 1024 / 1024 | floor)MB"'

# Recent workflow runs (last 30 days)
echo ""
echo "Workflows (last 30 days):"
gh api "/repos/$REPO/actions/runs?per_page=100" \
  --jq '.workflow_runs | group_by(.name) |
        map({name: .[0].name, runs: length,
             success: ([.[] | select(.conclusion == "success")] | length),
             failure: ([.[] | select(.conclusion == "failure")] | length),
             skipped: ([.[] | select(.conclusion == "skipped")] | length)}) |
        sort_by(-.runs)[] |
        "  \(.name): \(.runs) runs (\(.success) ok, \(.failure) fail, \(.skipped) skip)"'
```

**5. Quick waste indicators:**

```bash
echo ""
echo "=== Waste Indicators ==="

# Count skipped runs
SKIPPED=$(gh api "/repos/$REPO/actions/runs?per_page=100" \
  --jq '[.workflow_runs[] | select(.conclusion == "skipped")] | length')
TOTAL=$(gh api "/repos/$REPO/actions/runs?per_page=100" --jq '.workflow_runs | length')

echo "Skipped runs: $SKIPPED/$TOTAL"

# Check for missing concurrency in workflow files
if [ -d ".github/workflows" ]; then
  MISSING_CONCURRENCY=$(ls .github/workflows/*.yml .github/workflows/*.yaml 2>/dev/null | while read f; do
    grep -L "concurrency:" "$f" 2>/dev/null
  done | wc -l | tr -d ' ')
  echo "Workflows missing concurrency: $MISSING_CONCURRENCY"
fi
```

## Output Format

```
=== Org Billing: orgname ===
Minutes: 1234/2000 included, 0 paid

=== Org Cache Usage ===
45 caches, 2340MB total

=== Repo: orgname/reponame ===
Cache:
  12 caches, 450MB

Workflows (last 30 days):
  CI: 45 runs (40 ok, 3 fail, 2 skip)
  Deploy: 12 runs (12 ok, 0 fail, 0 skip)
  CodeQL: 30 runs (28 ok, 0 fail, 2 skip)

=== Waste Indicators ===
Skipped runs: 4/87
Workflows missing concurrency: 2
```

## Post-actions

Suggest next steps based on findings:
- High skipped runs → `/finops:waste`
- High cache usage → `/finops:caches`
- Want detailed workflow analysis → `/finops:workflows`
- Compare across repos → `/finops:compare`
