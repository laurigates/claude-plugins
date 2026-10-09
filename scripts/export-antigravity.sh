#!/usr/bin/env bash
# export-antigravity.sh — project this marketplace's subagents and lifecycle
# hooks into Antigravity CLI format (output: dist/antigravity).
#
# SKILLS ARE NOT EXPORTED. Antigravity CLI discovers skills natively and
# budgets their listing via progressive disclosure. configure-antigravity.sh
# registers skills in-place via skills.json (ADR-0022 principles: zero copying,
# zero drift).
#
# What gets exported:
#   - Subagents: Projected into Antigravity Markdown format (agents/<name>/agent.md)
#     with model tier mapping (opus->pro, sonnet->flash, haiku->flash_lite)
#     and inheritCustomizations=true.
#   - Hooks: Claude Code safety hooks + CLAUDE_* variable emulation projected into
#     hooks.json + run-agy-hook.py / run-agy-hook.sh.
#
# Usage: ./scripts/export-antigravity.sh [OUTPUT_DIR]   (default: dist/antigravity)
set -euo pipefail

export_script_dir="$(cd "$(dirname "$0")" && pwd)"
export_repo_root="$(cd "$export_script_dir/.." && pwd)"
export_out_dir="${1:-$export_repo_root/dist/antigravity}"

echo "=== ANTIGRAVITY EXPORT ==="
echo "SOURCE=$export_repo_root"
echo "OUTPUT=$export_out_dir"
echo "SKILLS=in-place (via skills.json — see configure-antigravity.sh)"

rm -rf "$export_out_dir"
mkdir -p "$export_out_dir"

# 1. Subagents -> Antigravity agent format
export_agents_status=0
python3 "$export_script_dir/export-antigravity-agents.py" \
    "$export_repo_root" "$export_out_dir" || export_agents_status=$?

# 2. Hooks -> hooks.json + runner + hook-scripts
export_hooks_status=0
python3 "$export_script_dir/generate-antigravity-hooks.py" \
    "$export_repo_root" "$export_out_dir" || export_hooks_status=$?

export_out_agents="$(find "$export_out_dir/agents" -name 'agent.md' 2>/dev/null | wc -l | tr -d ' ')"
export_out_hooks="$(find "$export_out_dir/hook-scripts" -name '*.sh' 2>/dev/null | wc -l | tr -d ' ')"

echo "OUTPUT_AGENTS=$export_out_agents"
echo "OUTPUT_HOOK_SCRIPTS=$export_out_hooks"

if [ "$export_agents_status" -eq 0 ] && [ "$export_hooks_status" -eq 0 ] && [ "$export_out_agents" -gt 0 ]; then
    echo "STATUS=OK"
    echo "ISSUE_COUNT=0"
else
    echo "STATUS=WARN"
    echo "ISSUE_COUNT=1"
fi
echo "=== END ANTIGRAVITY EXPORT ==="
