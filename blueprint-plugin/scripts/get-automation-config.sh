#!/usr/bin/env bash
# get-automation-config.sh — read the manifest automation block (ADR-0020).
#
# Shared helper for blueprint skills that honor interaction_mode / autonomy
# levels. Exit-0-safe in every degraded case (no manifest, no jq, no
# automation block) — those all report level 0 / normal, i.e. today's fully
# interactive behavior.
#
# EFFECTIVE_INTERACTION_MODE resolution: an explicit interaction_mode in the
# manifest wins; when the key is ABSENT, level >= 2 defaults to quiet and
# levels 0-1 default to normal.
#
# Output follows .claude/rules/structured-script-output.md.
#
# Usage: get-automation-config.sh [--project-dir DIR]

set -u

project_dir="."
while [ $# -gt 0 ]; do
    case "$1" in
        --project-dir)
            project_dir="${2:-.}"
            shift 2
            ;;
        *)
            shift
            ;;
    esac
done

emit() {
    # emit <level> <mode> <effective> <auto_draft> <auto_execute> <source>
    printf '=== BLUEPRINT AUTOMATION ===\n'
    printf 'AUTONOMY_LEVEL=%s\n' "$1"
    printf 'INTERACTION_MODE=%s\n' "$2"
    printf 'EFFECTIVE_INTERACTION_MODE=%s\n' "$3"
    printf 'WO_AUTO_DRAFT=%s\n' "$4"
    printf 'WO_AUTO_EXECUTE=%s\n' "$5"
    printf 'SOURCE=%s\n' "$6"
    printf 'STATUS=OK\n'
    printf 'ISSUE_COUNT=0\n'
    printf '=== END BLUEPRINT AUTOMATION ===\n'
    exit 0
}

manifest=""
if [ -f "${project_dir}/docs/blueprint/manifest.json" ]; then
    manifest="${project_dir}/docs/blueprint/manifest.json"
elif [ -f "${project_dir}/docs/blueprint/.manifest.json" ]; then
    manifest="${project_dir}/docs/blueprint/.manifest.json"
fi

if [ -z "$manifest" ] || ! command -v jq >/dev/null 2>&1; then
    emit 0 unset normal false false none
fi

if ! jq -e '.automation' "$manifest" >/dev/null 2>&1; then
    emit 0 unset normal false false "${manifest}:no_automation_block"
fi

auto_level=$(jq -r '.automation.autonomy_level // 0' "$manifest" 2>/dev/null || echo 0)
case "$auto_level" in
    ''|*[!0-9]*) auto_level=0 ;;
esac

if jq -e '.automation | has("interaction_mode")' "$manifest" >/dev/null 2>&1; then
    declared_mode=$(jq -r '.automation.interaction_mode' "$manifest" 2>/dev/null || echo normal)
    case "$declared_mode" in
        quiet|normal|interactive) effective_mode="$declared_mode" ;;
        *) declared_mode="normal"; effective_mode="normal" ;;
    esac
else
    declared_mode="unset"
    if [ "$auto_level" -ge 2 ]; then
        effective_mode="quiet"
    else
        effective_mode="normal"
    fi
fi

# jq's // treats explicit false as absent — read raw and compare literally.
wo_draft=$(jq -r '.automation.work_orders.auto_draft' "$manifest" 2>/dev/null || echo false)
[ "$wo_draft" = "true" ] || wo_draft=false
wo_execute=$(jq -r '.automation.work_orders.auto_execute' "$manifest" 2>/dev/null || echo false)
[ "$wo_execute" = "true" ] || wo_execute=false

emit "$auto_level" "$declared_mode" "$effective_mode" "$wo_draft" "$wo_execute" "$manifest"
