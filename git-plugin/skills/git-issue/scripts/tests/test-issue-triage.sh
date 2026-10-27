#!/usr/bin/env bash
# Behaviour test for git-issue's issue-triage.workflow.js, run against a stub
# runtime (run-issue-triage.mjs). It pins what the template adds over the ad-hoc
# triage runs it replaces, which sliced each batch on its own:
#   - the partition invariant: every input issue ends in exactly one slice or in
#     `deferred` with a closed reason, whatever the assessors and slicer return
#     (invented issues discarded, omitted ones deferred or recovered, duplicates
#     kept once, non-autonomous classes never sliced);
#   - cross-batch file overlap is serialised into separate waves, so no wave
#     hands implement-verify two units that own the same file;
#   - an autonomous issue whose assessment names an open-PR overlap or a
#     blocker is deferred before slicing, including the single-issue path
#     that runs no slicer;
#   - the closed class and slicer-reason enums are exact (adding a value fails);
#   - assessors run at most WAVE per parallel() call;
#   - a dependency cycle is deferred, never dispatched, and a dependant of a
#     slice whose issues were all deferred is deferred `blocked`;
#   - a directory entry ('src/lib/') overlaps every path under it;
#   - "No blockers" / "None." / "N/A." do not read as a blocker;
#   - waves are { units, standalone }, each layer split evenly between
#     implement-verify's floor of 2 and cap of 5; only a one-slice layer is a
#     one-unit `standalone` wave;
#   - args.classes as an array aborts `bad-classes` rather than being ignored;
#   - the floor/empty guards spend zero agents, and a dead slicer aborts
#     with the assessments rather than returning an unpartitioned plan.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
wf="$here/../../workflows/issue-triage.workflow.js"

command -v node >/dev/null || { echo "SKIP: node not installed"; exit 0; }
[[ -f "$wf" ]] || { echo "FAIL template missing: $wf"; exit 1; }

node "$here/run-issue-triage.mjs" "$wf"
