#!/usr/bin/env bash
# shellcheck disable=SC2015,SC2181  # `[ … ] && ok || notok` assertions: ok() exits 0, so notok only runs on a real miss
# Regression tests for sync-feature-tracker.sh (ADR-0020 on-change rung;
# implements docs/hook-plans/p1-feature-tracker-auto-sync.md).
#
# Pins the semantic contract:
#   - level 0 / missing tracker / disabled task / BLUEPRINT_SKIP_HOOKS are no-ops
#   - referencing an EXISTING tracked code refreshes last_updated + statistics
#   - unknown codes never create tracker entries (p1 Open Question 1)
#   - per-feature status is never changed; phases[].status never counts as a feature
#   - writes to the tracker/manifest themselves are self-trigger-guarded
#   - malformed tracker JSON is left untouched (exit 0)
#   - FR-NNN ids (object keys or array records) match like FRn / FRn.m (#3001)
#   - completion_percentage is round(complete/total*1000)/10 and the written
#     statistics pass blueprint-tracker-check.sh with zero divergence (#3001)
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="${SCRIPT_DIR}/sync-feature-tracker.sh"

pass=0
fail=0
ok() { pass=$((pass + 1)); printf 'ok   - %s\n' "$1"; }
notok() { fail=$((fail + 1)); printf 'FAIL - %s\n' "$1"; }

make_project() {
    # make_project <level>
    local proj
    proj=$(mktemp -d)
    if [ -z "$proj" ] || [ ! -d "$proj" ]; then
        echo "FATAL: mktemp failed" >&2
        exit 1
    fi
    mkdir -p "$proj/docs/blueprint" "$proj/docs/prps"
    cat > "$proj/docs/blueprint/manifest.json" <<EOF
{
  "format_version": "3.4.0",
  "automation": { "autonomy_level": $1 },
  "task_registry": {
    "feature-tracker-sync": { "enabled": true, "auto_run": true, "schedule": "daily" }
  }
}
EOF
    cat > "$proj/docs/blueprint/feature-tracker.json" <<'EOF'
{
  "version": "1.0.0",
  "last_updated": "2026-01-01",
  "project": "fixture",
  "source_document": "REQUIREMENTS.md",
  "phases": [
    { "id": "phase-1", "name": "Phase one", "status": "in_progress" }
  ],
  "features": {
    "FR1": {
      "name": "Category one",
      "features": {
        "FR1.1": { "name": "Feature A", "status": "complete", "phase": "phase-1" },
        "FR1.2": { "name": "Feature B", "status": "not_started", "phase": "phase-1" }
      }
    }
  }
}
EOF
    printf '%s' "$proj"
}

run_hook() {
    # run_hook <project_dir> <file_path> [env pairs...]
    local proj="$1" fp="$2"
    shift 2
    (cd "$proj" && printf '{"tool_input": {"file_path": "%s"}}' "$fp" | env "$@" bash "$HOOK" 2>/dev/null)
}

write_prp() {
    # write_prp <project_dir> <codes...>
    local proj="$1"
    shift
    {
        printf -- '---\nfeature-codes:\n'
        for c in "$@"; do printf '  - %s\n' "$c"; done
        printf -- '---\n\n# Fixture PRP\n'
    } > "$proj/docs/prps/fixture.md"
}

tracker_last() { jq -r '.last_updated' "$1/docs/blueprint/feature-tracker.json"; }

# ---- Test A: level 1 + existing code -> last_updated refreshed + stats recomputed ----
proj=$(make_project 1)
write_prp "$proj" FR1.1
run_hook "$proj" "docs/prps/fixture.md" X=1
rc=$?
[ "$rc" -eq 0 ] && ok "A: exit 0" || notok "A: exit $rc"
[ "$(tracker_last "$proj")" != "2026-01-01" ] && ok "A: last_updated refreshed" || notok "A: last_updated stale"
stats_total=$(jq -r '.statistics.total_features' "$proj/docs/blueprint/feature-tracker.json")
[ "$stats_total" = "2" ] && ok "A: phases excluded from feature count" || notok "A: total_features=$stats_total (phase leaked in?)"
stats_pct=$(jq -r '.statistics.completion_percentage' "$proj/docs/blueprint/feature-tracker.json")
[ "$stats_pct" = "50" ] && ok "A: completion percentage" || notok "A: completion=$stats_pct"
fr_status=$(jq -r '.features.FR1.features["FR1.1"].status' "$proj/docs/blueprint/feature-tracker.json")
[ "$fr_status" = "complete" ] && ok "A: per-feature status untouched" || notok "A: status mutated ($fr_status)"
rm -rf "$proj"

