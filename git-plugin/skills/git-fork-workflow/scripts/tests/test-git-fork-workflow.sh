#!/usr/bin/env bash
# Regression test for git-fork-workflow.sh (issue #1552).
# Plants a fixture repo with local upstream/main and origin/main refs and asserts
# the pure strategy recommender: an ahead-only fork recommends one strategy and a
# diverged fork another (plus fast-forward and in-sync). Fully offline.
# Exit 0 on success, non-zero on failure.

set -uo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
fork_script="${script_dir}/../git-fork-workflow.sh"

fail() {
  echo "FAIL: $1" >&2
  exit 1
}

pass() {
  echo "PASS: $1"
}

if ! command -v jq >/dev/null 2>&1; then
  echo "SKIP: jq not installed (jq parity with sibling tests)"
  exit 0
fi

[ -f "$fork_script" ] || fail "git-fork-workflow.sh not found at $fork_script"

export GIT_FORK_NO_FETCH=1

# Build a repo whose upstream/main and origin/main refs we control directly.
# Layout: a shared base, then divergent commits planted on the two refs.
make_repo() {
  local r="$1"
  git -C "$r" init -q -b main
  git -C "$r" config user.email "test@example.com"
  git -C "$r" config user.name "Test"
  git -C "$r" config commit.gpgsign false
  git -C "$r" remote add upstream https://github.com/owner/repo.git
  git -C "$r" remote add origin https://github.com/me/repo.git
  echo "base" > "$r/base.txt"; git -C "$r" add base.txt; git -C "$r" commit -q -m "base"
}

# Helper: set a remote-tracking ref to current HEAD.
set_ref() { git -C "$1" update-ref "refs/remotes/$2" HEAD; }

# -----------------------------------------------------------------------------
# Case 1: in-sync — upstream/main == origin/main
# -----------------------------------------------------------------------------
r1="$(mktemp -d)" || { echo "mktemp -d failed" >&2; exit 1; }; make_repo "$r1"
set_ref "$r1" upstream/main
set_ref "$r1" origin/main
out1="$(bash "$fork_script" --project-dir "$r1")"
echo "$out1" | grep -q "^BEHIND=0$" || fail "case1 expected BEHIND=0, got:\n$out1"
echo "$out1" | grep -q "^AHEAD=0$" || fail "case1 expected AHEAD=0, got:\n$out1"
echo "$out1" | grep -q "^RECOMMENDED_STRATEGY=in-sync$" \
  || fail "case1 expected in-sync, got:\n$(echo "$out1" | grep STRATEGY)"
pass "in-sync fork (0 behind, 0 ahead) recommends in-sync"
rm -rf "$r1"

# -----------------------------------------------------------------------------
# Case 2: ahead-only — origin has a commit upstream lacks, upstream unchanged
# -----------------------------------------------------------------------------
r2="$(mktemp -d)" || { echo "mktemp -d failed" >&2; exit 1; }; make_repo "$r2"
set_ref "$r2" upstream/main   # upstream pinned at base
echo "fork-work" > "$r2/fork.txt"; git -C "$r2" add fork.txt; git -C "$r2" commit -q -m "feat: fork only"
set_ref "$r2" origin/main     # origin one ahead of upstream
out2="$(bash "$fork_script" --project-dir "$r2")"
echo "$out2" | grep -q "^BEHIND=0$" || fail "case2 expected BEHIND=0, got:\n$out2"
echo "$out2" | grep -q "^AHEAD=1$" || fail "case2 expected AHEAD=1, got:\n$out2"
echo "$out2" | grep -q "^RECOMMENDED_STRATEGY=ahead-only$" \
  || fail "case2 expected ahead-only, got:\n$(echo "$out2" | grep STRATEGY)"
pass "ahead-only fork (0 behind, 1 ahead) recommends ahead-only"
rm -rf "$r2"

