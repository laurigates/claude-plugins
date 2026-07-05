#!/usr/bin/env bash
# Regression tests for blueprint-autorun-probe.sh (ADR-0020 SessionStart rung).
#
# Pins the semantic contract:
#   - level 0 / missing automation block emits an empty signal (runner never invoked)
#   - BLUEPRINT_AUTORUN_DISABLE=1 emits an empty signal (runner never invoked)
#   - level 1 emits one finding per due agent task, remediation /blueprint:<task>
#   - level 2 emits one aggregated finding, remediation /blueprint:autopilot
#   - TTL cache: a fresh cache re-emits findings WITHOUT re-invoking the runner
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROBE="${SCRIPT_DIR}/blueprint-autorun-probe.sh"

pass=0
fail=0
ok() { pass=$((pass + 1)); printf 'ok   - %s\n' "$1"; }
notok() { fail=$((fail + 1)); printf 'FAIL - %s\n' "$1"; }

work=$(mktemp -d)
if [ -z "$work" ] || [ ! -d "$work" ]; then
    echo "FATAL: mktemp failed" >&2
    exit 1
fi
trap 'rm -f "$work/stub-invocations"; rm -rf "$work"' EXIT

# Stub runner: logs every invocation, prints canned autorun output.
STUB="$work/stub-autorun.sh"
cat > "$STUB" <<'EOF'
#!/usr/bin/env bash
echo "invoked $*" >> "$STUB_LOG"
cat <<'OUT'
=== BLUEPRINT AUTORUN ===
MODE=apply
MANIFEST=docs/blueprint/manifest.json
AUTONOMY_LEVEL=1
TASK=adr-validate KIND=agent SCHEDULE=weekly STATE=due REMEDIATION=/blueprint:adr-validate
TASK=feature-tracker-sync KIND=agent SCHEDULE=daily STATE=due REMEDIATION=/blueprint:feature-tracker-sync
DUE_AGENT_TASKS=adr-validate,feature-tracker-sync
RAN_COUNT=0
STATUS=OK
ISSUE_COUNT=0
=== END BLUEPRINT AUTORUN ===
OUT
EOF
chmod +x "$STUB"

make_project() {
    # make_project <level>  (level "none" omits the automation block)
    local proj lvl="$1"
    proj=$(mktemp -d)
    if [ -z "$proj" ] || [ ! -d "$proj" ]; then
        echo "FATAL: mktemp failed" >&2
        exit 1
    fi
    mkdir -p "$proj/docs/blueprint"
    if [ "$lvl" = "none" ]; then
        printf '{"format_version": "3.3.0", "task_registry": {}}\n' > "$proj/docs/blueprint/manifest.json"
    else
        printf '{"format_version": "3.4.0", "automation": {"autonomy_level": %s}, "task_registry": {}}\n' "$lvl" \
            > "$proj/docs/blueprint/manifest.json"
    fi
    printf '%s' "$proj"
}

run_probe() {
    # run_probe <project_dir> <session_id> [env pairs...]
    local proj="$1" sid="$2"
    shift 2
    printf '{"session_id": "%s", "cwd": "%s"}' "$sid" "$proj" \
        | env STUB_LOG="$work/stub-invocations" \
              CLAUDE_DRIFT_SIGNALS_DIR="$work/signals" \
              CLAUDE_BLUEPRINT_AUTORUN_CACHE_DIR="$work/cache-$sid" \
              BLUEPRINT_AUTORUN_BIN="$STUB" \
              "$@" bash "$PROBE"
}

signal_file() { printf '%s/signals/%s/blueprint-autorun.json' "$work" "$1"; }
stub_count() { wc -l < "$work/stub-invocations" 2>/dev/null | tr -d ' ' || echo 0; }

: > "$work/stub-invocations"

# ---- Test A: level 0 -> empty signal, runner not invoked ----
proj=$(make_project 0)
run_probe "$proj" sidA
sig=$(signal_file sidA)
if [ -f "$sig" ] && [ "$(jq '.findings | length' "$sig")" = "0" ]; then
    ok "A: level 0 emits empty signal"
else
    notok "A: level 0 signal wrong ($(cat "$sig" 2>/dev/null))"
fi
[ "$(stub_count)" = "0" ] && ok "A: runner not invoked at level 0" || notok "A: runner invoked at level 0"
rm -rf "$proj"

# ---- Test B: missing automation block behaves as level 0 ----
proj=$(make_project none)
run_probe "$proj" sidB
sig=$(signal_file sidB)
[ "$(jq '.findings | length' "$sig")" = "0" ] && ok "B: 3.3.0 manifest is a no-op" || notok "B: 3.3.0 manifest produced findings"
[ "$(stub_count)" = "0" ] && ok "B: runner not invoked without automation block" || notok "B: runner invoked without automation block"
rm -rf "$proj"

# ---- Test C: opt-out env -> empty signal, runner not invoked ----
proj=$(make_project 1)
run_probe "$proj" sidC BLUEPRINT_AUTORUN_DISABLE=1
sig=$(signal_file sidC)
[ "$(jq '.findings | length' "$sig")" = "0" ] && ok "C: opt-out emits empty signal" || notok "C: opt-out produced findings"
[ "$(stub_count)" = "0" ] && ok "C: runner not invoked when opted out" || notok "C: runner invoked when opted out"
rm -rf "$proj"

# ---- Test D: level 1 -> per-task findings with /blueprint:<task> remediation ----
proj=$(make_project 1)
run_probe "$proj" sidD
sig=$(signal_file sidD)
n_findings=$(jq '.findings | length' "$sig")
[ "$n_findings" = "2" ] && ok "D: two findings at level 1" || notok "D: findings=$n_findings"
rem1=$(jq -r '.findings[0].remediation_skill' "$sig")
[ "$rem1" = "/blueprint:adr-validate" ] && ok "D: per-task remediation skill" || notok "D: remediation=$rem1"
kind1=$(jq -r '.findings[0].kind' "$sig")
[ "$kind1" = "task_due" ] && ok "D: task_due kind" || notok "D: kind=$kind1"
[ "$(stub_count)" = "1" ] && ok "D: runner invoked once" || notok "D: runner invocations=$(stub_count)"

# ---- Test E: fresh TTL cache -> findings re-emitted, runner NOT re-invoked ----
rm -rf "$work/signals"
run_probe "$proj" sidD
sig=$(signal_file sidD)
[ "$(jq '.findings | length' "$sig")" = "2" ] && ok "E: cached findings re-emitted" || notok "E: cache did not re-emit"
[ "$(stub_count)" = "1" ] && ok "E: runner not re-invoked on fresh cache" || notok "E: runner re-invoked ($(stub_count))"

# ---- Test F: stale cache -> runner re-invoked ----
touch -t 202001010000 "$work/cache-sidD/"*.out
run_probe "$proj" sidD
[ "$(stub_count)" = "2" ] && ok "F: stale cache re-runs runner" || notok "F: invocations=$(stub_count)"
rm -rf "$proj"

# ---- Test G: level 2 -> one aggregated finding -> /blueprint:autopilot ----
proj=$(make_project 2)
run_probe "$proj" sidG
sig=$(signal_file sidG)
[ "$(jq '.findings | length' "$sig")" = "1" ] && ok "G: single aggregated finding at level 2" || notok "G: findings=$(jq '.findings | length' "$sig")"
remg=$(jq -r '.findings[0].remediation_skill' "$sig")
[ "$remg" = "/blueprint:autopilot" ] && ok "G: autopilot remediation at level 2" || notok "G: remediation=$remg"
rm -rf "$proj"

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ] || exit 1
exit 0
