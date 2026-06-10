#!/usr/bin/env bash
# Regression test for blueprint-derive-tests.sh (issue #1553).
# Plants a tiny git repo (the injectable --project-dir seam) with a fix
# commit that carries no inline test file and a feat commit that DOES carry
# a test file, then asserts the semantic invariants: the untested fix is
# classified a CRITICAL coverage gap, the feat commit shipping a test is
# COVERED (not a gap), and a fix commit shipping a test is also COVERED.
# Exit 0 on success, non-zero on failure. SKIP (exit 0) if git/jq absent.

set -uo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
analyze_script="${script_dir}/../blueprint-derive-tests.sh"

fail() { echo "FAIL: $1" >&2; exit 1; }
pass() { echo "PASS: $1"; }

if ! command -v git >/dev/null 2>&1; then
  echo "SKIP: git not installed; cannot run blueprint-derive-tests tests"
  exit 0
fi

[ -f "$analyze_script" ] || fail "blueprint-derive-tests.sh not found at $analyze_script"

proj="$(mktemp -d)"
home="$(mktemp -d)"
trap 'rm -rf "$proj" "$home"' EXIT

git -C "$proj" init -q
git -C "$proj" config user.email "test@example.com"
git -C "$proj" config user.name "Test"
git -C "$proj" config commit.gpgsign false

# Commit 1: a fix with NO test file -> CRITICAL gap.
mkdir -p "${proj}/src"
echo "v1" > "${proj}/src/auth.js"
git -C "$proj" add src/auth.js
git -C "$proj" commit -q -m "fix(auth): handle null token"

# Commit 2: a feat WITH an inline test file -> COVERED (not a gap).
echo "feature" > "${proj}/src/widget.js"
echo "test" > "${proj}/src/widget.test.js"
git -C "$proj" add src/widget.js src/widget.test.js
git -C "$proj" commit -q -m "feat(widget): add widget"

# Commit 3: a fix WITH an inline test file -> COVERED (counter-case).
echo "v2" > "${proj}/src/parser.js"
echo "ptest" > "${proj}/src/parser.test.js"
git -C "$proj" add src/parser.js src/parser.test.js
git -C "$proj" commit -q -m "fix(parser): correct boundary"

out="$(bash "$analyze_script" --home-dir "$home" --project-dir "$proj")"

# Invariant 1: the untested fix is a CRITICAL gap.
echo "$out" | grep -q "^GAPS_CRITICAL=1$" \
  || fail "expected GAPS_CRITICAL=1 (the untested fix), got:\n$out"
echo "$out" | grep -q "TYPE=coverage_gap.*TYPE=fix SEVERITY=CRITICAL" \
  || fail "expected a CRITICAL coverage_gap issue for the fix, got:\n$out"
pass "untested fix commit is classified a CRITICAL coverage gap"

# Invariant 2: the feat shipping a test is COVERED, not a MEDIUM gap.
echo "$out" | grep -q "^GAPS_MEDIUM=0$" \
  || fail "expected GAPS_MEDIUM=0 (the feat shipped a test), got:\n$out"
echo "$out" | grep -q "^COVERED_COMMITS=2$" \
  || fail "expected COVERED_COMMITS=2 (feat+fix that shipped tests), got:\n$out"
pass "commits shipping inline tests are COVERED, not gaps"

# Invariant 3: counts and overall status reflect one critical gap.
echo "$out" | grep -q "^FIX_COMMITS=2$" \
  || fail "expected FIX_COMMITS=2, got:\n$out"
echo "$out" | grep -q "^FEAT_COMMITS=1$" \
  || fail "expected FEAT_COMMITS=1, got:\n$out"
echo "$out" | grep -q "^GAPS_TOTAL=1$" \
  || fail "expected GAPS_TOTAL=1, got:\n$out"
echo "$out" | grep -q "^STATUS=ERROR$" \
  || fail "expected STATUS=ERROR (a critical gap present), got:\n$out"
pass "commit classification counts and STATUS reflect the single critical gap"

# Counter-case: a repo whose only commit is a fully-tested fix -> no gaps, STATUS=OK.
proj2="$(mktemp -d)"
git -C "$proj2" init -q
git -C "$proj2" config user.email "test@example.com"
git -C "$proj2" config user.name "Test"
git -C "$proj2" config commit.gpgsign false
echo "x" > "${proj2}/lib.js"
echo "t" > "${proj2}/lib.test.js"
git -C "$proj2" add lib.js lib.test.js
git -C "$proj2" commit -q -m "fix(core): tested fix"
out2="$(bash "$analyze_script" --home-dir "$home" --project-dir "$proj2")"
rc2=$?
echo "$out2" | grep -q "^GAPS_TOTAL=0$" \
  || fail "expected GAPS_TOTAL=0 for a fully-tested repo, got:\n$out2"
echo "$out2" | grep -q "^STATUS=OK$" \
  || fail "expected STATUS=OK for a fully-tested repo, got:\n$out2"
[ "$rc2" -eq 0 ] || fail "expected exit 0 for a fully-tested repo, got $rc2"
rm -rf "$proj2"
pass "fully-tested repo yields no gaps, STATUS=OK, exit 0"

echo "ALL TESTS PASSED"
