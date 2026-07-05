#!/usr/bin/env bash
# Regression tests for blueprint-autorun.sh (ADR-0020 level-1 runner).
#
# Pins the semantic contract:
#   - no manifest / disabled env / jq path are silent no-ops (exit 0)
#   - level 0 never executes (due deterministic tasks report STATE=due)
#   - level 1 executes a due deterministic task (sync-ids sweep), registers
#     documents in id_registry, and writes back last_completed_at/stats
#   - --report never writes back
#   - agent-judgment due tasks are surfaced in DUE_AGENT_TASKS, never executed
#   - enabled:false always wins over auto_run:true
#   - on-change/on-demand schedules are never runner-due
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AUTORUN="${SCRIPT_DIR}/../blueprint-autorun.sh"

pass=0
fail=0

ok() { pass=$((pass + 1)); printf 'ok   - %s\n' "$1"; }
notok() { fail=$((fail + 1)); printf 'FAIL - %s\n' "$1"; }

assert_contains() {
    # assert_contains <label> <needle> <haystack>
    if printf '%s' "$3" | grep -qF -- "$2"; then
        ok "$1"
    else
        notok "$1 (missing: $2)"
    fi
}

assert_not_contains() {
    if printf '%s' "$3" | grep -qF -- "$2"; then
        notok "$1 (unexpected: $2)"
    else
        ok "$1"
    fi
}

make_sandbox() {
    local sb
    sb=$(mktemp -d)
    if [ -z "$sb" ] || [ ! -d "$sb" ]; then
        echo "FATAL: mktemp failed" >&2
        exit 1
    fi
    printf '%s' "$sb"
}

write_manifest() {
    # write_manifest <dir> <autonomy_level> <sync_auto> <sync_schedule> <sync_last> <sync_enabled>
    local dir="$1" lvl="$2" sync_auto="$3" sync_sched="$4" sync_last="$5" sync_enabled="${6:-true}"
    mkdir -p "$dir/docs/blueprint"
    local last_json="null"
    [ "$sync_last" != "null" ] && last_json="\"$sync_last\""
    cat > "$dir/docs/blueprint/manifest.json" <<EOF
{
  "format_version": "3.4.0",
  "automation": {
    "autonomy_level": $lvl,
    "interaction_mode": "normal",
    "work_orders": { "auto_draft": false, "auto_execute": false }
  },
  "task_registry": {
    "sync-ids": {
      "enabled": $sync_enabled,
      "auto_run": $sync_auto,
      "last_completed_at": $last_json,
      "last_result": null,
      "schedule": "$sync_sched",
      "stats": {}
    },
    "adr-validate": {
      "enabled": true,
      "auto_run": true,
      "last_completed_at": null,
      "last_result": null,
      "schedule": "weekly",
      "stats": {}
    },
    "curate-docs": {
      "enabled": true,
      "auto_run": true,
      "last_completed_at": null,
      "last_result": null,
      "schedule": "on-demand",
      "stats": {}
    },
    "claude-md": {
      "enabled": true,
      "auto_run": true,
      "last_completed_at": null,
      "last_result": null,
      "schedule": "on-change",
      "stats": {}
    }
  }
}
EOF
}

write_doc() {
    # write_doc <dir> <relpath> <id>
    local dir="$1" rel="$2" doc_id="$3"
    mkdir -p "$dir/$(dirname "$rel")"
    cat > "$dir/$rel" <<EOF
---
id: $doc_id
status: Accepted
created: 2026-07-01
---

# Fixture doc $doc_id
EOF
}

# ---- Test A: no manifest -> silent no-op ----
sb=$(make_sandbox)
out=$(bash "$AUTORUN" --project-dir "$sb")
rc=$?
[ "$rc" -eq 0 ] && ok "A: exit 0 without manifest" || notok "A: exit $rc without manifest"
assert_contains "A: reports no_manifest" "AUTORUN=no_manifest" "$out"
rm -rf "$sb"

# ---- Test B: level 0 never executes ----
sb=$(make_sandbox)
write_manifest "$sb" 0 true daily null
write_doc "$sb" "docs/adrs/0001-test.md" "ADR-0001"
out=$(bash "$AUTORUN" --project-dir "$sb")
assert_contains "B: level 0 reports due, does not run" "TASK=sync-ids KIND=deterministic SCHEDULE=daily STATE=due" "$out"
last=$(jq -r '.task_registry["sync-ids"].last_completed_at' "$sb/docs/blueprint/manifest.json")
[ "$last" = "null" ] && ok "B: no writeback at level 0" || notok "B: writeback happened at level 0 ($last)"
rm -rf "$sb"

