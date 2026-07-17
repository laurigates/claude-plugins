#!/usr/bin/env bash
# test-scheduled-reconcile.sh — regression tests for the scheduled-reconcile
# cadence wrapper (issue #1793) and reconcile.sh's --only-verdicts apply gate.
#
# Pins:
#   A. reconcile.sh --only-verdicts limits the APPLY set — with
#      --apply --only-verdicts=pr-merged,issue-closed only those two verdicts
#      are closed; a pr-closed task and an UNKNOWN-upstream task are NEVER
#      closed (UNKNOWN is verdict=live, so this only narrows the set).
#   B. reconcile.sh --apply WITHOUT --only-verdicts still closes every stale
#      verdict (back-compat; the flag must be opt-in).
#   C. scheduled-reconcile notify-only default mutates nothing (reconcile is
#      invoked WITHOUT --apply) and fires the notifier on STALE_COUNT>0.
#   D. GH_AVAILABLE=false suppresses the notification (never act on uncertainty).
#   E. the opt-out env var makes the wrapper a no-op (reconcile never invoked).
#   F. scheduled-reconcile --apply delegates with --apply AND the bounded
#      --only-verdicts=pr-merged,issue-closed allowlist.
#   G. reconcile.sh REJECTS an unknown argument (exit 2, error on stderr,
#      nothing mutated). Guards issue #2057: a silent `*) ;;` catch-all
#      swallowed a misspelled/unsupported --only-verdicts under version skew,
#      turning the bounded apply into an unbounded one that closed pr-closed
#      tasks the flag exists to protect.
#
# `task` and `gh` are pure stubs; no network, no real taskwarrior store.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RECONCILE="${SCRIPT_DIR}/../../skills/task-reconcile/scripts/reconcile.sh"
WRAPPER="${SCRIPT_DIR}/../scheduled-reconcile.sh"

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
[ -f "$RECONCILE" ] || { echo "missing reconcile: $RECONCILE" >&2; exit 1; }
[ -f "$WRAPPER" ]   || { echo "missing wrapper: $WRAPPER" >&2; exit 1; }

WORK="$(mktemp -d)"
[ -n "$WORK" ] || { echo "mktemp failed" >&2; exit 1; }
trap 'rm -rf "$WORK"' EXIT

BIN="${WORK}/bin"
mkdir -p "$BIN"
IMPORT_CAPTURE="${WORK}/import.json"

UA="aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa"  # ghpr 10 → MERGED   → pr-merged   (closeable)
UB="bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb"  # ghpr 11 → CLOSED   → pr-closed   (keep)
UC="cccccccc-cccc-cccc-cccc-cccccccccccc"  # ghid 20 → CLOSED   → issue-closed(closeable)
UD="dddddddd-dddd-dddd-dddd-dddddddddddd"  # ghpr 12 → ""       → UNKNOWN→live(never stale)

# Stub `task`:
#   * `import`            → capture stdin, succeed.
#   * `... +BLOCKING ...` → []   (nothing blocks, so every stale → bulk path).
#   * `... export ...`    → the four-task linked snapshot.
cat > "${BIN}/task" <<SH
#!/usr/bin/env bash
for a in "\$@"; do [ "\$a" = "import" ] && { cat > "${IMPORT_CAPTURE}"; exit 0; }; done
for a in "\$@"; do [ "\$a" = "+BLOCKING" ] && { echo "[]"; exit 0; }; done
cat <<'JSON'
[{"id":1,"uuid":"${UA}","project":"alpha","ghpr":"10"},
 {"id":2,"uuid":"${UB}","project":"alpha","ghpr":"11"},
 {"id":3,"uuid":"${UC}","project":"beta","ghid":"20"},
 {"id":4,"uuid":"${UD}","project":"beta","ghpr":"12"}]
JSON
SH
chmod +x "${BIN}/task"

# Stub `gh`: auth OK; PR/issue states by number; #12 returns empty → UNKNOWN.
cat > "${BIN}/gh" <<'SH'
#!/usr/bin/env bash
case "$1 $2" in
  "auth status") exit 0 ;;
  "pr view")   case "$3" in 10) echo MERGED ;; 11) echo CLOSED ;; *) echo "" ;; esac ;;
  "issue view") case "$3" in 20) echo CLOSED ;; *) echo OPEN ;; esac ;;
esac
exit 0
SH
chmod +x "${BIN}/gh"

run_reconcile() { PATH="${BIN}:$PATH" bash "$RECONCILE" --all "$@" 2>/dev/null; }
field() { printf '%s\n' "$2" | grep -m1 "^$1=" | cut -d= -f2-; }

