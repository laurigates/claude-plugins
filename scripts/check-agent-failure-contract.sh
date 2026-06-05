#!/usr/bin/env bash
# Verify the agent-patterns-plugin dispatch skills still carry the
# "loud-failure contract" — the semantic invariant that a dispatched agent
# must never surrender with a one-word final message (`Terminal.`/`Done.`).
#
# Background: issue #1422 documented dispatched worktree-isolated agents
# returning one-word summaries (e.g. "Terminal.") on failure after 50–200
# tool calls — no PR URL, no error explanation, no list of what's blocked.
# A one-word summary is indistinguishable from success to the orchestrator,
# so the harness cleans up the worktree and the work is lost. The fix is a
# loud-failure contract baked into the dispatch-prompt guidance; this check
# keeps a future bulk edit from silently "tightening" that contract away.
#
# This is a SEMANTIC gate (per .claude/rules/regression-testing.md): it asks
# whether the artefact still carries the intent it was designed for, not just
# whether it parses.
#
# What counts as compliant for each target skill:
#   parallel-agent-dispatch/SKILL.md
#     - contains the literal heading text "Loud-failure contract"
#     - cites the banned bare-surrender example "Terminal."
#     - references issue #1422
#   custom-agent-definitions/SKILL.md
#     - references issue #1422 (the cross-reference to the contract)
#
# Usage:
#   bash scripts/check-agent-failure-contract.sh
#
# Exit codes:
#   0 - both skills carry the contract markers
#   1 - one or more markers missing

set -uo pipefail

cd "$(dirname "$0")/.." || exit 1

dispatch_skill="agent-patterns-plugin/skills/parallel-agent-dispatch/SKILL.md"
agentdef_skill="agent-patterns-plugin/skills/custom-agent-definitions/SKILL.md"

errors=0

require_marker() {
  # require_marker <file> <fixed-string> <human description>
  local file="$1" needle="$2" desc="$3"
  if [ ! -f "$file" ]; then
    echo "ERROR: $file not found"
    errors=$((errors + 1))
    return
  fi
  if ! grep -qF -- "$needle" "$file"; then
    echo "ERROR: $file is missing the loud-failure contract marker: $desc"
    echo "       expected to find: $needle"
    errors=$((errors + 1))
  fi
}

# parallel-agent-dispatch is the dispatch-prompt home of the contract.
require_marker "$dispatch_skill" "Loud-failure contract" "the contract heading"
require_marker "$dispatch_skill" "Terminal." "the banned bare-surrender example"
require_marker "$dispatch_skill" "#1422" "the issue reference"

# custom-agent-definitions carries the cross-reference best practice.
require_marker "$agentdef_skill" "#1422" "the issue reference / cross-link"

# Regression #1424: REFERENCE.md must carry the QUANTITATIVE hook-thrashing
# heuristic so an orchestrator can intervene programmatically.  A bulk edit
# that "tightens" the prose may silently remove the threshold numbers, leaving
# only qualitative guidance and restoring the deferral to "issue #1424".
# Check for the specific numeric threshold strings that make the heuristic
# actionable (9:1 ratio and the 30% / 3-consecutive-blocks is_error rate).
reference_md="agent-patterns-plugin/skills/parallel-agent-dispatch/REFERENCE.md"
require_marker "$reference_md" "9:1" "Bash:Edit ratio threshold (issue #1424)"
require_marker "$reference_md" "is_error" "is_error rate signal (issue #1424)"
require_marker "$reference_md" "30%" "30% is_error-rate threshold (issue #1424)"

# Regression #1491: an agent cut off (e.g. by a rate limit) AFTER implementing
# its change but BEFORE emitting StructuredOutput is reported failed, yet the
# work sits intact as uncommitted WIP in its worktree. The fix is twofold and
# both halves are semantic invariants a bulk edit could silently drop:
#   1) SKILL.md "Handling a Missing Return" must (a) tell the orchestrator to
#      DISCRIMINATE an empty worktree from a dirty one before re-dispatching,
#      and (b) instruct the brief to commit WIP at checkpoints.
#   2) REFERENCE.md must carry the "WIP salvage before re-dispatch" subsection.
require_marker "$dispatch_skill" "empty vs dirty" "empty-vs-dirty discrimination (issue #1491)"
require_marker "$dispatch_skill" "WIP at checkpoints" "checkpoint-WIP-commit brief instruction (issue #1491)"
require_marker "$dispatch_skill" "#1491" "the issue reference"
require_marker "$reference_md" "WIP salvage before re-dispatch" "the salvage subsection heading (issue #1491)"
require_marker "$reference_md" "#1491" "the issue reference"

if [ "$errors" -ne 0 ]; then
  echo
  echo "The loud-failure contract (issue #1422) and the hook-thrashing heuristic"
  echo "(issue #1424) must remain in the dispatch skills / REFERENCE.md."
  echo "See .claude/rules/regression-testing.md and:"
  echo "  - 'Loud-failure contract' section in $dispatch_skill"
  echo "  - 'Killed-agent worktree recovery' section in $reference_md"
  echo "  - 'WIP salvage before re-dispatch' section in $reference_md (issue #1491)"
  exit 1
fi

echo "OK: loud-failure contract, hook-thrashing heuristic, and WIP-salvage discrimination present in agent-patterns dispatch skills"
exit 0