# -----------------------------------------------------------------------------
# Case 3: fast-forward — upstream moved ahead, fork clean (behind only)
# -----------------------------------------------------------------------------
r3="$(mktemp -d)" || { echo "mktemp -d failed" >&2; exit 1; }; make_repo "$r3"
set_ref "$r3" origin/main     # origin pinned at base
echo "up-work" > "$r3/up.txt"; git -C "$r3" add up.txt; git -C "$r3" commit -q -m "upstream new"
set_ref "$r3" upstream/main   # upstream one ahead of origin
out3="$(bash "$fork_script" --project-dir "$r3")"
echo "$out3" | grep -q "^BEHIND=1$" || fail "case3 expected BEHIND=1, got:\n$out3"
echo "$out3" | grep -q "^AHEAD=0$" || fail "case3 expected AHEAD=0, got:\n$out3"
echo "$out3" | grep -q "^RECOMMENDED_STRATEGY=fast-forward$" \
  || fail "case3 expected fast-forward, got:\n$(echo "$out3" | grep STRATEGY)"
pass "behind-only fork (1 behind, 0 ahead) recommends fast-forward"
rm -rf "$r3"

# -----------------------------------------------------------------------------
# Case 4: diverged — both sides have unique commits → rebase
# -----------------------------------------------------------------------------
r4="$(mktemp -d)" || { echo "mktemp -d failed" >&2; exit 1; }; make_repo "$r4"
# upstream branch: base + upstream commit
echo "up" > "$r4/up.txt"; git -C "$r4" add up.txt; git -C "$r4" commit -q -m "upstream new"
set_ref "$r4" upstream/main
# go back to base, add a different fork commit for origin
git -C "$r4" reset -q --hard HEAD~1
echo "fork" > "$r4/fork.txt"; git -C "$r4" add fork.txt; git -C "$r4" commit -q -m "fork new"
set_ref "$r4" origin/main
out4="$(bash "$fork_script" --project-dir "$r4")"
echo "$out4" | grep -q "^BEHIND=1$" || fail "case4 expected BEHIND=1, got:\n$out4"
echo "$out4" | grep -q "^AHEAD=1$" || fail "case4 expected AHEAD=1, got:\n$out4"
echo "$out4" | grep -q "^RECOMMENDED_STRATEGY=rebase$" \
  || fail "case4 expected rebase, got:\n$(echo "$out4" | grep STRATEGY)"
pass "diverged fork (1 behind, 1 ahead) recommends rebase"
rm -rf "$r4"

# -----------------------------------------------------------------------------
# Case 5: not a fork — no upstream remote
# -----------------------------------------------------------------------------
r5="$(mktemp -d)" || { echo "mktemp -d failed" >&2; exit 1; }
git -C "$r5" init -q -b main
git -C "$r5" config user.email "t@e.com"; git -C "$r5" config user.name "T"
git -C "$r5" config commit.gpgsign false
echo x > "$r5/x"; git -C "$r5" add x; git -C "$r5" commit -q -m "base"
out5="$(bash "$fork_script" --project-dir "$r5")"
echo "$out5" | grep -q "^IS_FORK=false$" || fail "case5 expected IS_FORK=false, got:\n$out5"
echo "$out5" | grep -q "^RECOMMENDED_STRATEGY=not-a-fork$" \
  || fail "case5 expected not-a-fork, got:\n$(echo "$out5" | grep STRATEGY)"
pass "repo without upstream remote reports IS_FORK=false / not-a-fork"
rm -rf "$r5"

# Trailer invariants on a representative run.
echo "$out2" | grep -q "^=== GIT FORK WORKFLOW ===$" || fail "missing section header"
echo "$out2" | grep -q "^=== END GIT FORK WORKFLOW ===$" || fail "missing section footer"
echo "$out2" | grep -q "^STATUS=" || fail "missing STATUS trailer"
echo "$out2" | grep -q "^ISSUE_COUNT=" || fail "missing ISSUE_COUNT trailer"
pass "structured-output trailers present"

echo "ALL TESTS PASSED"
