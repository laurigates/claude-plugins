#!/usr/bin/env bash
# evaluate-drift-probe.sh — SessionStart probe for evaluate-plugin drift.
#
# Detects eval-results that are older than the SKILL.md they evaluate.
# Layout (per evaluate-plugin/skills/evaluate-skill/SKILL.md):
#
#   <plugin>/skills/<skill>/SKILL.md
#   <plugin>/skills/<skill>/eval-results/*.json
#
# If the SKILL.md mtime is newer than every result file in eval-results/, the
# stored results no longer reflect what the skill currently does.
#
# No-ops when no eval-results/ directory exists anywhere in $DRIFT_CWD.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# >>> drift-protocol resolver >>>
# Keep this block byte-identical in every drift probe;
# scripts/tests/test-drift-probe-lib-resolution.sh enforces it.
# hooks-plugin ships the library. Layouts searched, in order:
#   flat    <root>/<plugin>/hooks          -> <root>/hooks-plugin/hooks/lib
#           (a claude-plugins checkout, --plugin-dir)
#   cache   <mkt>/<plugin>/<version>/hooks -> <mkt>/hooks-plugin/<version>/hooks/lib
#           (marketplace installs; old versions stay cached, highest wins)
#   legacy  ~/.claude/plugins/hooks-plugin/hooks/lib
# Before the cache layout was searched, every installed probe found nothing
# here and exited silently.
PROTO_LIB=""
for _dp_base in \
    "${SCRIPT_DIR}/../.." \
    "${CLAUDE_PLUGIN_ROOT:+${CLAUDE_PLUGIN_ROOT}/..}" \
    "${SCRIPT_DIR}/../../.." \
    "${CLAUDE_PLUGIN_ROOT:+${CLAUDE_PLUGIN_ROOT}/../..}" \
    "$HOME/.claude/plugins"; do
    if [ -z "$_dp_base" ] || [ ! -d "$_dp_base/hooks-plugin" ]; then
        continue
    fi
    if [ -f "$_dp_base/hooks-plugin/hooks/lib/drift-protocol.sh" ]; then
        PROTO_LIB="$_dp_base/hooks-plugin/hooks/lib/drift-protocol.sh"
        break
    fi
    _dp_ver=$(
        for _dp_lib in "$_dp_base"/hooks-plugin/*/hooks/lib/drift-protocol.sh; do
            if [ -f "$_dp_lib" ]; then
                _dp_lib="${_dp_lib#"$_dp_base"/hooks-plugin/}"
                printf '%s\n' "${_dp_lib%%/*}"
            fi
        done | sort -V | tail -n 1
    ) || _dp_ver=""
    if [ -n "$_dp_ver" ]; then
        PROTO_LIB="$_dp_base/hooks-plugin/$_dp_ver/hooks/lib/drift-protocol.sh"
        break
    fi
done
unset _dp_base _dp_ver _dp_lib
if [ -z "$PROTO_LIB" ]; then
    exit 0
fi
# shellcheck source=../../hooks-plugin/hooks/lib/drift-protocol.sh
# shellcheck disable=SC1091  # PROTO_LIB resolves at runtime via the search above
. "$PROTO_LIB"
# <<< drift-protocol resolver <<<

drift_init "evaluate-plugin"

# Discover any eval-results/ directories under the project.
# Bounded depth so the probe stays cheap on monorepos.
mapfile -t result_dirs < <(
    find "$DRIFT_CWD" -maxdepth 5 -type d -name 'eval-results' -not -path '*/node_modules/*' -not -path '*/.git/*' 2>/dev/null
)

if [ "${#result_dirs[@]}" -eq 0 ]; then
    drift_emit
    exit 0
fi

mtime_of() {
    # Cross-platform mtime (epoch seconds). Empty on failure.
    stat -f %m "$1" 2>/dev/null || stat -c %Y "$1" 2>/dev/null || echo ""
}

stale_count=0
for results_dir in "${result_dirs[@]}"; do
    # Skill dir is one level up.
    skill_dir=$(dirname "$results_dir")
    skill_md="${skill_dir}/SKILL.md"
    [ -f "$skill_md" ] || continue

    skill_mtime=$(mtime_of "$skill_md")
    [ -z "$skill_mtime" ] && continue

    # Most-recent result file in this dir.
    newest_result_mtime=0
    while IFS= read -r result; do
        [ -z "$result" ] && continue
        rm_=$(mtime_of "$result")
        [ -z "$rm_" ] && continue
        if [ "$rm_" -gt "$newest_result_mtime" ]; then
            newest_result_mtime="$rm_"
        fi
    done < <(find "$results_dir" -maxdepth 1 -type f -name '*.json' 2>/dev/null)

    if [ "$newest_result_mtime" -eq 0 ]; then
        continue
    fi

    if [ "$skill_mtime" -gt "$newest_result_mtime" ]; then
        stale_count=$((stale_count + 1))
    fi
done

if [ "$stale_count" -gt 0 ]; then
    drift_add_finding info \
        eval_results_stale \
        "${stale_count} skill(s) edited after their last eval-results run" \
        "/evaluate:report"
fi

drift_emit
exit 0
