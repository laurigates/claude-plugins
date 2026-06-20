#!/usr/bin/env bash
# Regression test for workflow-preflight.sh (issue #1558).
#
# Semantic invariant under test: the deterministic recommendation decision tree
# returns the correct RECOMMENDATION for each combination of booleans, computed
# offline against a planted git repo + canned gh JSON via the fixture seam
# (WORKFLOW_PREFLIGHT_FIXTURE + WORKFLOW_PREFLIGHT_NO_FETCH). No network, no gh.
#
# Cases:
#   (a) existing OPEN PR + clean tree   -> "continue ... or start fresh"
#   (b) merge conflicts detected        -> "Resolve conflicts"
#   (c) uncommitted + stash present     -> "Commit or stash"
#   (d) fresh branch, no PR, clean      -> "Ready to proceed"
#
# Exit 0 on success ("ALL TESTS PASSED"), non-zero on any failure.

set -uo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
preflight_script="${script_dir}/../workflow-preflight.sh"

fail() { echo "FAIL: $1" >&2; exit 1; }
pass() { echo "PASS: $1"; }

if ! command -v jq >/dev/null 2>&1; then
  echo "SKIP: jq not installed; cannot run workflow-preflight tests"
  exit 0
fi

[ -f "$preflight_script" ] || fail "workflow-preflight.sh not found at $preflight_script"

home_dir="$(mktemp -d)" || { echo "mktemp -d failed" >&2; exit 1; }
trap 'rm -rf "$home_dir"' EXIT

# Build a planted git repo with origin/main, a feature branch one commit ahead,
# and return its path. Isolated env so global git config can't interfere.
make_repo() {
  local root remote work
  root="$(mktemp -d)" || { echo "mktemp -d failed" >&2; exit 1; }
  remote="${root}/remote.git"
  work="${root}/work"

  git init --quiet --bare "$remote"

  git init --quiet "$work"
  git -C "$work" config user.email "test@example.com"
  git -C "$work" config user.name "Test"
  git -C "$work" config commit.gpgsign false
  git -C "$work" checkout -q -b main
  printf 'base\n' > "${work}/file.txt"
  git -C "$work" add file.txt
  git -C "$work" commit --quiet -m "base commit"
  git -C "$work" remote add origin "$remote"
  git -C "$work" push --quiet -u origin main

  # Feature branch one commit ahead of main.
  git -C "$work" checkout -q -b feature/issue-42
  printf 'base\nfeature line\n' > "${work}/file.txt"
  git -C "$work" add file.txt
  git -C "$work" commit --quiet -m "feature work"

  # Refresh remote-tracking refs without hitting the network at run time.
  git -C "$work" fetch --quiet origin

  echo "$root"
}

# ---------------------------------------------------------------------------
# Case (a): existing OPEN PR + clean tree -> continue-or-start-fresh
# ---------------------------------------------------------------------------
root_a="$(make_repo)"
work_a="${root_a}/work"
fix_a="$(mktemp -d)" || { echo "mktemp -d failed" >&2; exit 1; }
cat > "${fix_a}/issue.json" <<'JSON'
{"number":42,"title":"Fix the thing","state":"OPEN","labels":[]}
JSON
cat > "${fix_a}/pr-search.json" <<'JSON'
[{"number":99,"title":"fix: the thing","state":"OPEN","headRefName":"feature/issue-42"}]
JSON

out_a="$(WORKFLOW_PREFLIGHT_NO_FETCH=1 WORKFLOW_PREFLIGHT_FIXTURE="$fix_a" \
  bash "$preflight_script" --home-dir "$home_dir" --project-dir "$work_a" --issue 42)"

echo "$out_a" | grep -q "^EXISTING_PR_STATE=OPEN$" \
  || fail "(a) expected EXISTING_PR_STATE=OPEN, got:\n$out_a"
echo "$out_a" | grep -q "^RECOMMENDATION=Open PR #99 exists - continue on that branch or start fresh" \
  || fail "(a) expected continue-or-start-fresh recommendation, got:\n$out_a"
pass "(a) open PR + clean tree -> continue-or-start-fresh"
rm -rf "$root_a" "$fix_a"

