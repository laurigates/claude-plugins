#!/usr/bin/env bash
# export-opencode.sh — project this marketplace's subagents and hooks into
# OpenCode format. No rulesync, no npm, no network (#2094).
#
# SKILLS ARE NOT EXPORTED. OpenCode reads Claude Code `SKILL.md` natively
# (its own docs list `~/.claude/skills/<name>/SKILL.md` as auto-loaded), so the
# conversion half of the old pipeline solved a problem that no longer exists —
# and a flattened copy of ~400 skills costs ~34,000 standing tokens per turn
# (measured 2026-08-24, adapters/CUTOVER.md §8). The marketplace corpus reaches
# OpenCode through the adapter instead: a `search_skills` pull tool plus ranked
# top-k push injection at ~600 standing tokens (ADR-0022, adapters/opencode/).
#
# What still needs projecting, and why:
#   - Subagents: OpenCode does NOT auto-load `~/.claude/agents/`, and its agent
#     schema differs (no model/tools/maxTurns). export-opencode-agents.py owns
#     that transform.
#   - Hooks: OpenCode has no Claude Code hook surface at all; command-type
#     PreToolUse/PostToolUse hooks become OpenCode JS plugins via
#     generate-opencode-hook-plugins.py. prompt/agent hooks and
#     SessionStart/PreCompact have no equivalent and are skipped with a report.
#
# Source is read-only; output is fully reproducible.
#
# Usage: ./scripts/export-opencode.sh [OUTPUT_DIR]   (default: dist/opencode)
set -euo pipefail

export_script_dir="$(cd "$(dirname "$0")" && pwd)"
export_repo_root="$(cd "$export_script_dir/.." && pwd)"
export_out_dir="${1:-$export_repo_root/dist/opencode}"

echo "=== OPENCODE EXPORT ==="
echo "SOURCE=$export_repo_root"
echo "OUTPUT=$export_out_dir"
echo "SKILLS=adapter (not exported — see adapters/opencode/, ADR-0022)"

rm -rf "$export_out_dir"
mkdir -p "$export_out_dir"

# 1. Subagents -> OpenCode agent frontmatter.
export_agents_status=0
python3 "$export_script_dir/export-opencode-agents.py" \
    "$export_repo_root" "$export_out_dir" || export_agents_status=$?

# 2. Each plugin's hooks.json -> OpenCode JS plugins + the referenced scripts.
#    Emits plugins/<plugin>-hooks.js + hook-scripts/<plugin>/hooks/*.sh.
python3 "$export_script_dir/generate-opencode-hook-plugins.py" \
    "$export_repo_root" "$export_out_dir"

export_out_agents="$(find "$export_out_dir/agents" -name '*.md' 2>/dev/null | wc -l | tr -d ' ')"
export_out_plugins="$(find "$export_out_dir/plugins" -name '*-hooks.js' 2>/dev/null | wc -l | tr -d ' ')"
echo "OUTPUT_AGENTS=$export_out_agents"
echo "OUTPUT_HOOK_PLUGINS=$export_out_plugins"

if [ "$export_agents_status" -eq 0 ] && [ "$export_out_agents" -gt 0 ]; then
    echo "STATUS=OK"
    echo "ISSUE_COUNT=0"
else
    echo "STATUS=WARN"
    echo "ISSUE_COUNT=1"
fi
echo "=== END OPENCODE EXPORT ==="
