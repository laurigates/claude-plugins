#!/usr/bin/env bash
# Regression test for scan-shell.sh.
# Runs the scanner against fixtures/sample.sh and asserts exact counts
# per severity. Any drift in classification rules — allowlist matching,
# high-op promotion, function-scope tracking — will cause this to fail.
#
# Exit code 0 on success, non-zero with a diff on failure.
set -uo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
scanner="$here/scan-shell.sh"
fixture="$here/../fixtures/sample.sh"

if [[ ! -x "$scanner" ]]; then
  echo "FAIL: scanner not executable: $scanner" >&2
  exit 1
fi
if [[ ! -f "$fixture" ]]; then
  echo "FAIL: fixture missing: $fixture" >&2
  exit 1
fi

# Run with --min-severity low so all severities appear in output.
# Capture stdout (findings) and exit code; stderr (summary) is discarded.
output=$(bash "$scanner" "$fixture" --min-severity low 2>/dev/null)
exit_code=$?

high=$(printf '%s\n' "$output" | grep -c '^High|' || true)
med=$(printf '%s\n'  "$output" | grep -c '^Medium|' || true)
low=$(printf '%s\n'  "$output" | grep -c '^Low|' || true)

# Expected from fixtures/sample.sh annotations:
#   Low=2, Medium=3, High=3
#   exit code 2 (High findings present)
expected_high=3
expected_med=3
expected_low=2
expected_exit=2

failed=0
if [[ "$high" -ne "$expected_high" ]]; then
  printf 'FAIL: High count: got %d, expected %d\n' "$high" "$expected_high" >&2
  failed=1
fi
if [[ "$med" -ne "$expected_med" ]]; then
  printf 'FAIL: Medium count: got %d, expected %d\n' "$med" "$expected_med" >&2
  failed=1
fi
if [[ "$low" -ne "$expected_low" ]]; then
  printf 'FAIL: Low count: got %d, expected %d\n' "$low" "$expected_low" >&2
  failed=1
fi
if [[ "$exit_code" -ne "$expected_exit" ]]; then
  printf 'FAIL: exit code: got %d, expected %d\n' "$exit_code" "$expected_exit" >&2
  failed=1
fi

if [[ "$failed" -ne 0 ]]; then
  echo "" >&2
  echo "Scanner output was:" >&2
  printf '%s\n' "$output" >&2
  exit 1
fi

echo "OK: scan-shell.sh fixture (High=$high Medium=$med Low=$low, exit=$exit_code)"
