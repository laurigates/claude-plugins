---
model: haiku
description: Compare FinOps metrics across multiple repositories in an organization
args: "<org> [repo1 repo2 ...] [--limit N]"
allowed-tools: Bash(gh api *), Bash(gh repo *), Read, TodoWrite
argument-hint: Org name required, optional repo list, --limit for auto-discovery
created: 2025-01-30
modified: 2025-01-30
reviewed: 2025-01-30
name: finops-compare
---

# /finops:compare

Compare GitHub Actions FinOps metrics across multiple repositories - cache usage, workflow frequency, failure rates, and efficiency.

## Parameters

| Parameter | Description | Default |
|-----------|-------------|---------|
| `org` | GitHub organization name (required) | - |
| `repos...` | Space-separated list of repo names | All org repos |
| `--limit N` | Limit auto-discovery to N repos | 30 |

## Usage Examples

```bash
# Compare specific repos
/finops:compare myorg repo1 repo2 repo3

# Compare all repos in org (up to 30)
/finops:compare myorg

# Compare more repos
/finops:compare myorg --limit 50
```

## Execution

**1. Parse arguments:**

```bash
ORG="$1"
shift

# Check for --limit flag
LIMIT=30
REPOS=()
while [[ $# -gt 0 ]]; do
  case $1 in
    --limit)
      LIMIT="$2"
      shift 2
      ;;
    *)
      REPOS+=("$1")
      shift
      ;;
  esac
done

echo "=== FinOps Comparison: $ORG ==="
echo ""
```

**2. Discover repos if not specified:**

```bash
if [ ${#REPOS[@]} -eq 0 ]; then
  echo "Discovering repos (limit: $LIMIT)..."
  REPOS=($(gh repo list "$ORG" --json name --limit "$LIMIT" --jq '.[].name'))
  echo "Found ${#REPOS[@]} repos"
fi
echo ""
```

**3. Cache usage comparison:**

```bash
echo "=== Cache Usage ==="
printf "%-40s %10s %12s\n" "Repository" "Caches" "Size (MB)"
printf "%-40s %10s %12s\n" "----------" "------" "---------"

for repo in "${REPOS[@]}"; do
  result=$(gh api "/repos/$ORG/$repo/actions/cache/usage" 2>/dev/null)
  if [ -n "$result" ]; then
    count=$(echo "$result" | jq -r '.active_caches_count // 0')
    size=$(echo "$result" | jq -r '.active_caches_size_in_bytes // 0')
    size_mb=$((size / 1024 / 1024))
    printf "%-40s %10d %12d\n" "$repo" "$count" "$size_mb"
  fi
done | sort -t$'\t' -k3 -n -r

echo ""
```

**4. Workflow activity comparison:**

```bash
echo "=== Workflow Activity (last 30 days) ==="
printf "%-40s %8s %8s %8s %10s\n" "Repository" "Runs" "Success" "Failed" "Skip Rate"
printf "%-40s %8s %8s %8s %10s\n" "----------" "----" "-------" "------" "---------"

for repo in "${REPOS[@]}"; do
  result=$(gh api "/repos/$ORG/$repo/actions/runs?per_page=100" 2>/dev/null)
  if [ -n "$result" ]; then
    stats=$(echo "$result" | jq -r '
      .workflow_runs |
      {
        total: length,
        success: ([.[] | select(.conclusion == "success")] | length),
        failed: ([.[] | select(.conclusion == "failure")] | length),
        skipped: ([.[] | select(.conclusion == "skipped")] | length)
      } |
      "\(.total)\t\(.success)\t\(.failed)\t\(if .total > 0 then (.skipped * 100 / .total | floor) else 0 end)%"
    ')
    printf "%-40s %8s\n" "$repo" "$stats"
  fi
done | sort -t$'\t' -k2 -n -r

echo ""
```

**5. Failure rate comparison:**

