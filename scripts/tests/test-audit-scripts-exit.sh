#!/usr/bin/env bash
# Smoke test for the scheduled-audits scripts (scripts/blueprint-health-check.sh
# and scripts/infra-compliance-check.sh).
#
# Guards the class of bug that froze the monthly scheduled-audits.yml jobs:
# under `set -euo pipefail`, both scripts must run to completion and exit 0.
#
# Two footguns motivated this test:
#   1. `((var++))` / `((var += N))` returns exit 1 when the pre-increment value
#      is 0, which `set -e` turns into a silent script-killing abort. Fixed by
#      switching to the assignment form `var=$((var+1))` (always exit 0).
#   2. A `declare -a arr` array with no element ever assigned is treated as
#      UNSET under `set -u`, so a later "${#arr[@]}" / "${arr[@]}" on a still-
#      empty array aborts the script. Fixed by seeding with `arr=()`.
#
# Both bugs are invisible in CI's failure log (the script dies before emitting
# anything), so a positive "exit 0 and produced output" assertion is the only
# reliable regression signal.
set -uo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/../.." && pwd)"

pass_count=0
fail_count=0

assert() {
  # assert <description> <condition-result-string "true"/"false">
  if [ "$2" = "true" ]; then
    pass_count=$((pass_count + 1))
  else
    echo "FAIL: $1" >&2
    fail_count=$((fail_count + 1))
  fi
}

run_audit() {
  # run_audit <label> <script-path> <expected-first-line-substring>
  local label="$1" script="$2" needle="$3"
  local out err audit_status
  out="$(mktemp)"
  err="$(mktemp)"

  bash "$script" >"$out" 2>"$err"
  audit_status=$?

  echo "=== $label ==="
  assert "$label exits 0 under set -euo pipefail" \
    "$([ "$audit_status" -eq 0 ] && echo true || echo false)"
  assert "$label writes nothing to stderr" \
    "$([ ! -s "$err" ] && echo true || echo false)"
  assert "$label produces a non-empty markdown report" \
    "$([ -s "$out" ] && echo true || echo false)"
  assert "$label report contains '$needle'" \
    "$(grep -q "$needle" "$out" && echo true || echo false)"

  if [ "$audit_status" -ne 0 ] && [ -s "$err" ]; then
    echo "  stderr:" >&2
    sed 's/^/    /' "$err" >&2
  fi

  rm -f "$out" "$err"
}

run_audit "blueprint-health-check.sh" \
  "$repo_root/scripts/blueprint-health-check.sh" \
  "Monthly Blueprint Health"

run_audit "infra-compliance-check.sh" \
  "$repo_root/scripts/infra-compliance-check.sh" \
  "Infrastructure Compliance Dashboard"

echo ""
echo "Passed: $pass_count, Failed: $fail_count"
[ "$fail_count" -eq 0 ]
