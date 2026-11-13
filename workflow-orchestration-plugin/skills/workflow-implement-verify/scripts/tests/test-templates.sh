#!/usr/bin/env bash
# Regression tests for the workflow-implement-verify templates.
#   1. The Verify/Repair region is byte-identical in both templates, so a
#      repair-round run can consume an implement-verify run's rows.
#   2. Each template, run against a stub runtime, never lands a unit whose
#      verifier returned null (three ad-hoc repair runs read a dead verifier as
#      approval: `if (!v || v.approved)`), repairs at most once, never repairs a
#      `reject`, and aborts over its unit cap before spawning an agent.
#   3. Every repair brief reads the branch's PR state before any work, and a
#      repairer that stops on a merged or closed PR is BLOCKED and never
#      re-verified (#3589: a repairer opened a second PR for a merged branch).
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
wf="$here/../../workflows"

command -v node >/dev/null || { echo "SKIP: node not installed"; exit 0; }

region() { sed -n '/<shared:begin>/,/<shared:end>/p' "$1"; }
a="$(region "$wf/implement-verify.workflow.js")"
b="$(region "$wf/repair-round.workflow.js")"
if [[ -z "$a" ]]; then
  echo "FAIL shared region markers missing from implement-verify.workflow.js"; exit 1
fi
if [[ "$a" != "$b" ]]; then
  echo "FAIL shared Verify/Repair region differs between the two templates:"
  diff <(printf '%s\n' "$a") <(printf '%s\n' "$b") || true
  exit 1
fi
echo "PASS shared region identical ($(printf '%s\n' "$a" | wc -l | tr -d ' ') lines)"

# 4. The trial-integration recipe aborts a conflicted merge before removing the
#    throwaway worktree: `git worktree remove` refuses a tree holding a
#    conflicted merge's modified files unless forced.
skill="$here/../../SKILL.md"
landing="$here/../../references/landing.md"
recipe="$(awk '/^\*\*Trial-integrate/,/^$/' "$landing")"
if [[ "$(cat "$skill")" != *"references/landing.md"* ]]; then
  echo "FAIL SKILL.md does not link references/landing.md"; exit 1
fi
abort='git -C <tmp> merge --abort'
remove='git worktree remove <tmp>'
# Offset of the first abort and of the last remove, by string slicing (no pipes under pipefail).
before_abort="${recipe%%"$abort"*}"
before_remove="${recipe%"$remove"*}"
if [[ "$recipe" != *"$abort"* || "$recipe" != *"$remove"* ]] || (( ${#before_abort} > ${#before_remove} )); then
  echo "FAIL trial-integration recipe lacks \`git -C <tmp> merge --abort\` before its final \`git worktree remove <tmp>\`"; exit 1
fi
echo "PASS trial-integration recipe aborts a conflicted merge before removing the worktree"

# 5. The docs give the PR-state check's reason per template: a PR merging while
#    its verifier runs applies only to repair-round; in implement-verify no PR
#    exists before finalise, so the check fires only on a reused branch name.
docs="$(cat "$skill")"
if [[ "$docs" == *"because a PR can merge while its verifier runs"* \
   || "$docs" != *"In \`implement-verify\` no PR exists before finalise"* \
   || "$docs" != *"In \`repair-round\` the branch already has a PR"* ]]; then
  echo "FAIL SKILL.md does not state the PR-state check's reason per template"; exit 1
fi
echo "PASS SKILL.md states the PR-state check's reason per template"

status=0
for t in implement-verify repair-round; do
  node "$here/run-template.mjs" "$wf/$t.workflow.js" || status=1
done
exit "$status"
