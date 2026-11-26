#!/usr/bin/env bash
# __QUESTION__
# Ref: __REF__
set -uo pipefail
cd "$(dirname "$0")"
PROBE_DIR="$(pwd)"
PROBE_NAME="__NAME__"
PROBE_REF="__REF__"
REQUIRES_OS="__OS__"
# shellcheck source=/dev/null
. "$PROBE_DIR/../lib/report.sh"

probe_start
need jq

section RESULTS
# Control arm: a case whose outcome is known. If it does not behave as expected,
# the test arm proves nothing, so the verdict is INCONCLUSIVE.
control_ok=0
# ... run the control, write raw output to "$RESULTS/control.*", set control_ok=1 on the expected outcome
log "control: OK=$control_ok"

# Test arm: the case under question.
test_outcome=""
# ... run the test, write raw output to "$RESULTS/test.*", set test_outcome
log "test: OUTCOME=${test_outcome:-none}"

if [ "$control_ok" != "1" ]; then
  verdict INCONCLUSIVE "control did not behave as expected; see results/. Next: fix the setup."
fi
case "$test_outcome" in
  __CODES_CASE__
  *) verdict INCONCLUSIVE "test arm decided nothing; see results/." ;;
esac
