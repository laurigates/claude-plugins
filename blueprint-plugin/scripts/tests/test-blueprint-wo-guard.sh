#!/usr/bin/env bash
# test-blueprint-wo-guard.sh — regression tests for blueprint-wo-guard.sh, the
# deterministic level-3 gate + execution budget (ADR-0020 level 3).
#
# Pins:
#   1. autorun mode gates on autonomy_level >= 3 only
#   2. wo-execute additionally requires work_orders.auto_execute == true
#   3. per-day budget: ran-today >= max_per_day → HALT (daily_budget_exhausted)
#   4. stuck ceiling: attempts >= max_cycles → STUCK=true → HALT
#   5. manifest defaults (max_per_day 3, max_cycles 3) and flag overrides
#   6. every degraded case (no manifest, no jq path, bad mode) HALTs, exit 0
#      (parallel-safe: the verdict is PROCEED=, not the exit code)
#
# Pure jq/manifest reads — no network, no git.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GUARD="${SCRIPT_DIR}/../blueprint-wo-guard.sh"

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
[ -f "$GUARD" ] || { echo "missing script: $GUARD" >&2; exit 1; }

WORK="$(mktemp -d)"
[ -n "$WORK" ] || { echo "mktemp failed" >&2; exit 1; }
trap 'rm -rf "$WORK"' EXIT

kv() { grep -m1 -E "^$2=" <<<"$1" | cut -d= -f2-; }

mkmanifest() { # mkmanifest <dir> <json>
  mkdir -p "$WORK/$1/docs/blueprint"
  printf '%s' "$2" > "$WORK/$1/docs/blueprint/manifest.json"
}

mkmanifest l3 '{"format_version":"3.4.0","automation":{"autonomy_level":3,"work_orders":{"auto_execute":true}}}'
mkmanifest l3caps '{"automation":{"autonomy_level":3,"work_orders":{"auto_execute":true,"max_per_day":5,"max_cycles":2}}}'
mkmanifest l3noexec '{"automation":{"autonomy_level":3,"work_orders":{"auto_execute":false}}}'
mkmanifest l1 '{"automation":{"autonomy_level":1,"work_orders":{"auto_execute":false}}}'
mkmanifest l0 '{"format_version":"3.4.0"}'

# --- Test 1: autorun gates on level only ---
o=$("$GUARD" --mode autorun --project-dir "$WORK/l3")
check "autorun L3: PROCEED"       "true"                    "$(kv "$o" PROCEED)"
o=$("$GUARD" --mode autorun --project-dir "$WORK/l1")
check "autorun L1: PROCEED"       "false"                   "$(kv "$o" PROCEED)"
check "autorun L1: REASON"        "autonomy_level_below_3"  "$(kv "$o" REASON)"
o=$("$GUARD" --mode autorun --project-dir "$WORK/l3noexec")
check "autorun L3 no-exec: PROCEED (autorun ignores auto_execute)" "true" "$(kv "$o" PROCEED)"

# --- Test 2: wo-execute requires auto_execute ---
o=$("$GUARD" --mode wo-execute --project-dir "$WORK/l3" --ran-today 0 --attempts 0)
check "wo L3+exec fresh: PROCEED" "true"                    "$(kv "$o" PROCEED)"
o=$("$GUARD" --mode wo-execute --project-dir "$WORK/l3noexec")
check "wo L3 no-exec: PROCEED"    "false"                   "$(kv "$o" PROCEED)"
check "wo L3 no-exec: REASON"     "auto_execute_disabled"   "$(kv "$o" REASON)"
o=$("$GUARD" --mode wo-execute --project-dir "$WORK/l1")
check "wo L1: REASON below_3"     "autonomy_level_below_3"  "$(kv "$o" REASON)"

# --- Test 3: per-day budget (default max_per_day 3) ---
o=$("$GUARD" --mode wo-execute --project-dir "$WORK/l3" --ran-today 2 --attempts 0)
check "wo ran-today 2/3: PROCEED" "true"                    "$(kv "$o" PROCEED)"
o=$("$GUARD" --mode wo-execute --project-dir "$WORK/l3" --ran-today 3 --attempts 0)
check "wo ran-today 3/3: PROCEED" "false"                   "$(kv "$o" PROCEED)"
check "wo ran-today 3/3: REASON"  "daily_budget_exhausted"  "$(kv "$o" REASON)"

# --- Test 4: stuck ceiling (default max_cycles 3) ---
o=$("$GUARD" --mode wo-execute --project-dir "$WORK/l3" --ran-today 0 --attempts 3)
check "wo attempts 3/3: STUCK"    "true"                    "$(kv "$o" STUCK)"
check "wo attempts 3/3: PROCEED"  "false"                   "$(kv "$o" PROCEED)"
check "wo attempts 3/3: REASON"   "stuck_max_cycles_reached" "$(kv "$o" REASON)"

# --- Test 5: manifest caps + flag overrides ---
o=$("$GUARD" --mode wo-execute --project-dir "$WORK/l3caps" --ran-today 4 --attempts 0)
check "wo caps max_per_day 5, ran 4: PROCEED" "true"        "$(kv "$o" PROCEED)"
o=$("$GUARD" --mode wo-execute --project-dir "$WORK/l3caps" --ran-today 0 --attempts 2)
check "wo caps max_cycles 2, attempts 2: STUCK" "true"      "$(kv "$o" STUCK)"
# flag override beats manifest: tighten per-day to 1
o=$("$GUARD" --mode wo-execute --project-dir "$WORK/l3" --ran-today 1 --attempts 0 --max-per-day 1)
check "wo override max-per-day 1, ran 1: PROCEED" "false"   "$(kv "$o" PROCEED)"
check "wo override MAX_PER_DAY echoed"            "1"       "$(kv "$o" MAX_PER_DAY)"

# --- Test 6: degraded cases HALT, exit 0 ---
o=$("$GUARD" --mode autorun --project-dir "$WORK/does-not-exist"); rc=$?
check "no manifest: PROCEED"  "false"       "$(kv "$o" PROCEED)"
check "no manifest: REASON"   "no_manifest" "$(kv "$o" REASON)"
check "no manifest: exit 0"   "0"           "$rc"
o=$("$GUARD" --mode bogus --project-dir "$WORK/l3"); rc=$?
check "bad mode: REASON"      "invalid_mode" "$(kv "$o" REASON)"
check "bad mode: exit 0"      "0"            "$rc"
o=$("$GUARD" --mode autorun --project-dir "$WORK/l0")
check "level absent (=0): PROCEED" "false"   "$(kv "$o" PROCEED)"

printf '\n%s: %d passed, %d failed\n' "$(basename "$0")" "$pass" "$fail"
[ "$fail" -eq 0 ]
