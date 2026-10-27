#!/usr/bin/env bash
# Behaviour tests for the adversarial-review workflow templates, run against a
# stub runtime (run-template.mjs):
#   find-verify   — cross-lens dedup merges raised_by, a second defect at the
#                   same file:line rides in `also` and splits off as
#                   `unverified` when the verifier calls it distinct, the
#                   severity rank picks what the cap verifies, a dead or
#                   unreproduced verdict comes back as `unverified` (the ad-hoc
#                   runs dropped it from every bucket), `unverified` round-trips
#                   as `args.claims`, null caps mean the default, a missing ref
#                   aborts, verifiers run in waves of ≤ 5, `status` names a dead
#                   finder, lens bounds abort before any agent runs.
#   design-review — Revise reads every review and must return a resolution row
#                   per issue, a dead drafter or reviewer, or a non-sound verdict
#                   with no issue, never reads as a clean spec, guards abort
#                   with zero agents.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
wf="$here/../../workflows"

command -v node >/dev/null || { echo "SKIP: node not installed"; exit 0; }

status=0
for t in find-verify design-review; do
  node "$here/run-template.mjs" "$wf/$t.workflow.js" || status=1
done
exit "$status"