# --- A: --only-verdicts limits the apply set --------------------------------
: > "$IMPORT_CAPTURE"
out=$(run_reconcile --apply --only-verdicts=pr-merged,issue-closed)
check "A: ONLY_VERDICTS echoed" "pr-merged,issue-closed" "$(field ONLY_VERDICTS "$out")"
check "A: STALE_COUNT counts all 3 non-live" "3" "$(field STALE_COUNT "$out")"
check "A: CLOSED_COUNT only the 2 allowlisted" "2" "$(field CLOSED_COUNT "$out")"
imported_uuids=$(jq -r '.[].uuid' "$IMPORT_CAPTURE" 2>/dev/null | sort | tr '\n' ' ')
check "A: import payload = pr-merged + issue-closed only" "${UA} ${UC} " \
  "$(printf '%s\n' "$UA" "$UC" | sort | tr '\n' ' ')"
check "A: imported exactly those two uuids" "${UA} ${UC} " "$imported_uuids"
# pr-closed (UB) and unknown→live (UD) must be absent from the import payload.
check "A: pr-closed NOT closed" "0" "$(jq --arg u "$UB" '[.[]|select(.uuid==$u)]|length' "$IMPORT_CAPTURE" 2>/dev/null)"
check "A: unknown→live NOT closed" "0" "$(jq --arg u "$UD" '[.[]|select(.uuid==$u)]|length' "$IMPORT_CAPTURE" 2>/dev/null)"
# The pr-closed task is reported (method=keep), not silently dropped.
check "A: pr-closed reported method=keep" "keep" \
  "$(printf '%s\n' "$out" | grep "uuid=${UB}" | grep -o 'method=[^ ]*' | cut -d= -f2)"

# --- B: --apply WITHOUT --only-verdicts closes every stale verdict ----------
: > "$IMPORT_CAPTURE"
out=$(run_reconcile --apply)
check "B: ONLY_VERDICTS empty (back-compat)" "" "$(field ONLY_VERDICTS "$out")"
check "B: CLOSED_COUNT all 3 stale" "3" "$(field CLOSED_COUNT "$out")"
check "B: pr-closed IS closed without allowlist" "1" "$(jq --arg u "$UB" '[.[]|select(.uuid==$u)]|length' "$IMPORT_CAPTURE" 2>/dev/null)"
check "B: unknown→live still never closed" "0" "$(jq --arg u "$UD" '[.[]|select(.uuid==$u)]|length' "$IMPORT_CAPTURE" 2>/dev/null)"

# --- G: unknown argument fails fast (issue #2057) ----------------------------
# A caller passing a flag this version doesn't understand (e.g. --only-verdicts
# to a pre-#1793 script, or a typo'd --only-verdictz) must get a loud non-zero
# exit BEFORE any classification/apply — never a silently-unbounded apply.
: > "$IMPORT_CAPTURE"
g_err=$(PATH="${BIN}:$PATH" bash "$RECONCILE" --all --apply --only-verdictz=pr-merged,issue-closed 2>&1 >/dev/null)
g_exit=$?
check "G: unknown flag → exit 2" "2" "$g_exit"
check "G: unknown flag named on stderr" "yes" \
  "$(printf '%s\n' "$g_err" | grep -q 'unknown argument: --only-verdictz' && echo yes || echo no)"
check "G: usage printed on stderr" "yes" \
  "$(printf '%s\n' "$g_err" | grep -q '^usage: reconcile.sh' && echo yes || echo no)"
check "G: nothing imported (no mutation before the reject)" "no" \
  "$([ -s "$IMPORT_CAPTURE" ] && echo yes || echo no)"

# --- Wrapper tests: stub reconcile (records args, emits canned output) -------
RC_ARGS="${WORK}/rc.args"
RC_STUB="${WORK}/reconcile-stub.sh"
NOTIFY_CAPTURE="${WORK}/telegram.txt"
NOTIFY_BIN="${WORK}/telegram-stub.sh"

make_rc_stub() { # make_rc_stub <gh_avail> <stale_count>
  cat > "$RC_STUB" <<SH
#!/usr/bin/env bash
printf '%s\n' "\$@" > "${RC_ARGS}"
echo "=== TASK RECONCILE ==="
echo "GH_AVAILABLE=$1"
echo "TASK id=1 project=alpha uuid=${UA} ghpr=10 upstream=MERGED verdict=pr-merged method=bulk"
echo "TASK id=2 project=alpha uuid=${UB} ghpr=11 upstream=CLOSED verdict=pr-closed method=keep"
echo "TASK id=3 project=beta uuid=${UC} ghid=20 upstream=CLOSED verdict=issue-closed method=bulk"
echo "STALE_COUNT=$2"
echo "CLOSED_COUNT=2"
echo "STATUS=OK"
echo "=== END TASK RECONCILE ==="
SH
  chmod +x "$RC_STUB"
}

