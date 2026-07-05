#!/usr/bin/env bash
# PostToolUse hook — feature-tracker freshness auto-sync on docs changes.
#
# Implements docs/hook-plans/p1-feature-tracker-auto-sync.md as the on-change
# half of the ADR-0020 level-1 rung. Fires after Write/Edit under docs/**.
#
# Bounded auto-apply on an unambiguous fact only: when the changed document
# references feature codes that ALREADY EXIST in the tracker, refresh the
# tracker's last_updated date and recompute the statistics block (a pure
# function of the tracker itself). It never creates feature codes and never
# changes a feature's status — those need judgment and stay with
# /blueprint:feature-tracker-sync (p1 plan, Open Question 1).
#
# Gates: BLUEPRINT_SKIP_HOOKS=1, missing tracker, autonomy_level < 1, or
# task_registry["feature-tracker-sync"].enabled == false -> silent no-op.
# Non-blocking: always exits 0.

set -euo pipefail

if [ "${BLUEPRINT_SKIP_HOOKS:-0}" = "1" ]; then
    exit 0
fi

INPUT=$(cat)

FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null || true)
if [ -z "$FILE_PATH" ]; then
    exit 0
fi

# Only document changes under docs/ are signals; the tracker itself and the
# manifest are outputs, not signals (self-trigger guard).
case "$FILE_PATH" in
    docs/blueprint/feature-tracker.json|docs/blueprint/manifest.json) exit 0 ;;
    docs/*) ;;
    *) exit 0 ;;
esac

TRACKER="docs/blueprint/feature-tracker.json"
MANIFEST="docs/blueprint/manifest.json"

[ -f "$TRACKER" ] || exit 0
[ -f "$MANIFEST" ] || exit 0
[ -f "$FILE_PATH" ] || exit 0

# Malformed tracker: warn, never mutate.
if ! jq -e . "$TRACKER" >/dev/null 2>&1; then
    echo "WARNING: feature-tracker.json is not valid JSON; skipping auto-sync" >&2
    exit 0
fi

autorun_level=$(jq -r '.automation.autonomy_level // 0' "$MANIFEST" 2>/dev/null || echo 0)
case "$autorun_level" in
    ''|*[!0-9]*) autorun_level=0 ;;
esac
[ "$autorun_level" -ge 1 ] || exit 0

# Note: jq's // treats an explicit `false` as absent, so read the raw value
# and treat only the literal "false" as disabled (null/missing => enabled).
task_enabled=$(jq -r '.task_registry["feature-tracker-sync"].enabled' "$MANIFEST" 2>/dev/null || echo true)
[ "$task_enabled" != "false" ] || exit 0

# Extract feature codes from the changed file: frontmatter `feature-codes:`
# array plus inline FRn(.m)* references.
frontmatter_codes=$(head -50 "$FILE_PATH" | awk '
    /^feature-codes:/ { in_codes = 1; next }
    in_codes && /^[[:space:]]*-/ { gsub(/^[[:space:]]*-[[:space:]]*/, ""); print }
    in_codes && /^[a-z]/ { exit }
' | tr -d '\r' || true)
inline_codes=$(grep -oE 'FR[0-9]+(\.[0-9]+)*' "$FILE_PATH" 2>/dev/null | sort -u || true)

all_codes=$(printf '%s\n%s\n' "$frontmatter_codes" "$inline_codes" | grep -E '^FR[0-9]' | sort -u || true)
[ -n "$all_codes" ] || exit 0

# Count how many referenced codes exist in the tracker (top-level FRn
# categories or nested FRn.m features at any depth).
codes_json=$(printf '%s\n' "$all_codes" | jq -R -s 'split("\n") | map(select(length > 0))')
matched=$(jq --argjson codes "$codes_json" '
    [.. | objects | keys[]? | select(test("^FR[0-9]"))] as $tracked |
    [$codes[] | select(. as $c | $tracked | index($c))] | length
' "$TRACKER" 2>/dev/null || echo 0)

if [ -z "$matched" ] || [ "$matched" = "0" ]; then
    exit 0
fi

# Refresh last_updated and recompute statistics. Feature objects are the
# nested objects carrying name+status+phase — the has("phase") filter keeps
# phases[].status entries out of the counts.
today=$(date -u +%Y-%m-%d)
jq --arg today "$today" '
    ([.. | objects | select(has("status") and has("phase") and has("name"))]) as $feats |
    .last_updated = $today |
    .statistics = {
        total_features: ($feats | length),
        complete: ([$feats[] | select(.status == "complete")] | length),
        partial: ([$feats[] | select(.status == "partial")] | length),
        in_progress: ([$feats[] | select(.status == "in_progress")] | length),
        not_started: ([$feats[] | select(.status == "not_started")] | length),
        blocked: ([$feats[] | select(.status == "blocked")] | length),
        completion_percentage: (if ($feats | length) > 0
            then (([$feats[] | select(.status == "complete")] | length) * 100 / ($feats | length) | floor)
            else 0 end)
    }
' "$TRACKER" > "${TRACKER}.tmp" && mv "${TRACKER}.tmp" "$TRACKER"

total=$(jq -r '.statistics.total_features' "$TRACKER" 2>/dev/null || echo "?")
complete=$(jq -r '.statistics.complete' "$TRACKER" 2>/dev/null || echo "?")
echo "INFO: Feature tracker refreshed: ${matched} tracked code(s) referenced by ${FILE_PATH}; completion ${complete}/${total}" >&2
exit 0
