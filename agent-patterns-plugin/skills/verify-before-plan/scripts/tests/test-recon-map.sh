#!/usr/bin/env bash
# Behaviour tests for workflows/recon-map.workflow.js, run against a stub
# runtime (run-recon-map.mjs). They pin what the harness decides in plain JS:
#   - the unit cap of 10 drops and reports the overflow instead of hiding it;
#   - malformed args abort before any agent is spawned;
#   - gap-fill is capped at 3 and the rest come back as unfilled_gaps;
#   - a dead verifier confirms nothing (every selected item is "unverifiable");
#   - rejected and uncited items never reach the synthesizer;
#   - a haiku lean-reader unit is always re-checked by the opus verifier.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
wf="$here/../../workflows/recon-map.workflow.js"

command -v node >/dev/null || { echo "SKIP: node not installed"; exit 0; }
[[ -f "$wf" ]] || { echo "FAIL recon-map.workflow.js missing at $wf"; exit 1; }

node "$here/run-recon-map.mjs" "$wf"
