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
#     - references issue #1480 with the absolute-path git idiom
#       (`git -C "$WORKTREE"`) that defends against cwd-reset leaks
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

# Regression #1480: a git-write agent under isolation:worktree leaked its git
# writes into the MAIN repo because the agent-thread cwd reset landed on the
# session's primary cwd, not the worktree.  The dispatch contract must carry
# the cwd-reset guardrail (use `git -C "$WORKTREE"` / pin show-toplevel, plus a
# post-run main-repo integrity check) so a bulk edit can't tighten it away.
# This is DISTINCT from the #1319 transient-leak section above — assert both the
# #1480 reference and the absolute-path idiom that defends against the reset.
require_marker "$dispatch_skill" "#1480" "the cwd-reset worktree-leak reference"
# The single-quoted needle is a literal fixed string (grep -qF), not a shell
# expansion — `$WORKTREE` must stay verbatim to match the SKILL.md marker.
# shellcheck disable=SC2016
require_marker "$dispatch_skill" 'git -C "$WORKTREE"' "the absolute-path git idiom (issue #1480)"

# Regression #1546: SendMessage-resume of a COMPLETED worktree-isolated agent
# does NOT re-enter its worktree — the resumed run executes in the orchestrator's
# MAIN checkout, silently losing worktree isolation. Resuming several parallel
# file-mutating agents this way runs them concurrently in the main checkout and
# tangles branch state. The fix documents the caveat in parallel-agent-dispatch
# (and cross-references it from agent-teams) and directs re-dispatch of a fresh
# isolation:worktree agent for parallel file-mutating continuations. Assert BOTH
# the literal phrase and the issue reference survive future bulk edits.
require_marker "$dispatch_skill" "loses worktree isolation" "the SendMessage-resume isolation-loss caveat (issue #1546)"
require_marker "$dispatch_skill" "#1546" "the issue reference"

# Regression #1868: Workflow({resumeFromRunId}) does NOT cache a succeeded
# isolation:"worktree" agent — it RE-RUNS it on resume, re-firing its outward
# side effects and opening a DUPLICATE PR (#1858 dup of #1857). This is the
# opposite failure to the #1546 SendMessage-resume case (which loses isolation).
# The fix documents the caveat in parallel-agent-dispatch (subsection "Resuming
# a workflow: resumeFromRunId re-runs succeeded worktree agents") and directs
# fresh sequential re-dispatch of only the failed agents. Assert BOTH the
# load-bearing phrase and the issue reference survive future bulk edits.
require_marker "$dispatch_skill" "re-runs succeeded worktree agents" "the resumeFromRunId re-run caveat heading (issue #1868)"
require_marker "$dispatch_skill" "#1868" "the issue reference"

# Regression (#1692 sibling): the GIT_DIR/GIT_WORK_TREE export leak — exporting
# git env to paper over a bare worktree redirects every git op (and any
# git-shelling test/hook subprocess) at the shared common config, corrupting all
# worktrees. DISTINCT from the empty-mktemp vector guarded by
# check-git-sandbox-guards.sh (#1692): there the path is empty; here the path is
# correct and the exported env is the hijack. Assert the SKILL.md carries the
# hazard reference + the env-neutralizing idiom, and REFERENCE.md the section.
require_marker "$dispatch_skill" "#1692" "the GIT_DIR-export worktree-leak reference (#1692 sibling)"
require_marker "$dispatch_skill" "env -u GIT_DIR" "the env-neutralizing git idiom (#1692 sibling)"
require_marker "$reference_md" "Worktree GIT_DIR-export leak" "the REFERENCE.md GIT_DIR-export section (#1692 sibling)"

# Regression #1838: in a nested-repo workspace, isolation:"worktree" worktrees
# the OUTER session repo, not the nested independent repo the agent was told to
# edit — so the nested repo is absent and the agent must hand-roll its own
# worktree. The fix documents detecting the nesting and isolating the nested repo
# explicitly. Assert the SKILL.md carries the #1838 reference and the REFERENCE.md
# section survives bulk edits.
require_marker "$dispatch_skill" "#1838" "the nested-repo worktree-isolation reference (#1838)"
require_marker "$reference_md" "Nested-repo worktree isolation" "the REFERENCE.md nested-repo isolation section (#1838)"
# Regression #1601: a refactor subagent assigned a large CLOSED LIST of
# mechanical deletions (symbols/files) stops early but returns a plausible
# (often truncated) self-report, so the under-delivery is invisible unless the
# orchestrator re-runs the authoritative checker. The fix is twofold and both
# halves are semantic invariants a bulk edit could silently drop:
#   1) agents-plugin/agents/refactor.md must carry the Completion Manifest
#      requirement (a machine-checkable list of what actually landed) AND the
#      batch-size cap referencing #1601.
#   2) parallel-agent-dispatch SKILL.md + REFERENCE.md must reference #1601 and
#      carry the manifest / never-trust-self-report-alone language alongside the
#      existing Pillar 4/5 verification guidance.
refactor_agent="agents-plugin/agents/refactor.md"
require_marker "$refactor_agent" "Completion Manifest" "the completion-manifest section (issue #1601)"
require_marker "$refactor_agent" "#1601" "the issue reference in the refactor agent (batch-size cap)"
require_marker "$dispatch_skill" "#1601" "the completion-manifest reference (issue #1601)"
require_marker "$dispatch_skill" "completion manifest" "the manifest language in the dispatch skill (issue #1601)"
require_marker "$reference_md" "#1601" "the completion-manifest reference (issue #1601)"
require_marker "$reference_md" "Completion manifest" "the manifest line in the refactor-brief template (issue #1601)"

# Regression #1969: an isolation:"worktree" dispatch creates a fresh worktree
# with an AUTO-GENERATED branch name; when the agent later RENAMES onto a fixed
# conventional target name already checked out by a concurrent session's
# worktree, git refuses — and the collision surfaces only at end-of-task rename,
# ~25 min / ~400K tokens deep, after both sessions reached PR-open (two duplicate
# PRs). The fix adds a target-branch preflight to Pillar 1 (check the fixed name
# is free via git branch -a --list / worktree list / ls-remote BEFORE work) plus
# the refspec-push mitigation that sidesteps the "already checked out" refusal.
# Assert BOTH the load-bearing preflight idiom and the issue reference survive.
require_marker "$dispatch_skill" "Target-branch preflight" "the target-branch preflight subsection (issue #1969)"
require_marker "$dispatch_skill" "git ls-remote --heads origin" "the remote target-name check (issue #1969)"
require_marker "$dispatch_skill" "#1969" "the issue reference"

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
