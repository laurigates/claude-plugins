#!/usr/bin/env bash
# Assert the golden-set sweep cannot report green on a fraction of its canaries
# without saying so.
#
# The defect: `evaluate-plugin/golden-set.json` lists 16 canaries and exactly ONE
# carries an evals.json (measured 2026-09-03). The sweep gate is
# `eval_ready_count != '0'`, and the hard-fail fires only on ZERO enumerated
# canaries -- so a 6% sweep ran, passed, and filed an issue. The ratio existed
# only in $GITHUB_STEP_SUMMARY, which no issue mirrors and nothing persists, and
# the prompt reported a bare "Eval-ready canaries: 1" with no denominator. "1"
# reads as fine; "1 of 16" does not.
#
# Failing on the GAP was rejected: it would be red on arrival for as long as the
# 15 evals take to write, and a permanently-red monthly audit gets switched off.
# So the workflow keeps three properties instead, and this guard pins them:
#
#   1. a declared floor is READ from golden-set.json and a drop below it FAILS
#      (a ratchet -- regression is an error, a standing gap is not)
#   2. a partial sweep emits a ::warning:: naming both numbers
#   3. the denominator reaches the PROMPT, which is what reaches the filed issue
#      -- the only artifact that outlives the run
#
# Output follows .claude/rules/structured-script-output.md.
#
# Usage: check-golden-set-coverage.sh [--project-dir DIR]
# Exit:  0 invariants intact, 1 one is missing, 2 usage error.
set -uo pipefail

ROOT_DIR=""
while [ $# -gt 0 ]; do
  case "$1" in
    --project-dir)
      if [ -z "${2:-}" ] || [ ! -d "${2:-}" ]; then
        echo "check-golden-set-coverage.sh: --project-dir requires a directory" >&2
        exit 2
      fi
      ROOT_DIR="$(cd "$2" && pwd)"; shift 2 ;;
    -h|--help) sed -n '2,25p' "$0"; exit 0 ;;
    *) echo "check-golden-set-coverage.sh: unknown argument: $1" >&2; exit 2 ;;
  esac
done
[ -n "$ROOT_DIR" ] || ROOT_DIR="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
cd "$ROOT_DIR" || exit 2

WF=".github/workflows/golden-set-evaluation.yml"
GS="evaluate-plugin/golden-set.json"

issue_count=0
findings=""
note() { issue_count=$((issue_count + 1)); findings="${findings}  - SEVERITY=ERROR TYPE=$1 MSG=$2
"; }

wf_present=false
gs_present=false
[ -f "$WF" ] && wf_present=true
[ -f "$GS" ] && gs_present=true

ready=0; total=0; floor=0
if [ "$gs_present" = true ]; then
  floor="$(jq -r '.evalCoverageFloor // "absent"' "$GS" 2>/dev/null || echo absent)"
  while IFS= read -r ref; do
    [ -n "$ref" ] || continue
    total=$((total + 1))
    [ -f "${ref%%/*}/skills/${ref##*/}/evals.json" ] && ready=$((ready + 1))
  done < <(jq -r '.canaries[].skill' "$GS" 2>/dev/null || true)

  [ "$floor" = "absent" ] && note "floor_not_declared" \
    "golden-set.json has no evalCoverageFloor; a drop in coverage cannot be detected"
  if [ "$floor" != "absent" ] && [ "$ready" -lt "$floor" ]; then
    note "coverage_below_floor" \
      "$ready of $total canaries carry an evals.json, below the declared floor of $floor"
  fi
fi

if [ "$wf_present" = true ]; then
  grep -q 'evalCoverageFloor' "$WF" || note "floor_not_read" \
    "the workflow never reads evalCoverageFloor, so the ratchet is inert"
  grep -q '::warning::.*canaries' "$WF" || note "no_partial_warning" \
    "a partial sweep emits no ::warning::, so the gap is invisible on the run"
  # The prompt is the only path to the filed issue. A bare ready count there is
  # exactly what made 1-of-16 read as healthy.
  grep -q 'eval_total_count' "$WF" || note "denominator_missing" \
    "eval_total_count never reaches the prompt; the issue reports a count with no denominator"
fi

echo "=== GOLDEN SET COVERAGE ==="
echo "WORKFLOW_PRESENT=$wf_present"
echo "GOLDEN_SET_PRESENT=$gs_present"
echo "CANARIES_TOTAL=$total"
echo "CANARIES_EVAL_READY=$ready"
echo "COVERAGE_FLOOR=$floor"
echo "ISSUE_COUNT=$issue_count"
if [ "$issue_count" -gt 0 ]; then
  echo "STATUS=ERROR"
  echo "ISSUES:"
  printf '%s' "$findings"
else
  echo "STATUS=OK"
fi
echo "=== END GOLDEN SET COVERAGE ==="

[ "$issue_count" -gt 0 ] && exit 1
exit 0
