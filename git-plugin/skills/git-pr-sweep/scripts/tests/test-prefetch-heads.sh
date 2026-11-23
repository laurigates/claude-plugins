#!/usr/bin/env bash
# Tests for prefetch-heads.sh against a throwaway local origin — no network.
#
# Run: bash git-plugin/skills/git-pr-sweep/scripts/tests/test-prefetch-heads.sh
# Exit 0 = all pass, 1 = failures.
#
# Pins: a PR head that exists only under refs/pull/<n>/head on origin becomes
# present in the clone; a head already present is not refetched; an unknown
# SHA is an ERROR naming the PR; a clone whose origin is another repository is
# refused before any fetch; usage errors exit 2. Also (M5): a row the sweep does
# not review (policy.review false) is not fetched, a single-branch clone gets
# origin/<base>, and a base origin lacks is an ERROR.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PRE="$SCRIPT_DIR/../prefetch-heads.sh"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../../../.." && pwd)"
VALIDATOR="$REPO_ROOT/scripts/check-structured-output-contract.sh"
PASS=0
FAIL=0

command -v git >/dev/null || { echo "SKIP: git not installed"; exit 0; }
command -v jq >/dev/null || { echo "jq required" >&2; exit 1; }

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

# origin: widgets.git with main, plus a PR head reachable only as refs/pull/7/head.
git init -q -b main "$work/seed"
git -C "$work/seed" commit -q --allow-empty -m base
git -C "$work/seed" switch -q -c pr7
git -C "$work/seed" commit -q --allow-empty -m "pr 7 work"
pr7=$(git -C "$work/seed" rev-parse HEAD)
git init -q --bare -b main "$work/widgets.git"
git -C "$work/seed" push -q "$work/widgets.git" main "$pr7:refs/pull/7/head"
# --no-local: a plain local clone hardlinks every object, PR 7 head included.
git clone -q --no-local "$work/widgets.git" "$work/clone"
main_sha=$(git -C "$work/clone" rev-parse origin/main)

roster() { jq -n --arg repo "$1" --argjson rows "$2" '{repo: $repo, prs: $rows}'; }

echo "=== a refs/pull-only head is fetched ==="
assert_eq "control: PR 7 head absent before" absent "$(git -C "$work/clone" cat-file -e "${pr7}^{commit}" 2>/dev/null && echo present || echo absent)"
roster acme/widgets "[{\"number\":7,\"head_sha\":\"$pr7\",\"base\":\"main\"},{\"number\":8,\"head_sha\":\"$main_sha\",\"base\":\"main\"}]" > "$work/r.json"
summary=$(bash "$PRE" --root "$work/clone" "$work/r.json"); rc=$?
assert_eq "exit 0" 0 "$rc"
assert_eq "PR 7 head present after" 0 "$(git -C "$work/clone" cat-file -e "${pr7}^{commit}" 2>/dev/null; echo $?)"
assert_eq "one fetched, one already present" "FETCHED=1|ALREADY_PRESENT=1" "$(grep '^FETCHED=' <<<"$summary")|$(grep '^ALREADY_PRESENT=' <<<"$summary")"
validate "summary meets the structured-output contract (OK)" "$summary"

echo "=== an unknown SHA is an error naming the PR ==="
roster acme/widgets '[{"number":9,"head_sha":"1234567890123456789012345678901234567890","base":"main"}]' > "$work/r9.json"
summary=$(bash "$PRE" --root "$work/clone" "$work/r9.json"); rc=$?
assert_eq "exit 1" 1 "$rc"
assert_eq "MISSING names PR 9" "MISSING=9" "$(grep '^MISSING=' <<<"$summary")"
validate "summary meets the structured-output contract (ERROR)" "$summary"

