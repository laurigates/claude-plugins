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

# 6. The PR-state ancestry test the briefs prescribe, run against git (#3642).
#    A merged PR whose head was pushed from another clone, with its branch
#    deleted on merge, leaves a headRefOid the local clone does not have and
#    that is ahead of the local tip. Testing only `<headRefOid>` ancestor of the
#    local branch reads that PR as earlier work and ignores it; fetching
#    pull/<n>/head and testing both directions counts it, while an unrelated
#    PR on a reused name still fails both directions.
ancestry_sim() {
  local d
  d=$(mktemp -d) || return 2
  [[ -n "$d" && -d "$d" ]] || return 2
  (
    unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_OBJECT_DIRECTORY GIT_COMMON_DIR
    set -e
    g() { git -c user.email=t@example.com -c user.name=t "$@"; }
    g init -q --bare -b main "$d/origin.git"
    g clone -q "$d/origin.git" "$d/local" 2>/dev/null
    g -C "$d/local" commit -q --allow-empty -m c0
    g -C "$d/local" push -q origin HEAD:main
    g -C "$d/local" switch -q -c fix/a
    g -C "$d/local" commit -q --allow-empty -m c1
    g -C "$d/local" push -q origin fix/a
    # Another clone adds c2 to the PR, which merges; the branch is deleted.
    g clone -q -b fix/a "$d/origin.git" "$d/other" 2>/dev/null
    g -C "$d/other" commit -q --allow-empty -m c2
    head_oid=$(g -C "$d/other" rev-parse HEAD)
    g -C "$d/other" push -q origin HEAD:refs/pull/1/head
    g -C "$d/other" push -q origin --delete fix/a
    # An unrelated PR from an earlier use of the name, cut from main.
    g -C "$d/other" switch -q -c old main 2>/dev/null || g -C "$d/other" switch -q -c old origin/main
    g -C "$d/other" commit -q --allow-empty -m old-work
    old_oid=$(g -C "$d/other" rev-parse HEAD)
    g -C "$d/other" push -q origin HEAD:refs/pull/2/head
    g -C "$d/local" fetch -q origin
    set +e
    g -C "$d/local" merge-base --is-ancestor "$head_oid" fix/a 2>/dev/null
    old_rule=$?
    g -C "$d/local" fetch -q origin pull/1/head pull/2/head || exit 3
    g -C "$d/local" merge-base --is-ancestor "$head_oid" fix/a || g -C "$d/local" merge-base --is-ancestor fix/a "$head_oid"
    new_rule=$?
    g -C "$d/local" merge-base --is-ancestor "$old_oid" fix/a || g -C "$d/local" merge-base --is-ancestor fix/a "$old_oid"
    unrelated=$?
    echo "$old_rule $new_rule $unrelated"
  )
  local rc=$?
  rm -rf "$d"
  return "$rc"
}
if sim="$(ancestry_sim)"; then
  read -r old_rule new_rule unrelated <<<"$sim"
  if [[ "$old_rule" != 0 && "$new_rule" == 0 && "$unrelated" != 0 ]]; then
    echo "PASS ancestry: one-direction test misses a PR head pushed elsewhere; fetch + both directions counts it; unrelated PR still ignored"
  else
    echo "FAIL ancestry simulation: old_rule=$old_rule new_rule=$new_rule unrelated=$unrelated (want non-zero, 0, non-zero)"; exit 1
  fi
else
  echo "FAIL ancestry simulation setup failed"; exit 1
fi

status=0
for t in implement-verify repair-round; do
  node "$here/run-template.mjs" "$wf/$t.workflow.js" || status=1
done
exit "$status"
