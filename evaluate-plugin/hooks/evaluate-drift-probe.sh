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

PROTO_LIB="${SCRIPT_DIR}/../../hooks-plugin/hooks/lib/drift-protocol.sh"
if [ ! -f "$PROTO_LIB" ]; then
    for candidate in \
        "${CLAUDE_PLUGIN_ROOT:-}/../hooks-plugin/hooks/lib/drift-protocol.sh" \
        "$HOME/.claude/plugins/hooks-plugin/hooks/lib/drift-protocol.sh"; do
        if [ -n "$candidate" ] && [ -f "$candidate" ]; then
            PROTO_LIB="$candidate"
            break
        fi
    done
fi
if [ ! -f "$PROTO_LIB" ]; then
    exit 0
fi
# shellcheck source=../../hooks-plugin/hooks/lib/drift-protocol.sh
# shellcheck disable=SC1091  # PROTO_LIB resolves at runtime via fallback chain
. "$PROTO_LIB"

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
