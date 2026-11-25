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
# Usage: ./scripts/export-antigravity.sh [OUTPUT_DIR] [--plugin NAME ...]
#   OUTPUT_DIR defaults to dist/antigravity. Each --plugin limits the export to
#   that plugin's subagents and safety hooks; none means every plugin.
set -euo pipefail

export_script_dir="$(cd "$(dirname "$0")" && pwd)"
export_repo_root="$(cd "$export_script_dir/.." && pwd)"
# shellcheck source=/dev/null  # lib/plugin-args.sh, linted on its own
. "$export_script_dir/lib/plugin-args.sh"

export_out_dir=""
export_plugins=()
while [ "$#" -gt 0 ]; do
    case "$1" in
        --plugin)
            [ "$#" -ge 2 ] || { echo "--plugin needs a plugin name" >&2; exit 2; }
            require_plugin "$export_repo_root" "$2"
            export_plugins+=("$2")
            shift 2
            ;;
        -*) echo "unknown argument: $1" >&2; exit 2 ;;
        *)
            if [ -n "$export_out_dir" ]; then
                echo "unexpected argument: $1 (plugin names need --plugin)" >&2
                exit 2
            fi
            export_out_dir="$1"
            shift
            ;;
    esac
done
export_out_dir="${export_out_dir:-$export_repo_root/dist/antigravity}"

export_plugin_args=()
for p in ${export_plugins[@]+"${export_plugins[@]}"}; do
    export_plugin_args+=(--plugin "$p")
done

echo "=== ANTIGRAVITY EXPORT ==="
echo "SOURCE=$export_repo_root"
echo "OUTPUT=$export_out_dir"
echo "SKILLS=in-place (via skills.json — see configure-antigravity.sh)"
echo "PLUGINS=${export_plugins[*]:-all}"

rm -rf "$export_out_dir"
mkdir -p "$export_out_dir"

# 1. Subagents -> Antigravity agent format
export_agents_status=0
python3 "$export_script_dir/export-antigravity-agents.py" \
    "$export_repo_root" "$export_out_dir" ${export_plugins[@]+"${export_plugins[@]}"} \
    || export_agents_status=$?

# 2. Hooks -> hooks.json + runner + hook-scripts (nothing when the selected
#    plugins ship no safety hooks)
export_hooks_status=0
python3 "$export_script_dir/generate-antigravity-hooks.py" \
    "$export_repo_root" "$export_out_dir" ${export_plugin_args[@]+"${export_plugin_args[@]}"} \
    || export_hooks_status=$?

export_out_agents="$(find "$export_out_dir/agents" -name 'agent.md' 2>/dev/null | wc -l | tr -d ' ')"
# hook-scripts/ is absent when no hooks were selected; find's exit 1 would
# abort the script under pipefail.
export_out_hooks="$( { find "$export_out_dir/hook-scripts" -name '*.sh' 2>/dev/null || true; } | wc -l | tr -d ' ')"

echo "OUTPUT_AGENTS=$export_out_agents"
echo "OUTPUT_HOOK_SCRIPTS=$export_out_hooks"

# An unfiltered export with zero agents means discovery broke; a filtered one
# may legitimately select plugins that ship no agents (macos-plugin).
export_agents_ok=1
if [ "${#export_plugins[@]}" -eq 0 ] && [ "$export_out_agents" -eq 0 ]; then
    export_agents_ok=0
fi

if [ "$export_agents_status" -eq 0 ] && [ "$export_hooks_status" -eq 0 ] && [ "$export_agents_ok" -eq 1 ]; then
    echo "STATUS=OK"
    echo "ISSUE_COUNT=0"
else
    echo "STATUS=WARN"
    echo "ISSUE_COUNT=1"
fi
echo "=== END ANTIGRAVITY EXPORT ==="
