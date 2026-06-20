#!/usr/bin/env bash
# Regression test for preflight.sh (ADR-0016 extraction, #1558).
#
# Encodes the script's structured-output contract (the semantic invariant the
# skill depends on): the =/STATUS/ISSUE_COUNT envelope, the ahead/behind +
# uncommitted + stash + conflict facts, and the fixed recommendation decision
# tree (resolve-conflicts > commit-or-stash > rebase > ready). All cases run
# against a local fixture repo with --no-fetch --base main, so the test is
# hermetic (no remote, no gh).
#
# Exit 0 on success, non-zero on first failure.

set -uo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
preflight="${script_dir}/../preflight.sh"

fail() { echo "FAIL: $1" >&2; exit 1; }
pass() { echo "PASS: $1"; }

[ -f "$preflight" ] || fail "preflight.sh not found at $preflight"

# Fresh fixture repo on branch main with a configured identity.
make_repo() {
  local dir
  dir="$(mktemp -d)" || { echo "mktemp -d failed" >&2; exit 1; }
  git -C "$dir" init -q -b main
  git -C "$dir" config user.email "test@example.com"
  git -C "$dir" config user.name "Test"
  git -C "$dir" config commit.gpgsign false
  printf 'line\n' > "$dir/file.txt"
  git -C "$dir" add file.txt
  git -C "$dir" commit -q -m "initial"
  printf '%s' "$dir"
}

run() { bash "$preflight" --no-fetch --base main --project-dir "$1"; }

# -----------------------------------------------------------------------------
# Case 0: not a git repository -> STATUS=ERROR, exit 1
# -----------------------------------------------------------------------------
notrepo="$(mktemp -d)" || { echo "mktemp -d failed" >&2; exit 1; }
out0="$(bash "$preflight" --no-fetch --project-dir "$notrepo")"; rc0=$?
[ "$rc0" -eq 1 ] || fail "expected exit 1 outside a repo, got $rc0"
echo "$out0" | grep -q "^STATUS=ERROR$" || fail "expected STATUS=ERROR outside a repo:\n$out0"
echo "$out0" | grep -q "TYPE=not_a_repo" || fail "expected not_a_repo issue type:\n$out0"
rm -rf "$notrepo"
pass "non-repo emits STATUS=ERROR and exits 1"

# -----------------------------------------------------------------------------
# Case 1: clean, HEAD == base -> ready / OK, no divergence
# -----------------------------------------------------------------------------
r1="$(make_repo)"
out1="$(run "$r1")"; rc1=$?
[ "$rc1" -eq 0 ] || fail "clean repo should exit 0, got $rc1"
echo "$out1" | grep -q "^=== PREFLIGHT ===$"     || fail "missing section header:\n$out1"
echo "$out1" | grep -q "^=== END PREFLIGHT ===$" || fail "missing section footer:\n$out1"
echo "$out1" | grep -q "^FETCH=skipped$"         || fail "expected FETCH=skipped with --no-fetch:\n$out1"
echo "$out1" | grep -q "^BASE_RESOLVED=true$"    || fail "expected BASE_RESOLVED=true:\n$out1"
echo "$out1" | grep -q "^AHEAD=0$"               || fail "expected AHEAD=0:\n$out1"
echo "$out1" | grep -q "^BEHIND=0$"              || fail "expected BEHIND=0:\n$out1"
echo "$out1" | grep -q "^CONFLICTS=none$"        || fail "expected CONFLICTS=none:\n$out1"
echo "$out1" | grep -q "^RECOMMENDATION=ready$"  || fail "expected RECOMMENDATION=ready:\n$out1"
echo "$out1" | grep -q "^STATUS=OK$"             || fail "expected STATUS=OK:\n$out1"
echo "$out1" | grep -q "^ISSUE_COUNT=0$"         || fail "expected ISSUE_COUNT=0:\n$out1"
rm -rf "$r1"
pass "clean HEAD==base -> ready / OK"

