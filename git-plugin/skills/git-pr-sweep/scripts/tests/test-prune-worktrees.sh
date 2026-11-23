#!/usr/bin/env bash
# Tests for prune-worktrees.sh against a throwaway repository — no network.
#
# Run: bash git-plugin/skills/git-pr-sweep/scripts/tests/test-prune-worktrees.sh
# Exit 0 = all pass, 1 = failures.
#
# Pins: a worktree whose directory is gone is pruned; a live worktree under the
# worktrees dir is listed and left in place; a worktree elsewhere is not listed;
# usage errors exit 2; a non-clone root is an ERROR. Also pins (M3) that
# SKILL.md runs the clean-up through this script, under a grant anchored to
# ${CLAUDE_SKILL_DIR}, instead of an ungranted `git -C <root> worktree prune`.
# Pins (verifier, on M3) that only sweep-named worktrees are listed, so a peer
# session's worktree in the shared dir is never handed to the caller, and that
# neither the WARN nor Post-actions suggests removing what is listed.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PRUNE="$SCRIPT_DIR/../prune-worktrees.sh"
SKILL_MD="$SCRIPT_DIR/../../SKILL.md"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../../../.." && pwd)"
VALIDATOR="$REPO_ROOT/scripts/check-structured-output-contract.sh"
PASS=0
FAIL=0

command -v git >/dev/null || { echo "SKIP: git not installed"; exit 0; }

# Guard the sandbox: an empty $work would point git -C at the current repo.
work=$(mktemp -d)
{ [ -n "$work" ] && [ -d "$work" ]; } || { echo "mktemp failed" >&2; exit 1; }
work=$(cd -P -- "$work" && pwd -P) || { echo "cannot resolve temp dir" >&2; exit 1; }
trap 'rm -rf "$work"' EXIT
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_OBJECT_DIRECTORY GIT_COMMON_DIR
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@example.invalid GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@example.invalid

assert_eq() {
  local desc="$1" expected="$2" actual="$3"
  if [ "$expected" = "$actual" ]; then
    printf "  PASS: %s\n" "$desc"; PASS=$((PASS + 1))
  else
    printf "  FAIL: %s (expected [%s], got [%s])\n" "$desc" "$expected" "$actual"; FAIL=$((FAIL + 1))
  fi
}
validate() {
  local desc="$1" block="$2"
  if [ ! -f "$VALIDATOR" ]; then printf "  SKIP: %s (no validator)\n" "$desc"; return; fi
  if bash "$VALIDATOR" --validate - <<<"$block" >/dev/null 2>&1; then
    printf "  PASS: %s\n" "$desc"; PASS=$((PASS + 1))
  else
    printf "  FAIL: %s\n" "$desc"; FAIL=$((FAIL + 1))
  fi
}

git init -q -b main "$work/clone"
git -C "$work/clone" commit -q --allow-empty -m base
wt="$work/clone/.claude/worktrees"
git -C "$work/clone" worktree add -q --detach "$wt/repair-pr-1"
git -C "$work/clone" worktree add -q --detach "$wt/verify-pr-1"
git -C "$work/clone" worktree add -q --detach "$work/elsewhere"
rm -rf "$wt/verify-pr-1"

echo "=== prune and list ==="
summary=$(bash "$PRUNE" --root "$work/clone"); rc=$?
assert_eq "exit 0" 0 "$rc"
assert_eq "the worktree whose directory is gone is pruned" "PRUNED=1" "$(grep '^PRUNED=' <<<"$summary")"
assert_eq "one live worktree under the worktrees dir remains" "REMAINING=1" "$(grep '^REMAINING=' <<<"$summary")"
assert_eq "it is listed by path" "WORKTREE_1=$wt/repair-pr-1" "$(grep '^WORKTREE_1=' <<<"$summary")"
assert_eq "the live worktree is left in place" present "$([ -d "$wt/repair-pr-1" ] && echo present || echo absent)"
assert_eq "a worktree outside the worktrees dir is not listed" "" "$(grep -F "$work/elsewhere" <<<"$summary")"
validate "summary meets the structured-output contract (WARN)" "$summary"

git -C "$work/clone" worktree remove "$wt/repair-pr-1"
summary=$(bash "$PRUNE" --root "$work/clone" --worktrees "$wt"); rc=$?
assert_eq "nothing left: exit 0, STATUS=OK" "0|STATUS=OK" "$rc|$(grep '^STATUS=' <<<"$summary")"
validate "summary meets the structured-output contract (OK)" "$summary"

echo "=== errors and usage ==="
mkdir -p "$work/plain"
bash "$PRUNE" --root "$work/plain" >/dev/null; assert_eq "a non-clone root exits 1" 1 "$?"
bash "$PRUNE" >/dev/null 2>&1; assert_eq "no --root exits 2" 2 "$?"
bash "$PRUNE" --bogus >/dev/null 2>&1; assert_eq "unknown flag exits 2" 2 "$?"

