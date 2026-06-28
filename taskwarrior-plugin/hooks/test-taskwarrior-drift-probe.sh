#!/usr/bin/env bash
# test-taskwarrior-drift-probe.sh — regression tests for the SessionStart drift
# probe, focused on the stale-linked-task surfacing added for the "drift unless
# swept" follow-up.
#
# The probe classifies stale linked tasks by calling task-reconcile's reconcile.sh
# in dry-run mode, debounced behind a per-project TTL cache so the gh poll runs at
# most once per interval. These tests pin:
#   1. STALE_COUNT>0           → a stale_linked_tasks finding is emitted
#   2. STALE_COUNT=0           → no stale finding
#   3. fresh cache             → reconcile is NOT re-invoked; cached count is used
#   4. stale cache             → reconcile IS invoked and the cache is rewritten
#   5. opt-out env             → no stale finding (UDA check still runs)
#   6. GH_AVAILABLE=false      → no stale finding (never warn on uncertainty)
#   7. UDA drift still surfaces alongside the new check (no regression)
#
# Pure stubs: real `gh`/`task`/reconcile are never touched — the probe's
# TW_DRIFT_* overrides inject fakes and the drift signal dir is redirected.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROBE="${SCRIPT_DIR}/taskwarrior-drift-probe.sh"

pass=0
fail=0
check() { # check <description> <expected> <actual>
    if [ "$2" = "$3" ]; then
        pass=$((pass + 1))
    else
        fail=$((fail + 1))
        printf 'FAIL: %s\n  expected: %s\n  actual:   %s\n' "$1" "$2" "$3" >&2
    fi
}

if ! command -v jq >/dev/null 2>&1; then
    echo "SKIP: jq not available" >&2
    exit 0
fi

WORK="$(mktemp -d)"
[ -n "$WORK" ] || { echo "mktemp failed" >&2; exit 1; }
trap 'rm -rf "$WORK"' EXIT

BIN="${WORK}/bin"
PROJ="${WORK}/proj"
SIGNALS="${WORK}/signals"
CACHE="${WORK}/cache"
mkdir -p "$BIN" "$PROJ" "$SIGNALS" "$CACHE"

# --- Stubs -------------------------------------------------------------------
# task: only needs to exist on PATH (the probe no-ops the whole run if absent).
cat > "${BIN}/task" <<'SH'
#!/usr/bin/env bash
exit 0
SH
# gh: auth status succeeds so the probe proceeds to the reconcile poll.
cat > "${BIN}/gh" <<'SH'
#!/usr/bin/env bash
exit 0
SH
chmod +x "${BIN}/task" "${BIN}/gh"
export PATH="${BIN}:${PATH}"

# Fake reconcile.sh: emits a controlled dry-run result and records that it ran.
FAKE_RECONCILE="${WORK}/fake-reconcile.sh"
cat > "$FAKE_RECONCILE" <<'SH'
#!/usr/bin/env bash
# Records invocation (proves the debounce skipped/ran) then emits a controlled
# structured result driven by FAKE_GH_AVAILABLE / FAKE_STALE.
: > "${RECONCILE_RAN_MARKER:-/dev/null}"
echo "=== TASK RECONCILE ==="
echo "GH_AVAILABLE=${FAKE_GH_AVAILABLE:-true}"
echo "STALE_COUNT=${FAKE_STALE:-0}"
echo "STATUS=OK"
echo "=== END TASK RECONCILE ==="
exit 0
SH
chmod +x "$FAKE_RECONCILE"

# Fake resolve-project.sh: fixed project name so the cache path is predictable.
FAKE_RESOLVE="${WORK}/fake-resolve.sh"
cat > "$FAKE_RESOLVE" <<'SH'
#!/usr/bin/env bash
echo "PROJECT=testproj"
SH
chmod +x "$FAKE_RESOLVE"

# Fake ensure-udas.sh: controlled UDA-missing report driven by FAKE_UDAS_MISSING.
FAKE_UDAS="${WORK}/fake-ensure-udas.sh"
cat > "$FAKE_UDAS" <<'SH'
#!/usr/bin/env bash
echo "UDAS_MISSING=${FAKE_UDAS_MISSING:-0}"
echo "MISSING_NAMES=${FAKE_UDAS_NAMES:-}"
SH
chmod +x "$FAKE_UDAS"

# A HOME with a .taskrc so the probe does not no-op as "user doesn't use task".
FAKE_HOME="${WORK}/home"
mkdir -p "$FAKE_HOME"
: > "${FAKE_HOME}/.taskrc"

CACHE_FILE="${CACHE}/testproj.stale"

