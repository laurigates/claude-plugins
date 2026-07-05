#!/usr/bin/env bash
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

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ] || exit 1
exit 0
