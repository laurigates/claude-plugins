#!/usr/bin/env bash
# PostToolUse hook — feature-tracker freshness auto-sync on docs changes.
#
# Implements docs/hook-plans/p1-feature-tracker-auto-sync.md as the on-change
# half of the ADR-0020 level-1 rung. Called by blueprint-doc-change.sh for each
# changed docs/** path (Write, Edit, or a Bash command's bashEditDiff).
#
# Bounded auto-apply on an unambiguous fact only: when the changed document
# references feature codes that ALREADY EXIST in the tracker, refresh the
# tracker's last_updated date (and updated_at, only when the tracker already
# carries that key, so the two never disagree; it is never added) and
# recompute the statistics block (a pure function of the tracker itself). It never creates feature codes and never
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

# Write/Edit payloads carry an absolute file_path; the checks below are
# project-relative. Resolve from the project root.
HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091  # lib/doc-paths.sh resolves at runtime from HOOK_DIR
. "${HOOK_DIR}/lib/doc-paths.sh"
ROOT=$(blueprint_project_root) || exit 0
cd "$ROOT" || exit 0
FILE_PATH=$(blueprint_relpath "$FILE_PATH" "$ROOT")
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
# array plus inline references. Both id styles are recognised (#3001):
# hierarchical `FR1` / `FR1.2` and zero-padded `FR-001` / `FR-1.2`.
frontmatter_codes=$(head -50 "$FILE_PATH" | awk '
    /^feature-codes:/ { in_codes = 1; next }
    in_codes && /^[[:space:]]*-/ { gsub(/^[[:space:]]*-[[:space:]]*/, ""); print }
    in_codes && /^[a-z]/ { exit }
' | tr -d '\r' || true)
inline_codes=$(grep -oE 'FR-?[0-9]+(\.[0-9]+)*' "$FILE_PATH" 2>/dev/null | sort -u || true)

all_codes=$(printf '%s\n%s\n' "$frontmatter_codes" "$inline_codes" | grep -E '^FR-?[0-9]' | sort -u || true)
[ -n "$all_codes" ] || exit 0

# Shared jq definitions, mirroring blueprint-plugin/scripts/blueprint-tracker-check.sh
# so the hook and the integrity check agree on what a feature is:
#   norm - canonical FR key (`FR-001` -> `FR1`, `FR-1.2` -> `FR1.2`), the
#          checker's norm_fr; empty for a non-FR token.
#   ids  - every id the features collection mints: object keys (FR category
#          -> nested `features`) or array records' id/code/name.
#   recs - feature RECORDS: status-bearing objects reached only through
#          `features` collections, in either shape. phases[] and tasks sit
#          outside the collection, so they never count.
# shellcheck disable=SC2016  # jq program text, not a shell expansion
JQ_DEFS='
def norm: ascii_upcase
    | (capture("^FR[-_ ]?0*(?<n>[0-9]+)(?<rest>(\\.[0-9]+)*)$") | "FR\(.n)\(.rest)") // empty;
def ids: if type == "array" then .[] | objects | (.id // .code // .name // empty) | tostring
    elif type == "object" then to_entries[] | select(.value | type == "object")
        | (.key, (.value.features // null | ids))
    else empty end;
def recs: (if type == "array" or type == "object" then .[] else empty end)
    | objects | (select(has("status")), (.features // null | recs));
'

# Count how many referenced codes exist in the tracker, compared by canonical
# key so a doc citing `FR-001` matches a tracker minting `FR1` and vice versa.
codes_json=$(printf '%s\n' "$all_codes" | jq -R -s 'split("\n") | map(select(length > 0))')
matched=$(jq --argjson codes "$codes_json" "${JQ_DEFS}"'
    [.features // null | ids | norm] as $tracked |
    [$codes[] | norm | select(. as $c | $tracked | index([$c]))] | unique | length
' "$TRACKER" 2>/dev/null || echo 0)

if [ -z "$matched" ] || [ "$matched" = "0" ]; then
    exit 0
fi

# Refresh last_updated (plus a pre-existing updated_at, #3232) and recompute statistics over the same record set and
# with the same completion formula blueprint-tracker-check.sh verifies:
# round(complete/total*1000)/10, one decimal place (51/52 -> 98.1, 1/2 -> 50).
today=$(date -u +%Y-%m-%d)
jq --arg today "$today" "${JQ_DEFS}"'
    [.features // null | recs] as $feats |
    ([$feats[] | select(.status == "complete")] | length) as $done |
    .last_updated = $today |
    (if has("updated_at") then .updated_at = $today else . end) |
    .statistics = {
        total_features: ($feats | length),
        complete: $done,
        partial: ([$feats[] | select(.status == "partial")] | length),
        in_progress: ([$feats[] | select(.status == "in_progress")] | length),
        not_started: ([$feats[] | select(.status == "not_started")] | length),
        blocked: ([$feats[] | select(.status == "blocked")] | length),
        completion_percentage: (if ($feats | length) > 0
            then (($done / ($feats | length)) * 1000 | round) / 10
            else 0 end)
    }
' "$TRACKER" > "${TRACKER}.tmp" && mv "${TRACKER}.tmp" "$TRACKER"

total=$(jq -r '.statistics.total_features' "$TRACKER" 2>/dev/null || echo "?")
complete=$(jq -r '.statistics.complete' "$TRACKER" 2>/dev/null || echo "?")
echo "INFO: Feature tracker refreshed: ${matched} tracked code(s) referenced by ${FILE_PATH}; completion ${complete}/${total}" >&2
exit 0