cat > "$NOTIFY_BIN" <<SH
#!/usr/bin/env bash
printf '%s' "\$1" > "${NOTIFY_CAPTURE}"
SH
chmod +x "$NOTIFY_BIN"

run_wrapper() { # run_wrapper <extra wrapper args...>
  TW_RECONCILE_SCRIPT="$RC_STUB" \
  TW_RECONCILE_TELEGRAM_BIN="$NOTIFY_BIN" \
  bash "$WRAPPER" --no-desktop "$@" 2>/dev/null
}

# --- C: notify-only default mutates nothing + notifies on stale>0 -----------
make_rc_stub true 3
: > "$RC_ARGS"; rm -f "$NOTIFY_CAPTURE"
out=$(run_wrapper)
check "C: mode notify-only" "notify-only" "$(field MODE "$out")"
check "C: notified" "true" "$(field NOTIFIED "$out")"
check "C: telegram fired" "yes" "$([ -s "$NOTIFY_CAPTURE" ] && echo yes || echo no)"
check "C: reconcile invoked WITHOUT --apply (mutates nothing)" "no" \
  "$(grep -qx -- '--apply' "$RC_ARGS" && echo yes || echo no)"
check "C: per-project breakdown present" "yes" \
  "$(printf '%s\n' "$out" | grep -q '^PROJECT_BREAKDOWN=.*alpha=' && echo yes || echo no)"

# --- D: GH_AVAILABLE=false suppresses notification --------------------------
make_rc_stub false 3
rm -f "$NOTIFY_CAPTURE"
out=$(run_wrapper)
check "D: gh unavailable → not notified" "false" "$(field NOTIFIED "$out")"
check "D: gh unavailable → no telegram" "no" "$([ -s "$NOTIFY_CAPTURE" ] && echo yes || echo no)"
check "D: gh unavailable → STATUS OK" "OK" "$(field STATUS "$out")"

# --- D2: no stale → no notification -----------------------------------------
make_rc_stub true 0
rm -f "$NOTIFY_CAPTURE"
out=$(run_wrapper)
check "D2: zero stale → not notified" "false" "$(field NOTIFIED "$out")"
check "D2: zero stale → no telegram" "no" "$([ -s "$NOTIFY_CAPTURE" ] && echo yes || echo no)"

# --- E: opt-out env respected (reconcile never invoked) ---------------------
make_rc_stub true 3
: > "$RC_ARGS"; rm -f "$NOTIFY_CAPTURE"
out=$(CLAUDE_TASKWARRIOR_NO_SCHEDULED_RECONCILE=1 \
  TW_RECONCILE_SCRIPT="$RC_STUB" TW_RECONCILE_TELEGRAM_BIN="$NOTIFY_BIN" \
  bash "$WRAPPER" --no-desktop 2>/dev/null)
check "E: opt-out → SKIPPED" "opt-out" "$(field SKIPPED "$out")"
check "E: opt-out → reconcile NOT invoked" "no" "$([ -s "$RC_ARGS" ] && echo yes || echo no)"
check "E: opt-out → not notified" "false" "$(field NOTIFIED "$out")"

# --- F: --apply delegates with --apply + the bounded allowlist --------------
make_rc_stub true 3
: > "$RC_ARGS"
out=$(run_wrapper --apply)
check "F: mode apply" "apply" "$(field MODE "$out")"
check "F: reconcile got --apply" "yes" "$(grep -qx -- '--apply' "$RC_ARGS" && echo yes || echo no)"
check "F: reconcile got bounded --only-verdicts" "yes" \
  "$(grep -qx -- '--only-verdicts=pr-merged,issue-closed' "$RC_ARGS" && echo yes || echo no)"

# --- Summary ----------------------------------------------------------------
echo "=== SCHEDULED RECONCILE TEST ==="
echo "PASS=${pass}"
echo "FAIL=${fail}"
echo "STATUS=$([ "$fail" -eq 0 ] && echo OK || echo ERROR)"
echo "=== END SCHEDULED RECONCILE TEST ==="
[ "$fail" -eq 0 ]