echo "=== a clone of another repository is refused ==="
roster acme/gadgets "[{\"number\":7,\"head_sha\":\"$pr7\",\"base\":\"main\"}]" > "$work/rg.json"
summary=$(bash "$PRE" --root "$work/clone" "$work/rg.json"); rc=$?
assert_eq "origin mismatch exits 1" 1 "$rc"
assert_eq "origin mismatch reported" 'true' "$(grep -q 'TYPE=origin_mismatch' <<<"$summary" && echo true || echo false)"
git -C "$work/clone" remote set-url origin https://github.com/other/widgets.git
bash "$PRE" --root "$work/clone" "$work/r.json" >/dev/null; assert_eq "github origin of another owner with the same name is refused" 1 "$?"
git -C "$work/clone" remote set-url origin https://github.com/acme/widgets.git
bash "$PRE" --root "$work/clone" "$work/rg.json" >/dev/null; assert_eq "github origin of another repo is refused" 1 "$?"

# Regression (M5): every roster row was fetched, so an unfetchable head on a row
# the sweep never reviews (policy.review false) failed the whole prefetch.
echo "=== rows the sweep does not review are not fetched ==="
git -C "$work/clone" remote set-url origin "$work/widgets.git"
roster acme/widgets "[{\"number\":7,\"head_sha\":\"$pr7\",\"base\":\"main\",\"policy\":{\"review\":true}},{\"number\":30,\"head_sha\":\"3030303030303030303030303030303030303030\",\"base\":\"main\",\"policy\":{\"review\":false}}]" > "$work/rnr.json"
summary=$(bash "$PRE" --root "$work/clone" "$work/rnr.json"); rc=$?
assert_eq "unreviewed row with an unfetchable head: exit 0" 0 "$rc"
assert_eq "MISSING empty, NOT_REVIEWED=1" "MISSING=|NOT_REVIEWED=1" "$(grep '^MISSING=' <<<"$summary")|$(grep '^NOT_REVIEWED=' <<<"$summary")"
roster acme/widgets '[{"number":31,"head_sha":"3131313131313131313131313131313131313131","base":"main","policy":{"review":true}}]' > "$work/rrv.json"
bash "$PRE" --root "$work/clone" "$work/rrv.json" >/dev/null; assert_eq "control: a reviewed row with the same kind of head still fails" 1 "$?"

# Regression (M5): `git fetch origin <base>` left origin/<base> absent in a
# single-branch clone, and pr-review's `git diff origin/<base>...` then failed.
echo "=== a single-branch clone gets origin/<base> ==="
git -C "$work/seed" switch -q -c dev main
git -C "$work/seed" commit -q --allow-empty -m "dev work"
git -C "$work/seed" push -q "$work/widgets.git" dev
git clone -q --no-local --single-branch --branch main "$work/widgets.git" "$work/single"
assert_eq "control: origin/dev absent before" absent "$(git -C "$work/single" rev-parse --verify -q refs/remotes/origin/dev >/dev/null && echo present || echo absent)"
roster acme/widgets "[{\"number\":7,\"head_sha\":\"$pr7\",\"base\":\"dev\"}]" > "$work/rdev.json"
summary=$(bash "$PRE" --root "$work/single" "$work/rdev.json"); rc=$?
assert_eq "exit 0" 0 "$rc"
assert_eq "origin/dev present after" present "$(git -C "$work/single" rev-parse --verify -q refs/remotes/origin/dev >/dev/null && echo present || echo absent)"
roster acme/widgets "[{\"number\":7,\"head_sha\":\"$pr7\",\"base\":\"no-such-base\"}]" > "$work/rnob.json"
summary=$(bash "$PRE" --root "$work/single" "$work/rnob.json"); rc=$?
assert_eq "a base origin lacks exits 1" 1 "$rc"
assert_eq "base_missing reported" true "$(grep -q 'TYPE=base_missing' <<<"$summary" && echo true || echo false)"
validate "summary meets the structured-output contract (base ERROR)" "$summary"

echo "=== usage ==="
bash "$PRE" >/dev/null 2>&1; assert_eq "no input exits 2" 2 "$?"
bash "$PRE" --bogus "$work/r.json" >/dev/null 2>&1; assert_eq "unknown flag exits 2" 2 "$?"
bash "$PRE" --root "$work/nope" "$work/r.json" >/dev/null 2>&1; assert_eq "missing root exits 1" 1 "$?"

echo
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
