#!/usr/bin/env bash
# install-opencode-ocx.sh — opt-in installer for the OCX-distributed OpenCode
# orchestration plugins that complement (rather than overlap) our exported setup.
#
# Installs ONLY the non-overlapping plugins:
#   - worktree           — per-session git worktrees for parallel agents
#   - background-agents  — async task delegation with on-disk result persistence
#
# DELIBERATELY EXCLUDED: opencode-workspace. It bundles its own researcher/coder/
# reviewer agents + DCP + worktrees, which overlap and compete with the agents +
# orchestrator we already export. Prefer ours. See docs/opencode-export.md.
#
# These plugins are distributed via the third-party OCX CLI + registry
# (registry.kdco.dev), NOT the npm `plugin:` array — so this is a separate,
# explicitly opt-in path with a third-party trust dependency. OCX must already be
# installed and on PATH; this script does not install OCX itself.
#
# Usage: ./scripts/install-opencode-ocx.sh [target]   (target reserved for future scoping)
set -euo pipefail

ocx_target="${1:-~/.config/opencode}"

echo "=== OPENCODE OCX INSTALL ==="
echo "TARGET=$ocx_target"
echo "EXCLUDED=opencode-workspace (overlaps our exported agents/orchestrator — prefer ours)"

if ! command -v ocx >/dev/null 2>&1; then
    echo "OCX_AVAILABLE=false"
    echo "PREREQUISITE=the OCX CLI is required and was not found on PATH"
    echo "HINT=install the OCX CLI (kdcokenny OpenCode ecosystem; registry at https://registry.kdco.dev), then re-run"
    echo "STATUS=SKIP"
    echo "ISSUE_COUNT=0"
    echo "=== END OPENCODE OCX INSTALL ==="
    exit 0
fi
echo "OCX_AVAILABLE=true"

ocx_issue_count=0
for ocx_plugin in worktree background-agents; do
    echo "INSTALLING=$ocx_plugin"
    if ocx add "kdco/$ocx_plugin" --from https://registry.kdco.dev; then
        echo "INSTALLED=$ocx_plugin"
    else
        echo "FAILED=$ocx_plugin"
        ocx_issue_count=$((ocx_issue_count + 1))
    fi
done

if [ "$ocx_issue_count" -eq 0 ]; then
    echo "STATUS=OK"
else
    echo "STATUS=ERROR"
fi
echo "ISSUE_COUNT=$ocx_issue_count"
echo "=== END OPENCODE OCX INSTALL ==="