# -----------------------------------------------------------------------------
# Case 2: behind base, no conflict -> rebase
# -----------------------------------------------------------------------------
r2="$(make_repo)"
git -C "$r2" checkout -q -b feature
git -C "$r2" checkout -q main
printf 'extra\n' > "$r2/other.txt"
git -C "$r2" add other.txt
git -C "$r2" commit -q -m "advance main"
git -C "$r2" checkout -q feature
out2="$(run "$r2")"
echo "$out2" | grep -q "^BEHIND=1$"               || fail "expected BEHIND=1:\n$out2"
echo "$out2" | grep -q "^AHEAD=0$"                || fail "expected AHEAD=0:\n$out2"
echo "$out2" | grep -q "^CONFLICTS=none$"         || fail "expected no conflict for disjoint change:\n$out2"
echo "$out2" | grep -q "^RECOMMENDATION=rebase$"  || fail "expected RECOMMENDATION=rebase:\n$out2"
echo "$out2" | grep -q "^STATUS=WARN$"            || fail "expected STATUS=WARN when behind:\n$out2"
rm -rf "$r2"
pass "behind base, no conflict -> rebase / WARN"

# -----------------------------------------------------------------------------
# Case 3: uncommitted changes (not behind, no conflict) -> commit-or-stash
# -----------------------------------------------------------------------------
r3="$(make_repo)"
printf 'dirty\n' >> "$r3/file.txt"
out3="$(run "$r3")"
echo "$out3" | grep -q "^UNCOMMITTED=1$"                  || fail "expected UNCOMMITTED=1:\n$out3"
echo "$out3" | grep -q "^BEHIND=0$"                       || fail "expected BEHIND=0:\n$out3"
echo "$out3" | grep -q "^RECOMMENDATION=commit-or-stash$" || fail "expected commit-or-stash:\n$out3"
rm -rf "$r3"
pass "uncommitted changes -> commit-or-stash"

# -----------------------------------------------------------------------------
# Case 4: conflicting divergence -> resolve-conflicts (precedence over behind)
# -----------------------------------------------------------------------------
r4="$(make_repo)"
git -C "$r4" checkout -q -b feature
printf 'feature-line\n' > "$r4/file.txt"
git -C "$r4" commit -q -am "feature edit"
git -C "$r4" checkout -q main
printf 'main-line\n' > "$r4/file.txt"
git -C "$r4" commit -q -am "main edit"
git -C "$r4" checkout -q feature
out4="$(run "$r4")"
echo "$out4" | grep -q "^CONFLICTS=detected$"                || fail "expected CONFLICTS=detected:\n$out4"
echo "$out4" | grep -q "^CONFLICT_FILES=.*file.txt"          || fail "expected file.txt in CONFLICT_FILES:\n$out4"
echo "$out4" | grep -q "^RECOMMENDATION=resolve-conflicts$"  || fail "expected resolve-conflicts (precedence):\n$out4"
echo "$out4" | grep -q "^STATUS=WARN$"                       || fail "expected STATUS=WARN on conflict:\n$out4"
rm -rf "$r4"
pass "conflicting divergence -> resolve-conflicts (beats behind)"

# -----------------------------------------------------------------------------
# Case 5: stash state is reported
# -----------------------------------------------------------------------------
r5="$(make_repo)"
printf 'wip\n' >> "$r5/file.txt"
git -C "$r5" stash -q
out5="$(run "$r5")"
echo "$out5" | grep -q "^STASH_COUNT=1$" || fail "expected STASH_COUNT=1:\n$out5"
rm -rf "$r5"
pass "stash state reported"

# -----------------------------------------------------------------------------
# Case 6: no --issue -> existing-work lookups stay inert (hermetic, no gh)
# -----------------------------------------------------------------------------
r6="$(make_repo)"
out6="$(run "$r6")"
echo "$out6" | grep -q "^ISSUE=none$"          || fail "expected ISSUE=none without --issue:\n$out6"
echo "$out6" | grep -q "^EXISTING_PRS=none$"   || fail "expected EXISTING_PRS=none without --issue:\n$out6"
echo "$out6" | grep -q "^BRANCH_MATCHES=none$" || fail "expected BRANCH_MATCHES=none without --issue:\n$out6"
rm -rf "$r6"
pass "no --issue keeps PR/issue lookup inert"

echo "ALL PASS"
