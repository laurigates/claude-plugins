#!/usr/bin/env bash
# Regression tests for scripts/resolve-additive-conflicts.py — deterministic
# (no-LLM) resolution of additive/union merge conflicts.
#
# Run: bash scripts/tests/test-resolve-additive-conflicts.sh
# Exit 0 = all tests pass, Exit 1 = failures
# shellcheck disable=SC2015   # file-level: `cond && pass || fail` is the deliberate test idiom (pass() returns 0)
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RESOLVER="$SCRIPT_DIR/resolve-additive-conflicts.py"
PASS=0
FAIL=0

pass() { printf "  PASS: %s\n" "$1"; PASS=$((PASS + 1)); }
fail() { printf "  FAIL: %s\n" "$1"; FAIL=$((FAIL + 1)); }

field() { grep -E "^$2=" <<<"$1" | cut -d= -f2; }

# Build a sandbox git repo with a conflict on table.md between two branches
# (theirs merged into ours, left in conflicted state). Echoes the repo dir.
make_conflict_repo() {
  local base="$1" ours="$2" theirs="$3"
  local repo def
  repo=$(mktemp -d) || return 1
  [ -n "$repo" ] && [ -d "$repo" ] || return 1
  (
    cd "$repo" || exit 1
    git init -q
    git config user.email t@e.com
    git config user.name t
    git config commit.gpgsign false
    git config merge.ff false
    def=$(git symbolic-ref --short HEAD)
    printf '%s' "$base" >table.md
    git add table.md
    git commit -qm base
    git switch -qc theirs
    printf '%s' "$theirs" >table.md
    git commit -qam theirs
    git switch -q "$def"
    git switch -qc ours
    printf '%s' "$ours" >table.md
    git commit -qam ours
    git merge --no-ff theirs >/dev/null 2>&1 || true
  )
  echo "$repo"
}

echo "=== resolve-additive-conflicts regression tests ==="

# --- Test 1: additive conflict (both append disjoint rows) → auto-resolved ---
BASE=$'| a |\n| b |\n'
OURS=$'| a |\n| b |\n| ours-row |\n'
THEIRS=$'| a |\n| b |\n| theirs-row |\n'
repo1=$(make_conflict_repo "$BASE" "$OURS" "$THEIRS")
[ -n "$repo1" ] && [ -d "$repo1" ] || { echo "setup failed" >&2; exit 1; }
out1=$(cd "$repo1" && python3 "$RESOLVER" 2>&1)
rc1=$?

[ "$(field "$out1" REMAINING_COUNT)" = "0" ] \
  && pass "additive: REMAINING_COUNT=0" \
  || fail "additive: expected REMAINING_COUNT=0, got '$(field "$out1" REMAINING_COUNT)'"
[ "$(field "$out1" RESOLVED_COUNT)" = "1" ] \
  && pass "additive: RESOLVED_COUNT=1" \
  || fail "additive: expected RESOLVED_COUNT=1, got '$(field "$out1" RESOLVED_COUNT)'"
[ "$(field "$out1" STATUS)" = "OK" ] \
  && pass "additive: STATUS=OK" \
  || fail "additive: expected STATUS=OK, got '$(field "$out1" STATUS)'"
[ "$rc1" = "0" ] && pass "additive: exit 0 (parallel-safe)" || fail "additive: expected exit 0, got $rc1"

markers1=$(grep -cE '^<<<<<<<|^>>>>>>>|^=======' "$repo1/table.md")
[ "$markers1" = "0" ] && pass "additive: no conflict markers remain" || fail "additive: $markers1 markers remain"
grep -q 'ours-row' "$repo1/table.md" && grep -q 'theirs-row' "$repo1/table.md" \
  && pass "additive: both rows present (union)" \
  || fail "additive: union dropped a row"

# --- Test 2: semantic conflict (same line edited differently) → left for LLM ---
BASE=$'line1\nshared\nline3\n'
OURS=$'line1\nshared-OURS\nline3\n'
THEIRS=$'line1\nshared-THEIRS\nline3\n'
repo2=$(make_conflict_repo "$BASE" "$OURS" "$THEIRS")
[ -n "$repo2" ] && [ -d "$repo2" ] || { echo "setup failed" >&2; exit 1; }
out2=$(cd "$repo2" && python3 "$RESOLVER" 2>&1)
rc2=$?

[ "$(field "$out2" REMAINING_COUNT)" = "1" ] \
  && pass "semantic: REMAINING_COUNT=1 (left for LLM)" \
  || fail "semantic: expected REMAINING_COUNT=1, got '$(field "$out2" REMAINING_COUNT)'"
[ "$(field "$out2" RESOLVED_COUNT)" = "0" ] \
  && pass "semantic: RESOLVED_COUNT=0 (not auto-touched)" \
  || fail "semantic: expected RESOLVED_COUNT=0, got '$(field "$out2" RESOLVED_COUNT)'"
[ "$(field "$out2" STATUS)" = "WARN" ] \
  && pass "semantic: STATUS=WARN" \
  || fail "semantic: expected STATUS=WARN, got '$(field "$out2" STATUS)'"
[ "$rc2" = "0" ] && pass "semantic: exit 0 (parallel-safe)" || fail "semantic: expected exit 0, got $rc2"
grep -qE '^<<<<<<<' "$repo2/table.md" \
  && pass "semantic: conflict markers preserved for LLM" \
  || fail "semantic: markers were removed (should be left intact)"

# --- Test 3: mixed run (one additive + one semantic) → partial, LLM for rest ---
mixed=$(mktemp -d) || exit 1
[ -n "$mixed" ] && [ -d "$mixed" ] || { echo "setup failed" >&2; exit 1; }
(
  cd "$mixed" || exit 1
  git init -q
  git config user.email t@e.com
  git config user.name t
  git config commit.gpgsign false
  git config merge.ff false
  def=$(git symbolic-ref --short HEAD)
  printf '| a |\n' >tbl.md
  printf 'shared\n' >code.txt
  git add .
  git commit -qm base
  git switch -qc theirs
  printf '| a |\n| theirs |\n' >tbl.md
  printf 'shared-THEIRS\n' >code.txt
  git commit -qam theirs
  git switch -q "$def"
  git switch -qc ours
  printf '| a |\n| ours |\n' >tbl.md
  printf 'shared-OURS\n' >code.txt
  git commit -qam ours
  git merge --no-ff theirs >/dev/null 2>&1 || true
)
out3=$(cd "$mixed" && python3 "$RESOLVER" 2>&1)
[ "$(field "$out3" RESOLVED_COUNT)" = "1" ] && [ "$(field "$out3" REMAINING_COUNT)" = "1" ] \
  && pass "mixed: 1 additive resolved, 1 semantic remaining" \
  || fail "mixed: expected RESOLVED=1 REMAINING=1, got RESOLVED=$(field "$out3" RESOLVED_COUNT) REMAINING=$(field "$out3" REMAINING_COUNT)"

rm -rf "$repo1" "$repo2" "$mixed"

echo "=== Results: $PASS passed, $FAIL failed ==="
[ "$FAIL" -eq 0 ]
