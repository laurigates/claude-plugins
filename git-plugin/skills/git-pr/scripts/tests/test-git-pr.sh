#!/usr/bin/env bash
# Regression test for git-pr.sh (issue #1552).
# Plants a tiny git repo with a base branch + a feature branch ahead of it, and
# asserts: a branch with an existing PR is detected vs a fresh branch; ahead-count
# readiness; stacked-dependent scan; closing-keyword audit. Fully offline via the
# fixture seams (no network, no live gh).
# Exit 0 on success, non-zero on failure.

set -uo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
pr_script="${script_dir}/../git-pr.sh"

fail() {
  echo "FAIL: $1" >&2
  exit 1
}

pass() {
  echo "PASS: $1"
}

if ! command -v jq >/dev/null 2>&1; then
  echo "SKIP: jq not installed; cannot run git-pr tests"
  exit 0
fi

[ -f "$pr_script" ] || fail "git-pr.sh not found at $pr_script"

repo="$(mktemp -d)"
work="$(mktemp -d)"
trap 'rm -rf "$repo" "$work"' EXIT

git -C "$repo" init -q -b main
git -C "$repo" config user.email "test@example.com"
git -C "$repo" config user.name "Test"
git -C "$repo" config commit.gpgsign false

echo "base" > "$repo/base.txt"
git -C "$repo" add base.txt
git -C "$repo" commit -q -m "chore: base"

# Simulate origin/main so base_ref=origin/main resolves without a remote fetch.
git -C "$repo" update-ref refs/remotes/origin/main HEAD

# Feature branch two commits ahead.
git -C "$repo" switch -q -c feature/work
echo "a" > "$repo/a.txt"; git -C "$repo" add a.txt; git -C "$repo" commit -q -m "feat: a"
echo "b" > "$repo/b.txt"; git -C "$repo" add b.txt; git -C "$repo" commit -q -m "feat: b"

export GIT_PR_NO_FETCH=1

# -----------------------------------------------------------------------------
# Case 1: fresh branch — no existing PR fixture → EXISTING_PR=none, PR_READY=true
# -----------------------------------------------------------------------------
export GIT_PR_EXISTING_PR_FIXTURE="${work}/none.json"
echo "null" > "$GIT_PR_EXISTING_PR_FIXTURE"
export GIT_PR_DEPENDENTS_FIXTURE="${work}/nodeps.json"
echo "[]" > "$GIT_PR_DEPENDENTS_FIXTURE"

out1="$(bash "$pr_script" --project-dir "$repo" --base origin/main)"
echo "$out1" | grep -q "^EXISTING_PR=none$" \
  || fail "fresh branch expected EXISTING_PR=none, got:\n$(echo "$out1" | grep '^EXISTING_PR')"
echo "$out1" | grep -q "^AHEAD_COUNT=2$" \
  || fail "expected AHEAD_COUNT=2, got:\n$(echo "$out1" | grep '^AHEAD_COUNT')"
echo "$out1" | grep -q "^PR_READY=true$" \
  || fail "expected PR_READY=true (2 commits ahead), got:\n$(echo "$out1" | grep '^PR_READY')"
echo "$out1" | grep -q "^STACK_PARENT=false$" \
  || fail "expected STACK_PARENT=false with empty dependents, got:\n$(echo "$out1" | grep '^STACK_PARENT')"
pass "fresh branch: no existing PR, ahead-count 2, PR_READY=true, not a stack parent"

# -----------------------------------------------------------------------------
# Case 2: branch with an existing PR → EXISTING_PR=<n>, state surfaced
# -----------------------------------------------------------------------------
echo '{"number":77,"state":"OPEN"}' > "${work}/existing.json"
export GIT_PR_EXISTING_PR_FIXTURE="${work}/existing.json"

out2="$(bash "$pr_script" --project-dir "$repo" --base origin/main)"
echo "$out2" | grep -q "^EXISTING_PR=77$" \
  || fail "expected EXISTING_PR=77, got:\n$(echo "$out2" | grep '^EXISTING_PR')"
echo "$out2" | grep -q "^EXISTING_PR_STATE=OPEN$" \
  || fail "expected EXISTING_PR_STATE=OPEN, got:\n$(echo "$out2" | grep '^EXISTING_PR_STATE')"
pass "branch with existing PR detected (#77, state via 'state' field not 'merged')"

# -----------------------------------------------------------------------------
# Case 3: stacked-PR dependents detected
# -----------------------------------------------------------------------------
cat > "${work}/deps.json" <<'JSON'
[{"number":88,"title":"downstream","headRefName":"feature/child"}]
JSON
export GIT_PR_DEPENDENTS_FIXTURE="${work}/deps.json"

out3="$(bash "$pr_script" --project-dir "$repo" --base origin/main)"
echo "$out3" | grep -q "^DEPENDENT_COUNT=1$" \
  || fail "expected DEPENDENT_COUNT=1, got:\n$(echo "$out3" | grep '^DEPENDENT_COUNT')"
echo "$out3" | grep -q "^STACK_PARENT=true$" \
  || fail "expected STACK_PARENT=true, got:\n$(echo "$out3" | grep '^STACK_PARENT')"
echo "$out3" | grep -q "DEPENDENT_PR=88 HEAD=feature/child" \
  || fail "expected dependent PR #88 listed, got:\n$(echo "$out3" | grep '^DEPENDENT_PR')"
pass "stacked-PR scan flags STACK_PARENT=true and lists dependent #88"

# -----------------------------------------------------------------------------
# Case 4: closing-keyword audit via --body-file
#   Body references #1 (Fixes), #2 (Resolves), #3 (Related only → not closing).
# -----------------------------------------------------------------------------
cat > "${work}/body.md" <<'MD'
## Summary
Adds X.

## Related Issues
Fixes #1
Resolves #2
Related: #3
MD

out4="$(bash "$pr_script" --project-dir "$repo" --base origin/main --body-file "${work}/body.md")"
echo "$out4" | grep -q "^BODY_NOT_AUTOCLOSING=#3$" \
  || fail "expected BODY_NOT_AUTOCLOSING=#3, got:\n$(echo "$out4" | grep '^BODY_NOT_AUTOCLOSING')"
echo "$out4" | grep -qE "^BODY_CLOSING=#1,#2$" \
  || fail "expected BODY_CLOSING=#1,#2, got:\n$(echo "$out4" | grep '^BODY_CLOSING')"
pass "closing-keyword audit: #1/#2 auto-close, #3 (Related) flagged not-auto-closing"

# Trailer invariants.
echo "$out4" | grep -q "^=== GIT PR ===$" || fail "missing section header"
echo "$out4" | grep -q "^=== END GIT PR ===$" || fail "missing section footer"
echo "$out4" | grep -q "^STATUS=" || fail "missing STATUS trailer"
echo "$out4" | grep -q "^ISSUE_COUNT=" || fail "missing ISSUE_COUNT trailer"
pass "structured-output trailers present"

echo "ALL TESTS PASSED"