# ---- Test B: unknown codes -> tracker untouched, no new entries ----
proj=$(make_project 1)
write_prp "$proj" FR9.9
run_hook "$proj" "docs/prps/fixture.md" X=1
[ "$(tracker_last "$proj")" = "2026-01-01" ] && ok "B: unknown code leaves tracker untouched" || notok "B: tracker mutated for unknown code"
if jq -e '.. | objects | select(has("FR9.9"))' "$proj/docs/blueprint/feature-tracker.json" >/dev/null 2>&1; then
    notok "B: unknown code was created"
else
    ok "B: unknown code not created"
fi
rm -rf "$proj"

# ---- Test C: level 0 -> no-op ----
proj=$(make_project 0)
write_prp "$proj" FR1.1
run_hook "$proj" "docs/prps/fixture.md" X=1
[ "$(tracker_last "$proj")" = "2026-01-01" ] && ok "C: level 0 is a no-op" || notok "C: level 0 mutated tracker"
rm -rf "$proj"

# ---- Test D: disabled task -> no-op ----
proj=$(make_project 1)
jq '.task_registry["feature-tracker-sync"].enabled = false' "$proj/docs/blueprint/manifest.json" \
    > "$proj/docs/blueprint/manifest.json.tmp" && mv "$proj/docs/blueprint/manifest.json.tmp" "$proj/docs/blueprint/manifest.json"
write_prp "$proj" FR1.1
run_hook "$proj" "docs/prps/fixture.md" X=1
[ "$(tracker_last "$proj")" = "2026-01-01" ] && ok "D: enabled:false wins" || notok "D: disabled task ran"
rm -rf "$proj"

# ---- Test E: BLUEPRINT_SKIP_HOOKS + non-docs path + self-trigger guard ----
proj=$(make_project 1)
write_prp "$proj" FR1.1
run_hook "$proj" "docs/prps/fixture.md" BLUEPRINT_SKIP_HOOKS=1
[ "$(tracker_last "$proj")" = "2026-01-01" ] && ok "E: BLUEPRINT_SKIP_HOOKS honored" || notok "E: skip-hooks ignored"
run_hook "$proj" "src/main.py" X=1
[ "$(tracker_last "$proj")" = "2026-01-01" ] && ok "E: non-docs path ignored" || notok "E: non-docs path mutated tracker"
run_hook "$proj" "docs/blueprint/feature-tracker.json" X=1
[ "$(tracker_last "$proj")" = "2026-01-01" ] && ok "E: tracker write self-guarded" || notok "E: self-trigger loop"
rm -rf "$proj"

# ---- Test F: inline FR references (no frontmatter) also count ----
proj=$(make_project 1)
printf '# Notes\n\nThis touches FR1.2 directly.\n' > "$proj/docs/prps/fixture.md"
run_hook "$proj" "docs/prps/fixture.md" X=1
[ "$(tracker_last "$proj")" != "2026-01-01" ] && ok "F: inline code reference detected" || notok "F: inline reference missed"
rm -rf "$proj"

# ---- Test G: malformed tracker -> untouched, exit 0 ----
proj=$(make_project 1)
printf '{ not json' > "$proj/docs/blueprint/feature-tracker.json"
write_prp "$proj" FR1.1
run_hook "$proj" "docs/prps/fixture.md" X=1
rc=$?
[ "$rc" -eq 0 ] && ok "G: malformed tracker exits 0" || notok "G: exit $rc"
[ "$(cat "$proj/docs/blueprint/feature-tracker.json")" = "{ not json" ] && ok "G: malformed tracker untouched" || notok "G: malformed tracker rewritten"
rm -rf "$proj"

# ---- Test H: missing tracker -> silent no-op ----
proj=$(make_project 1)
rm "$proj/docs/blueprint/feature-tracker.json"
write_prp "$proj" FR1.1
run_hook "$proj" "docs/prps/fixture.md" X=1
[ $? -eq 0 ] && ok "H: missing tracker no-op" || notok "H: missing tracker errored"
rm -rf "$proj"

# ---- #3001: FR-NNN codes + rounded completion_percentage --------------------
# The hook used to match only `FR[0-9]` (so FR-001 trackers were a permanent
# no-op) and wrote floor(complete*100/total), which blueprint-tracker-check.sh
# reports as statistics_divergence (it expects round(c/t*1000)/10).
CHECKER="${SCRIPT_DIR}/../scripts/blueprint-tracker-check.sh"

checker_divergence() {
    # checker_divergence <project_dir> -> STATISTICS_DIVERGENCE_COUNT value,
    # or "no-stats" when the hook wrote none (a vacuous 0 must not pass).
    bash "$CHECKER" --project-dir "$1" 2>/dev/null | awk -F= '
        $1 == "STATISTICS_PRESENT" { present = $2 }
        $1 == "STATISTICS_DIVERGENCE_COUNT" { count = $2 }
        END { print (present == "true" ? count : "no-stats") }'
}

