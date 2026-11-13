#!/usr/bin/env bash
# shellcheck disable=SC2015   # file-level: `cond && ok … || notok …` is the
# deliberate assertion idiom (ok/notok both exit 0) — see test-check-schema.sh.
# Regression tests for blueprint-autorun-probe.sh (ADR-0020 SessionStart rung).
#
# Pins the semantic contract:
#   - level 0 / missing automation block emits an empty signal (runner never invoked)
#   - BLUEPRINT_AUTORUN_DISABLE=1 emits an empty signal (runner never invoked)
#   - level 1 emits one finding per due agent task, remediation /blueprint:<task>
#   - level 2 emits one aggregated finding, remediation /blueprint:autopilot
#   - TTL cache: a fresh cache re-emits findings WITHOUT re-invoking the runner
#   - a run killed mid-flight (hook timeout) is reported next session as
#     autorun_incomplete, and a completed re-run clears it (#3169)
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
if [ -n "${STUB_HANG:-}" ]; then
    : > "$STUB_HANG"
    sleep 30
fi
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
if [ -n "${STUB_EXTRA:-}" ]; then
    printf '%s\n' "$STUB_EXTRA"
fi
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

# ---- Test H: a run killed by the hook timeout surfaces next session (#3169) ----
# The harness kills the probe when the runner outlives the 5 s SessionStart
# budget, so the killed session can report nothing. The probe writes a start
# marker before the run and a done marker after it returns; a later session
# that finds the start marker without the done marker reports
# autorun_incomplete, instead of looking identical to "nothing due".
proj=$(make_project 1)
set -m
printf '{"session_id": "sidH", "cwd": "%s"}' "$proj" \
    | env STUB_LOG="$work/stub-invocations" STUB_HANG="$work/hang-mark" \
          CLAUDE_DRIFT_SIGNALS_DIR="$work/signals" \
          CLAUDE_BLUEPRINT_AUTORUN_CACHE_DIR="$work/cache-sidH" \
          BLUEPRINT_AUTORUN_BIN="$STUB" \
          bash "$PROBE" &
probe_pid=$!
set +m
i=0
while [ ! -e "$work/hang-mark" ] && [ "$i" -lt 100 ]; do
    sleep 0.1
    i=$((i + 1))
done
if [ -e "$work/hang-mark" ]; then
    kill -TERM -- "-$probe_pid" 2>/dev/null
    wait "$probe_pid" 2>/dev/null
    ok "H: probe killed while the runner was still running"
else
    notok "H: runner never started"
    wait "$probe_pid" 2>/dev/null
fi
rm -rf "$work/signals"
before_runs=$(stub_count)
run_probe "$proj" sidH
sig=$(signal_file sidH)
[ "$(stub_count)" = "$before_runs" ] && ok "H: fresh cache, runner not re-invoked" || notok "H: runner re-invoked ($(stub_count))"
kindh=$(jq -r '[.findings[].kind] | join(",")' "$sig" 2>/dev/null)
[ "$kindh" = "autorun_incomplete" ] && ok "H: next session reports autorun_incomplete" \
    || notok "H: findings after a killed run: '$kindh'"
remh=$(jq -r '.findings[0].remediation_skill' "$sig" 2>/dev/null)
[ "$remh" = "/blueprint:sync-ids" ] && ok "H: remediation is /blueprint:sync-ids" || notok "H: remediation=$remh"

# A run that completes clears the incomplete state.
touch -t 202001010000 "$work/cache-sidH/"*.out
rm -rf "$work/signals"
run_probe "$proj" sidH
sig=$(signal_file sidH)
kindh=$(jq -r '[.findings[].kind] | join(",")' "$sig" 2>/dev/null)
[ "$kindh" = "task_due,task_due" ] && ok "H: a completed re-run clears autorun_incomplete" \
    || notok "H: findings after a completed re-run: '$kindh'"
rm -rf "$proj"

# ---- Test I: registry writes and task errors reach the session (#3551) ----
# The probe sent runner stdout to a cache file, so the sync-ids CHANGED= line
# never reached the session: a session starting with a modified manifest had
# no explanation for it.
kinds_of() { jq -r '[.findings[].kind] | join(",")' "$(signal_file "$1")" 2>/dev/null; }
count_kind() { jq --arg k "$2" '[.findings[] | select(.kind == $k)] | length' "$(signal_file "$1")" 2>/dev/null; }
proj=$(make_project 1)
run_probe "$proj" sidI STUB_EXTRA="TASK=sync-ids KIND=deterministic SCHEDULE=on-change STATE=ran DOCS=3 CHANGED=true"
[ "$(count_kind sidI registry_reconciled)" = "1" ] && ok "I: CHANGED=true emits exactly one registry_reconciled" \
    || notok "I: registry_reconciled findings: $(kinds_of sidI)"
rem=$(jq -r '.findings[] | select(.kind == "registry_reconciled") | .remediation_skill' "$(signal_file sidI)")
[ "$rem" = "commit docs/blueprint/manifest.json" ] && ok "I: remediation is to commit the manifest" || notok "I: remediation=$rem"

# A second probe within the TTL re-reads the fresh cache: no repeat.
rm -rf "$work/signals"
run_probe "$proj" sidI STUB_EXTRA="TASK=sync-ids KIND=deterministic SCHEDULE=on-change STATE=ran DOCS=3 CHANGED=true"
[ "$(count_kind sidI registry_reconciled)" = "0" ] && ok "I: a TTL-fresh cache emits no registry_reconciled" \
    || notok "I: registry_reconciled repeated from the cache: $(kinds_of sidI)"
rm -rf "$proj"

proj=$(make_project 1)
run_probe "$proj" sidJ STUB_EXTRA="TASK=sync-ids KIND=deterministic SCHEDULE=on-change STATE=error"
[ "$(count_kind sidJ autorun_task_error)" = "1" ] && ok "I: STATE=error emits autorun_task_error" \
    || notok "I: autorun_task_error findings: $(kinds_of sidJ)"
summary=$(jq -r '.findings[] | select(.kind == "autorun_task_error") | .summary' "$(signal_file sidJ)")
case "$summary" in *sync-ids*) ok "I: autorun_task_error names the task" ;; *) notok "I: summary=$summary" ;; esac
rm -rf "$proj"

proj=$(make_project 1)
run_probe "$proj" sidK STUB_EXTRA="TASK=sync-ids KIND=deterministic SCHEDULE=on-change STATE=ran DOCS=3 CHANGED=false"
[ "$(kinds_of sidK)" = "task_due,task_due" ] && ok "I: CHANGED=false emits no new finding" \
    || notok "I: CHANGED=false findings: $(kinds_of sidK)"
rm -rf "$proj"

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ] || exit 1
exit 0
