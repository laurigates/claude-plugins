#!/usr/bin/env bash
# Behaviour tests for workflows/recon-map.workflow.js, run against a stub
# runtime (run-recon-map.mjs). They pin what the harness decides in plain JS:
#   - the unit cap of 10 drops and reports the overflow instead of hiding it;
#   - malformed args abort before any agent is spawned;
#   - gap-fill is capped at 3 and the rest come back as unfilled_gaps;
#   - a dead verifier confirms nothing (every selected item is "unverifiable");
#   - rejected and uncited items never reach the synthesizer;
#   - a haiku lean-reader unit is always re-checked by the opus verifier;
#   - the literal fan-out slices equal MAX_UNITS / MAX_GAPFILL (static: the
#     scale guard counts the literal, so a drift between the two is invisible
#     to any stub run).
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
wf="$here/../../workflows/recon-map.workflow.js"

command -v node >/dev/null || { echo "SKIP: node not installed"; exit 0; }
[[ -f "$wf" ]] || { echo "FAIL recon-map.workflow.js missing at $wf"; exit 1; }

# cap_pair <constant> <slice expression prefix>: the constant and every literal
# slice bound (code and comments alike) must be the same number.
cap_pair() {
  local const lit
  const="$(sed -nE "s/^const $1 = ([0-9]+).*/\1/p" "$wf")"
  lit="$(grep -oE "$2\.slice\(0, [0-9]+\)" "$wf" | grep -oE '[0-9]+\)$' | tr -d ')' | sort -u | paste -sd, -)"
  if [[ -n "$const" && "$const" == "$lit" ]]; then
    echo "PASS recon-map.workflow.js $1 ($const) equals the literal $2.slice(0, $lit)"
  else
    echo "FAIL recon-map.workflow.js $1 (${const:-missing}) differs from the literal $2.slice(0, ${lit:-missing})"
    return 1
  fi
}
static_rc=0
cap_pair MAX_UNITS 'UNITS' || static_rc=1
cap_pair MAX_GAPFILL 'toFill' || static_rc=1

node "$here/run-recon-map.mjs" "$wf"
exit "$static_rc"