write_tracker() {
    # write_tracker <project_dir> <jq program building .features>
    jq -n "{version: \"1.0.0\", last_updated: \"2026-01-01\", project: \"fixture\",
            source_document: \"REQUIREMENTS.md\",
            phases: [{id: \"phase-1\", name: \"Phase one\", status: \"in_progress\"}],
            features: ($2)}" > "$1/docs/blueprint/feature-tracker.json"
}

# Test I: object-shaped tracker keyed by FR-NNN, 51/52 complete -> 98.1
proj=$(make_project 1)
write_tracker "$proj" '[range(1; 53) | {key: ("FR-" + ("00" + tostring | .[-3:])),
    value: {name: ("Feature " + tostring), phase: "phase-1",
            status: (if . == 52 then "not_started" else "complete" end)}}] | from_entries'
write_prp "$proj" FR-001
run_hook "$proj" "docs/prps/fixture.md" X=1
[ "$(tracker_last "$proj")" != "2026-01-01" ] && ok "I: FR-NNN frontmatter code matched" || notok "I: FR-NNN code ignored (hook no-op)"
stats_pct=$(jq -r '.statistics.completion_percentage' "$proj/docs/blueprint/feature-tracker.json")
[ "$stats_pct" = "98.1" ] && ok "I: 51/52 completion is 98.1" || notok "I: completion=$stats_pct (want 98.1)"
div=$(checker_divergence "$proj")
[ "$div" = "0" ] && ok "I: tracker-check sees no statistics_divergence" || notok "I: tracker-check divergence=$div"
rm -rf "$proj"

# Test J: array-shaped tracker of FR-NNN records, inline citation in prose
proj=$(make_project 1)
write_tracker "$proj" '[range(1; 4) | {id: ("FR-" + ("00" + tostring | .[-3:])),
    name: ("Feature " + tostring), status: (if . == 1 then "complete" else "in_progress" end)}]'
printf '# Notes\n\nThis implements FR-002 end to end.\n' > "$proj/docs/prps/fixture.md"
run_hook "$proj" "docs/prps/fixture.md" X=1
[ "$(tracker_last "$proj")" != "2026-01-01" ] && ok "J: inline FR-NNN in array tracker matched" || notok "J: inline FR-NNN ignored"
stats_total=$(jq -r '.statistics.total_features' "$proj/docs/blueprint/feature-tracker.json")
[ "$stats_total" = "3" ] && ok "J: array records counted" || notok "J: total_features=$stats_total (want 3)"
stats_pct=$(jq -r '.statistics.completion_percentage' "$proj/docs/blueprint/feature-tracker.json")
[ "$stats_pct" = "33.3" ] && ok "J: 1/3 completion is 33.3" || notok "J: completion=$stats_pct (want 33.3)"
div=$(checker_divergence "$proj")
[ "$div" = "0" ] && ok "J: tracker-check sees no statistics_divergence" || notok "J: tracker-check divergence=$div"
rm -rf "$proj"

# Test K: unknown FR-NNN code still never mutates the tracker
proj=$(make_project 1)
write_tracker "$proj" '{"FR-001": {name: "A", phase: "phase-1", status: "complete"}}'
write_prp "$proj" FR-999
run_hook "$proj" "docs/prps/fixture.md" X=1
[ "$(tracker_last "$proj")" = "2026-01-01" ] && ok "K: unknown FR-NNN leaves tracker untouched" || notok "K: tracker mutated for unknown FR-NNN"
rm -rf "$proj"

# Test L: FRn.m codes (no FR-NNN involved), 2/3 complete -> 66.7, not floor 66
proj=$(make_project 1)
write_tracker "$proj" '{FR1: {name: "Cat", features: {
    "FR1.1": {name: "A", phase: "phase-1", status: "complete"},
    "FR1.2": {name: "B", phase: "phase-1", status: "complete"},
    "FR1.3": {name: "C", phase: "phase-1", status: "blocked"}}}}'
write_prp "$proj" FR1.2
run_hook "$proj" "docs/prps/fixture.md" X=1
stats_pct=$(jq -r '.statistics.completion_percentage' "$proj/docs/blueprint/feature-tracker.json")
[ "$stats_pct" = "66.7" ] && ok "L: 2/3 completion is 66.7" || notok "L: completion=$stats_pct (want 66.7)"
div=$(checker_divergence "$proj")
[ "$div" = "0" ] && ok "L: FRn.m tracker agrees with tracker-check" || notok "L: tracker-check divergence=$div"
rm -rf "$proj"

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ] || exit 1
exit 0