# Regression (verifier, on M3): the default worktrees dir is the one every
# Claude Code session shares. The script listed every live worktree there,
# peers' included, under a REASON telling the caller to remove each.
echo "=== only sweep-named worktrees are listed ==="
git -C "$work/clone" worktree add -q --detach "$wt/repair-pr-2"
git -C "$work/clone" worktree add -q --detach "$wt/round2/verify-pr-2"
git -C "$work/clone" worktree add -q --detach "$wt/pr-sweep-verify-7-1"
git -C "$work/clone" worktree add -q --detach "$wt/peer-session"
git -C "$work/clone" worktree add -q --detach "$wt/agent-a1b2"
git -C "$work/clone" worktree add -q --detach "$wt/wf_ab12cd-3f4-1"
git -C "$work/clone" worktree add -q --detach "$wt/wf_ffff00-000-1"
summary=$(bash "$PRUNE" --root "$work/clone"); rc=$?
assert_eq "exit 0" 0 "$rc"
assert_eq "three sweep-named worktrees listed" "REMAINING=3" "$(grep '^REMAINING=' <<<"$summary")"
assert_eq "four other worktrees counted" "OTHER_WORKTREES=4" "$(grep '^OTHER_WORKTREES=' <<<"$summary")"
assert_eq "repair-, round2/verify- and pr-sweep-verify- are the ones listed" \
  "$wt/pr-sweep-verify-7-1|$wt/repair-pr-2|$wt/round2/verify-pr-2" \
  "$(sed -n 's/^WORKTREE_[0-9]*=//p' <<<"$summary" | sort | paste -sd'|' -)"
assert_eq "a peer session's worktree is not named" "" "$(grep -F -e "$wt/peer-session" -e "$wt/agent-a1b2" <<<"$summary")"
assert_eq "a harness run's worktree is not named without --run-id" "" "$(grep -F "$wt/wf_" <<<"$summary")"
reason=$(grep '^REASON=' <<<"$summary")
assert_eq "the WARN does not tell the caller to remove what is listed" "" "$(grep -iF 'remove each' <<<"$reason")"
assert_eq "the WARN says to remove none" true "$(grep -qF 'remove none' <<<"$reason" && echo true || echo false)"
validate "summary meets the structured-output contract (scoped WARN)" "$summary"

for id in ab12cd-3f4 wf_ab12cd-3f4; do
  summary=$(bash "$PRUNE" --root "$work/clone" --run-id "$id")
  assert_eq "--run-id $id adds that run's worktree" "$wt/wf_ab12cd-3f4-1" "$(grep -oF "$wt/wf_ab12cd-3f4-1" <<<"$summary")"
  assert_eq "--run-id $id leaves another run's worktree unnamed" "" "$(grep -F "$wt/wf_ffff00" <<<"$summary")"
done
bash "$PRUNE" --root "$work/clone" --run-id 'a.*' >/dev/null 2>&1; assert_eq "a --run-id with regex characters exits 2" 2 "$?"
bash "$PRUNE" --root "$work/clone" --run-id >/dev/null 2>&1; assert_eq "--run-id with no value exits 2" 2 "$?"

# Regression (M3): Post-actions ran `git -C <root> worktree prune`, which no
# allowed-tools entry covered, so the run ended on a permission prompt.
echo "=== SKILL.md runs the clean-up under a grant ==="
# shellcheck disable=SC2016 # literal ${CLAUDE_SKILL_DIR} as written in SKILL.md
grant='Bash(bash ${CLAUDE_SKILL_DIR}/scripts/prune-worktrees.sh *)'
assert_eq "allowed-tools grants prune-worktrees.sh" true "$(grep -m1 '^allowed-tools:' "$SKILL_MD" | grep -qF "$grant" && echo true || echo false)"
post=$(awk '/^## Post-actions/{on=1} on' "$SKILL_MD")
# shellcheck disable=SC2016
assert_eq "Post-actions invokes it as granted" true "$(grep -qF 'bash ${CLAUDE_SKILL_DIR}/scripts/prune-worktrees.sh --root <root>' <<<"$post" && echo true || echo false)"
assert_eq "Post-actions no longer runs an ungranted git -C worktree prune" "" "$(grep -F 'git -C <root> worktree prune' <<<"$post")"
assert_eq "Post-actions reports the listed worktrees and removes none" true "$(grep -qF 'Remove none' <<<"$post" && echo true || echo false)"
REDISPATCH="$SCRIPT_DIR/../../references/fix-redispatch.md"
assert_eq "fix-redispatch.md lists a harness run's worktrees with --run-id" true "$(grep -qF -- '--run-id <run-id>' "$REDISPATCH" && echo true || echo false)"

echo
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