# ---- Test C: level 1 executes due sync-ids sweep + writeback ----
sb=$(make_sandbox)
write_manifest "$sb" 1 true daily null
write_doc "$sb" "docs/adrs/0001-test.md" "ADR-0001"
write_doc "$sb" "docs/prds/0002-feature.md" "PRD-0002"
out=$(bash "$AUTORUN" --project-dir "$sb")
assert_contains "C: sync-ids ran" "TASK=sync-ids KIND=deterministic SCHEDULE=daily STATE=ran DOCS=2" "$out"
assert_contains "C: ran count" "RAN_COUNT=1" "$out"
reg_path=$(jq -r '.id_registry.documents["ADR-0001"].path' "$sb/docs/blueprint/manifest.json")
[ "$reg_path" = "docs/adrs/0001-test.md" ] && ok "C: ADR registered with relative path" || notok "C: ADR registration ($reg_path)"
last_prd=$(jq -r '.id_registry.last_prd' "$sb/docs/blueprint/manifest.json")
[ "$last_prd" = "2" ] && ok "C: last_prd counter updated" || notok "C: last_prd counter ($last_prd)"
last=$(jq -r '.task_registry["sync-ids"].last_completed_at' "$sb/docs/blueprint/manifest.json")
[ "$last" != "null" ] && ok "C: last_completed_at written" || notok "C: last_completed_at not written"
runs=$(jq -r '.task_registry["sync-ids"].stats.runs' "$sb/docs/blueprint/manifest.json")
[ "$runs" = "1" ] && ok "C: stats.runs incremented" || notok "C: stats.runs ($runs)"

# ---- Test D: fresh last_completed_at -> not due ----
out=$(bash "$AUTORUN" --project-dir "$sb")
assert_contains "D: fresh task not due" "TASK=sync-ids SCHEDULE=daily STATE=not_due" "$out"
rm -rf "$sb"

# ---- Test E: --report never writes back ----
sb=$(make_sandbox)
write_manifest "$sb" 1 true daily null
write_doc "$sb" "docs/adrs/0001-test.md" "ADR-0001"
out=$(bash "$AUTORUN" --project-dir "$sb" --report)
assert_contains "E: report mode reports due" "TASK=sync-ids KIND=deterministic SCHEDULE=daily STATE=due" "$out"
last=$(jq -r '.task_registry["sync-ids"].last_completed_at' "$sb/docs/blueprint/manifest.json")
[ "$last" = "null" ] && ok "E: report mode no writeback" || notok "E: report mode wrote back"
if jq -e '.id_registry' "$sb/docs/blueprint/manifest.json" >/dev/null 2>&1; then
    notok "E: report mode initialized id_registry"
else
    ok "E: report mode left manifest untouched"
fi
rm -rf "$sb"

# ---- Test F: agent-judgment tasks surfaced, never executed ----
sb=$(make_sandbox)
write_manifest "$sb" 1 false daily null
out=$(bash "$AUTORUN" --project-dir "$sb")
assert_contains "F: adr-validate due as agent task" "TASK=adr-validate KIND=agent SCHEDULE=weekly STATE=due REMEDIATION=/blueprint:adr-validate" "$out"
assert_contains "F: DUE_AGENT_TASKS lists adr-validate" "DUE_AGENT_TASKS=adr-validate" "$out"
adr_last=$(jq -r '.task_registry["adr-validate"].last_completed_at' "$sb/docs/blueprint/manifest.json")
[ "$adr_last" = "null" ] && ok "F: agent task not marked completed" || notok "F: agent task falsely completed"
rm -rf "$sb"

# ---- Test G: enabled:false always wins; on-change/on-demand never due ----
sb=$(make_sandbox)
write_manifest "$sb" 1 true daily null false
out=$(bash "$AUTORUN" --project-dir "$sb")
assert_contains "G: disabled task skipped" "TASK=sync-ids STATE=skipped REASON=disabled" "$out"
assert_contains "G: on-demand never due" "TASK=curate-docs SCHEDULE=on-demand STATE=on_demand" "$out"
assert_contains "G: on-change is event-driven" "TASK=claude-md SCHEDULE=on-change STATE=event_driven" "$out"
assert_not_contains "G: curate-docs not in due list" "curate-docs" "$(printf '%s' "$out" | grep '^DUE_AGENT_TASKS=')"
rm -rf "$sb"

# ---- Test H: BLUEPRINT_AUTORUN_DISABLE=1 is a no-op ----
sb=$(make_sandbox)
write_manifest "$sb" 1 true daily null
out=$(BLUEPRINT_AUTORUN_DISABLE=1 bash "$AUTORUN" --project-dir "$sb")
assert_contains "H: env opt-out" "AUTORUN=disabled_by_env" "$out"
last=$(jq -r '.task_registry["sync-ids"].last_completed_at' "$sb/docs/blueprint/manifest.json")
[ "$last" = "null" ] && ok "H: opt-out mutates nothing" || notok "H: opt-out wrote back"
rm -rf "$sb"

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ] || exit 1
exit 0
