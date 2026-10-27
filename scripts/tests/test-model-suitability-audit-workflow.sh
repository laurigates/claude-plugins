#!/usr/bin/env bash
# Regression tests for .claude/workflows/model-suitability-audit.workflow.js,
# the repo-internal harness behind the Haiku 5.5 suitability audit and its
# planned re-run (#3116).
#
#   1. The scale estimator counts both fan-outs (UNBOUNDED=0, ESTIMATE=26):
#      the literal .slice(0, 18) / .slice(0, 8) caps are what bound the run.
#   2. Against a stub runtime (fixtures/model-suitability-audit/run-workflow.mjs):
#      empty or invalid args abort before any agent (the file is runnable by
#      name); a dead or silent classifier leaves files unclassified rather than
#      sampled; a dead or silent verifier is never read as a confirmation; the
#      control sample of keeps is deterministic; the verifier cap reports the
#      remainder as unverified instead of dropping it; an empty list from a
#      non-empty batch counts as a dead agent.
#
# check-workflow-js-model.sh scans only */skills/*/workflows/*.js, so this test
# is also where the explicit model + effort and the structured-output schema on
# every agent() call are pinned.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
root="$(cd "$here/../.." && pwd)"
wf="$root/.claude/workflows/model-suitability-audit.workflow.js"

command -v node >/dev/null || { echo "SKIP: node not installed"; exit 0; }
[[ -f "$wf" ]] || { echo "FAIL workflow missing: $wf"; exit 1; }

status=0
if command -v python3 >/dev/null; then
  est="$(python3 "$root/hooks-plugin/hooks/workflow-scale-estimate.py" < "$wf")"
  if grep -qx 'UNBOUNDED=0' <<<"$est" && grep -qx 'ESTIMATE=26' <<<"$est"; then
    echo "PASS scale estimator counts both fan-outs (ESTIMATE=26, UNBOUNDED=0)"
  else
    echo "FAIL scale estimator: expected ESTIMATE=26 UNBOUNDED=0, got:"; printf '%s\n' "$est"; status=1
  fi
else
  echo "SKIP - python3 not installed: estimator check not run"
fi

node "$here/fixtures/model-suitability-audit/run-workflow.mjs" "$wf" || status=1
exit "$status"
