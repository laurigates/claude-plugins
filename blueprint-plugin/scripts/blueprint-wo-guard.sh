#!/usr/bin/env bash
# blueprint-wo-guard.sh — the ADR-0020 autonomy-level-3 gate + execution budget.
#
# The single deterministic PROCEED/HALT verdict both level-3 workflows consult
# before spending any model tokens. Two modes:
#
#   --mode autorun     : the scheduled pipeline (blueprint-autorun.yml).
#                        PROCEED iff automation.autonomy_level >= 3.
#   --mode wo-execute  : the approved-work-order executor (blueprint-wo-execute.yml).
#                        PROCEED iff level >= 3 AND automation.work_orders.auto_execute
#                        is true AND the run/day budget is not spent AND the
#                        per-order attempt ceiling is not reached (stuck-detection).
#
# Both manifest gates default OFF (missing block == level 0, auto_execute false),
# so a repo only reaches level 3 by explicitly opting in — this repo dogfoods at
# level 1 and this guard is what keeps its own level-3 workflows dormant.
#
# Budgets (loop-integrity: no runaway; see .claude/rules/loop-integrity.md) read
# from the manifest with defaults, overridable by flags:
#   automation.work_orders.max_per_day  (default 3)  — orders per calendar day
#   automation.work_orders.max_cycles   (default 3)  — attempts on ONE order
#                                                      before "stuck -> human"
# The dynamic counts the guard cannot know statelessly are passed in by the
# workflow (computed via gh): --ran-today (orders already executed today) and
# --attempts (prior execution attempts on THIS order). "Same failure N x = stuck"
# is --attempts >= max_cycles.
#
# Output follows .claude/rules/structured-script-output.md. Exit 0 always
# (PROCEED= carries the verdict; a HALT is not a script error — parallel-safe).
#
# Usage: blueprint-wo-guard.sh --mode autorun|wo-execute [--project-dir DIR]
#            [--ran-today N] [--attempts N] [--max-per-day N] [--max-cycles N]

set -u

mode=""
project_dir="."
ran_today=0
attempts=0
override_per_day=""
override_cycles=""

while [ $# -gt 0 ]; do
    case "$1" in
        --mode)        mode="${2:-}"; shift 2 ;;
        --project-dir) project_dir="${2:-.}"; shift 2 ;;
        --ran-today)   ran_today="${2:-0}"; shift 2 ;;
        --attempts)    attempts="${2:-0}"; shift 2 ;;
        --max-per-day) override_per_day="${2:-}"; shift 2 ;;
        --max-cycles)  override_cycles="${2:-}"; shift 2 ;;
        *)             shift ;;
    esac
done

# Coerce numeric inputs; a non-integer becomes 0 (fail-safe, never a huge budget).
intval() { case "${1:-}" in ''|*[!0-9]*) echo 0 ;; *) echo "$1" ;; esac; }
ran_today=$(intval "$ran_today")
attempts=$(intval "$attempts")

section_open() { printf '=== BLUEPRINT WO GUARD ===\n'; }
section_close() { printf '=== END BLUEPRINT WO GUARD ===\n'; }

halt() {
    # halt <reason>
    printf 'PROCEED=false\n'
    printf 'REASON=%s\n' "$1"
    printf 'STATUS=OK\n'
    printf 'ISSUE_COUNT=0\n'
    section_close
    exit 0
}

section_open
printf 'MODE=%s\n' "${mode:-none}"

if [ "$mode" != "autorun" ] && [ "$mode" != "wo-execute" ]; then
    printf 'RAN_TODAY=%s\n' "$ran_today"
    printf 'ATTEMPTS=%s\n' "$attempts"
    halt "invalid_mode"
fi

if ! command -v jq >/dev/null 2>&1; then
    printf 'RAN_TODAY=%s\n' "$ran_today"
    printf 'ATTEMPTS=%s\n' "$attempts"
    halt "jq_unavailable"
fi

manifest=""
if [ -f "${project_dir}/docs/blueprint/manifest.json" ]; then
    manifest="${project_dir}/docs/blueprint/manifest.json"
elif [ -f "${project_dir}/docs/blueprint/.manifest.json" ]; then
    manifest="${project_dir}/docs/blueprint/.manifest.json"
fi

if [ -z "$manifest" ]; then
    printf 'RAN_TODAY=%s\n' "$ran_today"
    printf 'ATTEMPTS=%s\n' "$attempts"
    halt "no_manifest"
fi
printf 'MANIFEST=%s\n' "$manifest"

autonomy_level=$(jq -r '.automation.autonomy_level // 0' "$manifest" 2>/dev/null || echo 0)
autonomy_level=$(intval "$autonomy_level")
printf 'AUTONOMY_LEVEL=%s\n' "$autonomy_level"

# jq's // treats an explicit false as absent — read raw and compare literally.
auto_execute=$(jq -r '.automation.work_orders.auto_execute' "$manifest" 2>/dev/null || echo false)
[ "$auto_execute" = "true" ] || auto_execute=false
printf 'WO_AUTO_EXECUTE=%s\n' "$auto_execute"

# Budget caps: flag override wins, else manifest, else default.
manifest_num() { # manifest_num <jsonpath> <default>
    local v
    v=$(jq -r "$1 // empty" "$manifest" 2>/dev/null || echo "")
    case "$v" in ''|*[!0-9]*) echo "$2" ;; *) echo "$v" ;; esac
}
max_per_day=$(intval "${override_per_day:-$(manifest_num '.automation.work_orders.max_per_day' 3)}")
max_cycles=$(intval "${override_cycles:-$(manifest_num '.automation.work_orders.max_cycles' 3)}")

printf 'RAN_TODAY=%s\n' "$ran_today"
printf 'ATTEMPTS=%s\n' "$attempts"
printf 'MAX_PER_DAY=%s\n' "$max_per_day"
printf 'MAX_CYCLES=%s\n' "$max_cycles"

# --- Gate: autonomy level (both modes) ---
if [ "$autonomy_level" -lt 3 ]; then
    printf 'STUCK=false\n'
    halt "autonomy_level_below_3"
fi

if [ "$mode" = "autorun" ]; then
    printf 'STUCK=false\n'
    printf 'PROCEED=true\n'
    printf 'REASON=ok\n'
    printf 'STATUS=OK\n'
    printf 'ISSUE_COUNT=0\n'
    section_close
    exit 0
fi

# --- wo-execute additional gates ---
if [ "$auto_execute" != "true" ]; then
    printf 'STUCK=false\n'
    halt "auto_execute_disabled"
fi

# Stuck-detection ceiling: this order has been attempted too many times.
stuck=false
[ "$attempts" -ge "$max_cycles" ] && stuck=true
printf 'STUCK=%s\n' "$stuck"
if [ "$stuck" = true ]; then
    halt "stuck_max_cycles_reached"
fi

# Per-day budget: orders already executed today at/over the cap.
if [ "$ran_today" -ge "$max_per_day" ]; then
    halt "daily_budget_exhausted"
fi

printf 'PROCEED=true\n'
printf 'REASON=ok\n'
printf 'STATUS=OK\n'
printf 'ISSUE_COUNT=0\n'
section_close
exit 0
