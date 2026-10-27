#!/usr/bin/env bash
# Regression tests for workflows/survivor-triage.workflow.js, run against a stub
# runtime (run-survivor-triage.mjs). They pin the two behaviours the ad-hoc runs
# this template replaces got wrong or lacked:
#   1. The verifier cap is spent on the highest-severity claims across ALL
#      clusters, after a barrier. The ad-hoc runs pipelined triage into verify
#      with a shared slot counter, so the cap went to whichever cluster finished
#      first, and a follow-up run had to verify the claims it dropped.
#   2. Every claim the cap (or a dead skeptic) leaves behind comes back in
#      `unverified`, shaped so it can be passed straight back as `args.claims`.
# Plus refute-by-default (held needs a reproduction), the closed kind/verdict
# schemas on every agent call, the static-mutant filter in every triage brief,
# each duplicated ceiling (MAX_CLUSTERS/slice(0, 8), VERIFY_MAX/slice(0, 6))
# tested on its own, and zero-agent aborts, including malformed `clusters`.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
wf="$here/../../workflows/survivor-triage.workflow.js"

command -v node >/dev/null || { echo "SKIP: node not installed"; exit 0; }
[[ -f "$wf" ]] || { echo "FAIL template missing: $wf"; exit 1; }

node "$here/run-survivor-triage.mjs" "$wf"
