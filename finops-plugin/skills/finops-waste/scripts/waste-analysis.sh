#!/usr/bin/env bash
# Waste Analysis
# Identifies GitHub Actions waste patterns: skipped runs, bot triggers,
# duplicate runs, and high-frequency workflows.
# Usage: bash waste-analysis.sh [repo]
#
# Args:
#   repo  Repository in owner/name format (default: current repo)
#
# Note: Workflow file analysis (concurrency, path filters) requires local
#       filesystem access and is handled inline in SKILL.md.

# shellcheck disable=SC2016  # jq expressions use $ for variable references, not shell expansion
set -euo pipefail

REPO="${1:-$(gh repo view --json nameWithOwner --jq '.nameWithOwner')}"
echo "=== Waste Analysis: $REPO ==="
echo ""

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

echo "$SKIPPED_DATA" | jq -r '"Total runs: \(.total)\nSkipped: \(.skipped) (\(if .total > 0 then (.skipped * 100 / .total | floor) else 0 end)%)"'
echo ""
echo "By workflow:"
echo "$SKIPPED_DATA" | jq -r '.by_workflow[] | "  \(.workflow): \(.count) skipped"'

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
  } |
  "Bot-triggered: \(.bot_triggered)/\(.total) runs\n\nBy bot:\(.bots | map("\n  \(.bot): \(.count) runs") | join(""))"'

echo ""
echo "=== Potential Duplicate Runs ==="
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

echo ""
echo "=== High-Frequency Workflows ==="
gh api "/repos/$REPO/actions/runs?per_page=100" \
  --jq '.workflow_runs | group_by(.name) |
        map(select(length > 30)) |
        map({workflow: .[0].name, count: length}) |
        sort_by(-.count)[] |
        "  \(.workflow): \(.count) runs in sample - review trigger conditions"'