# ---------------------------------------------------------------------------
# Case (b): merge conflicts detected -> "Resolve conflicts"
# ---------------------------------------------------------------------------
root_b="$(make_repo)"
work_b="${root_b}/work"
# Diverge origin/main on the SAME line the feature branch changed, so a
# merge-tree dry-run reports a real conflict.
git -C "$work_b" checkout -q main
printf 'base\nmain divergent line\n' > "${work_b}/file.txt"
git -C "$work_b" add file.txt
git -C "$work_b" commit --quiet -m "main diverges"
git -C "$work_b" push --quiet origin main
git -C "$work_b" fetch --quiet origin
git -C "$work_b" checkout -q feature/issue-42

out_b="$(WORKFLOW_PREFLIGHT_NO_FETCH=1 \
  bash "$preflight_script" --home-dir "$home_dir" --project-dir "$work_b")"

echo "$out_b" | grep -q "^CONFLICTS_DETECTED=true$" \
  || fail "(b) expected CONFLICTS_DETECTED=true, got:\n$out_b"
echo "$out_b" | grep -q "^RECOMMENDATION=Resolve conflicts with origin/main" \
  || fail "(b) expected resolve-conflicts recommendation, got:\n$out_b"
pass "(b) conflicts detected -> resolve-conflicts"
rm -rf "$root_b"

# ---------------------------------------------------------------------------
# Case (c): uncommitted changes + stash present -> "Commit or stash"
# ---------------------------------------------------------------------------
root_c="$(make_repo)"
work_c="${root_c}/work"
# Create a stash, then leave an uncommitted change in the tree.
printf 'base\nfeature line\nstashed change\n' > "${work_c}/file.txt"
git -C "$work_c" stash --quiet
printf 'base\nfeature line\nuncommitted change\n' > "${work_c}/file.txt"

out_c="$(WORKFLOW_PREFLIGHT_NO_FETCH=1 \
  bash "$preflight_script" --home-dir "$home_dir" --project-dir "$work_c")"

echo "$out_c" | grep -q "^UNCOMMITTED_CHANGES=true$" \
  || fail "(c) expected UNCOMMITTED_CHANGES=true, got:\n$out_c"
echo "$out_c" | grep -qE "^STASH_COUNT=[1-9]" \
  || fail "(c) expected STASH_COUNT>=1, got:\n$out_c"
echo "$out_c" | grep -q "^RECOMMENDATION=Commit or stash uncommitted changes before branching$" \
  || fail "(c) expected commit-or-stash recommendation, got:\n$out_c"
pass "(c) uncommitted + stash present -> commit-or-stash"
rm -rf "$root_c"

# ---------------------------------------------------------------------------
# Case (d): fresh branch, no PR, clean, up to date -> "Ready to proceed"
# ---------------------------------------------------------------------------
root_d="$(make_repo)"
work_d="${root_d}/work"
# Sit on main itself: clean, no divergence, no target issue.
git -C "$work_d" checkout -q main

out_d="$(WORKFLOW_PREFLIGHT_NO_FETCH=1 \
  bash "$preflight_script" --home-dir "$home_dir" --project-dir "$work_d")"

echo "$out_d" | grep -q "^EXISTING_PR_STATE=NONE$" \
  || fail "(d) expected EXISTING_PR_STATE=NONE, got:\n$out_d"
echo "$out_d" | grep -q "^UNCOMMITTED_CHANGES=false$" \
  || fail "(d) expected clean tree, got:\n$out_d"
echo "$out_d" | grep -q "^CONFLICTS_DETECTED=false$" \
  || fail "(d) expected no conflicts, got:\n$out_d"
echo "$out_d" | grep -q "^RECOMMENDATION=Ready to proceed$" \
  || fail "(d) expected ready-to-proceed recommendation, got:\n$out_d"
echo "$out_d" | grep -q "^STATUS=OK$" \
  || fail "(d) expected STATUS=OK on a clean fresh tree, got:\n$out_d"
pass "(d) fresh branch, no PR, clean -> ready-to-proceed"
rm -rf "$root_d"

echo "ALL TESTS PASSED"