```bash
echo "=== Failure Rates ==="
printf "%-40s %8s %8s %10s\n" "Repository" "Total" "Failed" "Rate"
printf "%-40s %8s %8s %10s\n" "----------" "-----" "------" "----"

for repo in "${REPOS[@]}"; do
  result=$(gh api "/repos/$ORG/$repo/actions/runs?per_page=100&status=completed" 2>/dev/null)
  if [ -n "$result" ]; then
    stats=$(echo "$result" | jq -r '
      .workflow_runs |
      {
        total: length,
        failed: ([.[] | select(.conclusion == "failure")] | length)
      } |
      "\(.total)\t\(.failed)\t\(if .total > 0 then (.failed * 100 / .total | floor) else 0 end)%"
    ')
    printf "%-40s %8s\n" "$repo" "$stats"
  fi
done | sort -t$'\t' -k4 -n -r | head -15

echo ""
```

**6. Workflow count comparison:**

```bash
echo "=== Active Workflows ==="
printf "%-40s %10s\n" "Repository" "Workflows"
printf "%-40s %10s\n" "----------" "---------"

for repo in "${REPOS[@]}"; do
  count=$(gh workflow list --repo "$ORG/$repo" --json id --jq 'length' 2>/dev/null || echo "0")
  printf "%-40s %10s\n" "$repo" "$count"
done | sort -t$'\t' -k2 -n -r

echo ""
```

**7. Summary statistics:**

```bash
echo "=== Summary ==="

# Total cache usage
TOTAL_CACHE=0
for repo in "${REPOS[@]}"; do
  size=$(gh api "/repos/$ORG/$repo/actions/cache/usage" --jq '.active_caches_size_in_bytes // 0' 2>/dev/null)
  TOTAL_CACHE=$((TOTAL_CACHE + size))
done
echo "Total cache usage: $((TOTAL_CACHE / 1024 / 1024))MB across ${#REPOS[@]} repos"

# Repos with high cache usage (>1GB)
echo ""
echo "Repos exceeding 1GB cache:"
for repo in "${REPOS[@]}"; do
  size=$(gh api "/repos/$ORG/$repo/actions/cache/usage" --jq '.active_caches_size_in_bytes // 0' 2>/dev/null)
  if [ "$size" -gt 1073741824 ]; then
    echo "  $repo: $((size / 1024 / 1024))MB"
  fi
done

# Repos with high failure rates (>20%)
echo ""
echo "Repos with >20% failure rate:"
for repo in "${REPOS[@]}"; do
  result=$(gh api "/repos/$ORG/$repo/actions/runs?per_page=50&status=completed" 2>/dev/null)
  if [ -n "$result" ]; then
    rate=$(echo "$result" | jq -r '
      .workflow_runs |
      if length > 0 then
        ([.[] | select(.conclusion == "failure")] | length) * 100 / length | floor
      else 0 end
    ')
    if [ "$rate" -gt 20 ]; then
      echo "  $repo: ${rate}% failure rate"
    fi
  fi
done
```

## Output Format

```
=== FinOps Comparison: myorg ===

Discovering repos (limit: 30)...
Found 25 repos

=== Cache Usage ===
Repository                               Caches    Size (MB)
----------                               ------    ---------
frontend-app                                 45         2340
backend-api                                  32         1850
shared-libs                                  18          420
...

=== Workflow Activity (last 30 days) ===
Repository                                 Runs  Success   Failed  Skip Rate
----------                                 ----  -------   ------  ---------
frontend-app                                156      140       10         3%
backend-api                                  89       85        2         2%
...

=== Failure Rates ===
Repository                                Total   Failed       Rate
----------                                -----   ------       ----
legacy-service                               45       12        26%
experimental-repo                            20        5        25%
...

=== Active Workflows ===
Repository                               Workflows
----------                               ---------
frontend-app                                     8
backend-api                                      5
...

=== Summary ===
Total cache usage: 8450MB across 25 repos

Repos exceeding 1GB cache:
  frontend-app: 2340MB
  backend-api: 1850MB

Repos with >20% failure rate:
  legacy-service: 26%
  experimental-repo: 25%
```

## Post-actions

Based on comparison results:
- **High cache repos**: Run `/finops:caches <repo>` for detailed analysis
- **High failure repos**: Run `/finops:workflows <repo>` to investigate
- **High activity repos**: Run `/finops:waste <repo>` to find optimizations
- **Create report**: Consider creating a GitHub issue with findings
