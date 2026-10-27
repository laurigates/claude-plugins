#!/usr/bin/env bash
# Behaviour tests for the adversarial-review workflow templates, run against a
# stub runtime (run-template.mjs):
#   find-verify   — cross-lens dedup merges raised_by, the severity rank picks
#                   what the cap verifies, a dead verifier's finding comes back
#                   as `unverified` (the ad-hoc runs dropped it from every
#                   bucket), `unverified` round-trips as `args.claims`, the
#                   control sample and caps are clamped, lens bounds abort
#                   before any agent runs.
#   design-review — Revise reads every review, a dead drafter or reviewer set
#                   never reads as a clean spec, guards abort with zero agents.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
wf="$here/../../workflows"

command -v node >/dev/null || { echo "SKIP: node not installed"; exit 0; }

status=0
for t in find-verify design-review; do
  node "$here/run-template.mjs" "$wf/$t.workflow.js" || status=1
done
exit "$status"
