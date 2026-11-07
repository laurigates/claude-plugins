#!/usr/bin/env bash
# Behaviour test for git-triage's issue-triage.workflow.js, run against a stub
# runtime (run-issue-triage.mjs). It pins what the template generalised from a
# one-off multi-repository triage run:
#   - repositories, clone paths and issues come from args (owner/name#N,
#     alias#N, or { repo, number }); each agent's prompt reads its own clone;
#   - a dead agent lands in `missing`, never as a verdict, and a row is keyed
#     by its input issue, not by what the agent echoed;
#   - the verdict enum is the closed four, and the question field is
#     question_for_user;
#   - args.classes and args.limits replace the default text;
#   - over the cap, below the floor, a repository with no clone, an
#     unparseable reference and an unknown verdict all abort with zero agents;
#   - at the cap every issue gets an agent.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
wf="$here/../../workflows/issue-triage.workflow.js"

command -v node >/dev/null || { echo "SKIP: node not installed"; exit 0; }
[[ -f "$wf" ]] || { echo "FAIL template missing: $wf"; exit 1; }

node "$here/run-issue-triage.mjs" "$wf"
