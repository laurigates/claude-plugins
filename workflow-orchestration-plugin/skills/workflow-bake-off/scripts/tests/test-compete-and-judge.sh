#!/usr/bin/env bash
# Behaviour tests for workflows/compete-and-judge.workflow.js, run against a
# stub runtime (run-template.mjs). They pin the template's one load-bearing
# claim: the winner is COMPUTED in JS from the judges' rankings or measured
# metrics, never picked by a model reading the verdicts.
#
#   - Borda points are K-1-position over the surviving entries; a partial,
#     duplicated or unknown-key ranking cannot inflate an entry.
#   - Ties break on mean score (one score per judge per entry, so a duplicated
#     row is not an extra vote), then on caller order (args.entries), so the
#     same inputs always crown the same entry, whatever order verdicts arrive.
#   - A panel below quorum crowns nobody. The ad-hoc runs this was distilled
#     from sorted an all-zero tally and refined whichever entry came first.
#     A metric judge whose rows carry no finite metric value is not a panel
#     member either: it would make every median null and crown entry 0.
#   - Metric mode ranks on judge-measured numbers, never on an entrant's
#     self-report or a judge's ranking; a missing value sorts last, and a
#     judge's repeated measurement row or value counts once.
#   - Every judge's prompt lists every surviving entry (barrier (d)), and every
#     verdict a judge returned reaches the result, unusable ones named.
#   - Judge scratch sits under ${out}/_judges/, a name no key can take.
#   - Over/under caps, duplicate or path-like keys, and a dead setup stage
#     abort before any further agent is spawned.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
wf="$here/../../workflows/compete-and-judge.workflow.js"

command -v node >/dev/null || { echo "SKIP: node not installed"; exit 0; }
[[ -f "$wf" ]] || { echo "FAIL template missing: $wf"; exit 1; }

node "$here/run-template.mjs" "$wf"
