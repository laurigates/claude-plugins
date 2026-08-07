#!/usr/bin/env bash
# Runner shim for the friction_* Python regression suites.
#
# The suites themselves are Python (`test_friction_*.py`), but
# scripts/run-skill-script-tests.sh (and the `Test: Skill scripts` CI workflow)
# discover only `*-plugin/scripts/tests/test-*.sh`. Without this shim the
# friction parser/cluster regressions ran by hand only — the checks existed but
# nothing fired them, so a regression could land green.
#
# Usage: bash feedback-plugin/scripts/tests/test-friction-parse.sh

set -uo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if ! command -v python3 >/dev/null 2>&1; then
  echo "SKIP: python3 not available"
  exit 0
fi

failed=0
total=0

for suite in "$TESTS_DIR"/test_friction_*.py; do
  [ -f "$suite" ] || continue
  total=$((total + 1))
  echo "=== $(basename "$suite") ==="
  if python3 "$suite"; then
    :
  else
    failed=$((failed + 1))
  fi
done

echo "SUITES=${total}"
echo "FAILED=${failed}"
if [ "$failed" -gt 0 ]; then
  echo "STATUS=ERROR"
  exit 1
fi
echo "STATUS=OK"
exit 0