# run_probe — invokes the probe with a fresh signal dir and returns the
# space-separated list of finding kinds via stdout. Env overrides come from the
# caller's environment (FAKE_STALE, etc.).
run_probe() {
    rm -rf "${SIGNALS:?}"/* 2>/dev/null || true
    printf '{"session_id":"testsess","cwd":"%s"}' "$PROJ" \
        | HOME="$FAKE_HOME" \
          CLAUDE_DRIFT_SIGNALS_DIR="$SIGNALS" \
          CLAUDE_TASKWARRIOR_DRIFT_CACHE_DIR="$CACHE" \
          TW_DRIFT_RECONCILE_SCRIPT="$FAKE_RECONCILE" \
          TW_DRIFT_RESOLVE_SCRIPT="$FAKE_RESOLVE" \
          TW_DRIFT_ENSURE_UDAS="$FAKE_UDAS" \
          bash "$PROBE" >/dev/null 2>&1
    local sig="${SIGNALS}/testsess/taskwarrior-plugin.json"
    [ -f "$sig" ] || { echo "__NO_SIGNAL_FILE__"; return; }
    jq -r '[.findings[].kind] | join(" ")' "$sig" 2>/dev/null
}

now() { date +%s; }
seed_cache() { printf 'EPOCH=%s\nSTALE=%s\n' "$1" "$2" > "$CACHE_FILE"; }

# --- Test 1: STALE_COUNT>0 → stale finding -----------------------------------
rm -f "$CACHE_FILE"
RECONCILE_RAN="${WORK}/ran1"; rm -f "$RECONCILE_RAN"
out=$(RECONCILE_RAN_MARKER="$RECONCILE_RAN" FAKE_STALE=4 FAKE_UDAS_MISSING=0 run_probe)
case " $out " in *" stale_linked_tasks "*) got=yes ;; *) got=no ;; esac
check "stale_count>0 emits stale_linked_tasks finding" "yes" "$got"
check "test1: reconcile ran (cold cache)" "ran" "$([ -f "$RECONCILE_RAN" ] && echo ran || echo no)"

# --- Test 2: STALE_COUNT=0 → no stale finding --------------------------------
rm -f "$CACHE_FILE"
out=$(FAKE_STALE=0 FAKE_UDAS_MISSING=0 run_probe)
case " $out " in *" stale_linked_tasks "*) got=yes ;; *) got=no ;; esac
check "stale_count=0 emits no stale finding" "no" "$got"

# --- Test 3: fresh cache → reconcile NOT re-invoked, cached count used --------
seed_cache "$(now)" 7
RECONCILE_RAN="${WORK}/ran3"; rm -f "$RECONCILE_RAN"
out=$(RECONCILE_RAN_MARKER="$RECONCILE_RAN" FAKE_STALE=0 FAKE_UDAS_MISSING=0 run_probe)
case " $out " in *" stale_linked_tasks "*) got=yes ;; *) got=no ;; esac
check "fresh cache surfaces cached stale (7) despite fake reporting 0" "yes" "$got"
check "fresh cache does NOT re-invoke reconcile" "skipped" \
    "$([ -f "$RECONCILE_RAN" ] && echo ran || echo skipped)"

# --- Test 4: stale cache → reconcile invoked, cache rewritten -----------------
seed_cache 100 9   # epoch 100 = ancient → far older than the 4h TTL
RECONCILE_RAN="${WORK}/ran4"; rm -f "$RECONCILE_RAN"
out=$(RECONCILE_RAN_MARKER="$RECONCILE_RAN" FAKE_STALE=2 FAKE_UDAS_MISSING=0 run_probe)
check "stale cache re-invokes reconcile" "ran" \
    "$([ -f "$RECONCILE_RAN" ] && echo ran || echo no)"
check "stale cache rewritten with fresh count" "2" "$(grep -m1 '^STALE=' "$CACHE_FILE" | cut -d= -f2)"

# --- Test 5: opt-out env suppresses the poll (UDA check still runs) -----------
rm -f "$CACHE_FILE"
RECONCILE_RAN="${WORK}/ran5"; rm -f "$RECONCILE_RAN"
out=$(CLAUDE_TASKWARRIOR_DRIFT_NO_RECONCILE=1 RECONCILE_RAN_MARKER="$RECONCILE_RAN" \
    FAKE_STALE=5 FAKE_UDAS_MISSING=2 FAKE_UDAS_NAMES="ghid,ghpr" run_probe)
case " $out " in *" stale_linked_tasks "*) got_stale=yes ;; *) got_stale=no ;; esac
case " $out " in *" udas_missing "*) got_uda=yes ;; *) got_uda=no ;; esac
check "opt-out: no stale finding" "no" "$got_stale"
check "opt-out: reconcile never runs" "skipped" \
    "$([ -f "$RECONCILE_RAN" ] && echo ran || echo skipped)"
check "opt-out: UDA check still surfaces drift" "yes" "$got_uda"

# --- Test 6: GH_AVAILABLE=false → no stale finding (uncertainty) --------------
rm -f "$CACHE_FILE"
out=$(FAKE_GH_AVAILABLE=false FAKE_STALE=8 FAKE_UDAS_MISSING=0 run_probe)
case " $out " in *" stale_linked_tasks "*) got=yes ;; *) got=no ;; esac
check "GH_AVAILABLE=false suppresses stale finding" "no" "$got"

# --- Test 7: UDA drift + stale drift coexist (no regression) -----------------
rm -f "$CACHE_FILE"
out=$(FAKE_STALE=3 FAKE_UDAS_MISSING=1 FAKE_UDAS_NAMES="ghid" run_probe)
case " $out " in *" stale_linked_tasks "*) s=yes ;; *) s=no ;; esac
case " $out " in *" udas_missing "*) u=yes ;; *) u=no ;; esac
check "coexist: stale finding present" "yes" "$s"
check "coexist: uda finding present" "yes" "$u"

# --- Test 8: the on-exit gh-sync queue is drained before the stale-check ------
# A fresh cache would normally skip the reconcile poll. The drain busts the
# cache for the queued task's project FIRST, so the stale-check re-polls in the
# same run (issue #1810). Inject a drain script that removes the cache file, and
# confirm a fresh-cache run still re-invokes reconcile.
FAKE_DRAIN="${WORK}/fake-drain.sh"
cat > "$FAKE_DRAIN" <<'SH'
#!/usr/bin/env bash
# Stand-in drain: bust the project cache so the stale-check re-polls this run.
: > "${DRAIN_RAN_MARKER:-/dev/null}"
rm -f "${CLAUDE_TASKWARRIOR_DRIFT_CACHE_DIR}/testproj.stale" 2>/dev/null || true
SH
chmod +x "$FAKE_DRAIN"

run_probe_drain() {
    rm -rf "${SIGNALS:?}"/* 2>/dev/null || true
    printf '{"session_id":"testsess","cwd":"%s"}' "$PROJ" \
        | HOME="$FAKE_HOME" \
          CLAUDE_DRIFT_SIGNALS_DIR="$SIGNALS" \
          CLAUDE_TASKWARRIOR_DRIFT_CACHE_DIR="$CACHE" \
          TW_DRIFT_RECONCILE_SCRIPT="$FAKE_RECONCILE" \
          TW_DRIFT_RESOLVE_SCRIPT="$FAKE_RESOLVE" \
          TW_DRIFT_ENSURE_UDAS="$FAKE_UDAS" \
          TW_DRIFT_DRAIN_SCRIPT="$FAKE_DRAIN" \
          bash "$PROBE" >/dev/null 2>&1
}

seed_cache "$(now)" 0          # fresh cache → would normally skip reconcile
DRAIN_RAN="${WORK}/drainran"; rm -f "$DRAIN_RAN"
RECONCILE_RAN="${WORK}/ran8"; rm -f "$RECONCILE_RAN"
DRAIN_RAN_MARKER="$DRAIN_RAN" RECONCILE_RAN_MARKER="$RECONCILE_RAN" \
    FAKE_STALE=1 FAKE_UDAS_MISSING=0 run_probe_drain
check "drain runs at session start" "ran" \
    "$([ -f "$DRAIN_RAN" ] && echo ran || echo no)"
check "drain busting the cache forces reconcile despite a fresh cache" "ran" \
    "$([ -f "$RECONCILE_RAN" ] && echo ran || echo no)"

# Opt-out suppresses the drain.
seed_cache "$(now)" 0
DRAIN_RAN="${WORK}/drainran2"; rm -f "$DRAIN_RAN"
CLAUDE_TASKWARRIOR_NO_GHSYNC_QUEUE=1 DRAIN_RAN_MARKER="$DRAIN_RAN" \
    RECONCILE_RAN_MARKER="${WORK}/ran8b" FAKE_STALE=1 FAKE_UDAS_MISSING=0 run_probe_drain
check "opt-out env suppresses the drain" "skipped" \
    "$([ -f "$DRAIN_RAN" ] && echo ran || echo skipped)"

# --- Summary -----------------------------------------------------------------
echo "=== TASKWARRIOR DRIFT PROBE TEST ==="
echo "PASS=${pass}"
echo "FAIL=${fail}"
echo "STATUS=$([ "$fail" -eq 0 ] && echo OK || echo ERROR)"
echo "=== END TASKWARRIOR DRIFT PROBE TEST ==="
[ "$fail" -eq 0 ]
