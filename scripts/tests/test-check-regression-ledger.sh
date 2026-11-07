#!/usr/bin/env bash
# Regression tests for scripts/check-regression-ledger.sh and
# scripts/render-regression-ledger.sh (issue #2947).
#
# The ledger used to be one table in docs/regression-ledger.md, kept mergeable
# by `merge=union`. GitHub's server-side merge (`gh pr update-branch`, the
# mergeability check, "Update branch") ignores custom merge drivers, so two PRs
# that each appended a row conflicted there. Each entry is now its own file
# under docs/regression-ledger/, and the table is rendered on demand. Case 8
# is the acceptance criterion: two branches that each add an entry merge with
# `git merge-tree`, which uses no merge driver, and the merged tree is valid.
#
# Run: bash scripts/tests/test-check-regression-ledger.sh
# Exit 0 = all tests pass, Exit 1 = failures
set -uo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
GUARD="$repo_root/scripts/check-regression-ledger.sh"
RENDER="$repo_root/scripts/render-regression-ledger.sh"
CONTRACT="$repo_root/scripts/check-structured-output-contract.sh"
PASS=0
FAIL=0

WORK=$(mktemp -d) || { echo "mktemp -d failed" >&2; exit 1; }
if [ -z "$WORK" ] || [ ! -d "$WORK" ]; then echo "bad sandbox dir" >&2; exit 1; fi
trap 'rm -rf "$WORK"' EXIT

ok()    { printf '  PASS: %s\n' "$1"; PASS=$((PASS + 1)); }
notok() { printf '  FAIL: %s\n' "$1"; FAIL=$((FAIL + 1)); }

field() { grep -m1 "^$2=" <<<"$1" | cut -d= -f2-; }

# new_case <name>: a root with an index page (no table rows) and two entries.
new_case() {
  local d="$WORK/$1"
  mkdir -p "$d/docs/regression-ledger"
  printf '# Regression Ledger\n\nOne file per entry under docs/regression-ledger/.\n' \
    > "$d/docs/regression-ledger.md"
  printf '| first defect | first cause | first check | PR #9 |\n' \
    > "$d/docs/regression-ledger/9-first-defect.md"
  printf '| second defect | second cause | second check | issue #10 |\n' \
    > "$d/docs/regression-ledger/10-second-defect.md"
  printf '%s\n' "$d"
}

# assert_finding <desc> <dir> <want-count> [<want-type>]
assert_finding() {
  local desc="$1" dir="$2" want="$3" type="${4:-}" out got
  out=$(bash "$GUARD" "$dir" 2>&1)
  got=$(field "$out" ISSUE_COUNT)
  if [ "$got" != "$want" ]; then
    notok "$desc (want ISSUE_COUNT=$want, got '$got')"
    printf '%s\n' "$out" | sed 's/^/      /'
    return
  fi
  if [ -n "$type" ] && ! grep -q "TYPE=$type " <<<"$out"; then
    notok "$desc (no TYPE=$type in output)"
    return
  fi
  ok "$desc"
}

echo "TEST 1: a clean ledger is OK"
d=$(new_case clean)
assert_finding "two well-formed entries, no rows in the index" "$d" 0

echo "TEST 2: entry file names must be <number>-<slug>.md"
d=$(new_case bad-name)
printf '| x | y | z | #1 |\n' > "$d/docs/regression-ledger/no-number.md"
assert_finding "a name without a leading number is reported" "$d" 1 bad_name
d=$(new_case bad-name-case)
printf '| x | y | z | #1 |\n' > "$d/docs/regression-ledger/12-Upper_Case.md"
assert_finding "upper case and underscores are reported" "$d" 1 bad_name
d=$(new_case bad-name-ext)
printf '| x | y | z | #1 |\n' > "$d/docs/regression-ledger/12-entry.txt"
assert_finding "a non-.md file is reported" "$d" 1 bad_name

echo "TEST 3: an entry is exactly one table row"
d=$(new_case multi-line)
printf '| x | y |\n| z | #1 |\n' > "$d/docs/regression-ledger/12-two-lines.md"
assert_finding "a two-line entry is reported" "$d" 1 bad_entry
d=$(new_case not-a-row)
printf 'A defect described in prose.\n' > "$d/docs/regression-ledger/12-prose.md"
assert_finding "prose that is not a row is reported" "$d" 1 bad_entry
d=$(new_case empty-entry)
: > "$d/docs/regression-ledger/12-empty.md"
assert_finding "an empty entry is reported" "$d" 1 bad_entry
d=$(new_case header-row)
printf '| Issue | Root Cause | Check Added | Fixed In |\n' > "$d/docs/regression-ledger/0-header.md"
assert_finding "the table header committed as an entry is reported" "$d" 1 bad_entry

echo "TEST 4: a row appended to the old single-file table is reported"
d=$(new_case row-in-index)
printf '| stale | branch | appended here | #11 |\n' >> "$d/docs/regression-ledger.md"
assert_finding "a table row in docs/regression-ledger.md is reported" "$d" 1 row_in_index

echo "TEST 5: a missing or empty entry directory is an error"
d=$(new_case no-dir)
rm -rf "$d/docs/regression-ledger"
assert_finding "missing docs/regression-ledger/ is reported" "$d" 1 missing_entries
d=$(new_case empty-dir)
rm -f "$d/docs/regression-ledger/"*.md
assert_finding "an empty docs/regression-ledger/ is reported" "$d" 1 missing_entries

echo "TEST 6: --strict exit codes and the structured-output contract"
bash "$GUARD" --strict "$WORK/row-in-index" >/dev/null 2>&1; rc=$?
if [ "$rc" -eq 1 ]; then ok "--strict exits 1 on a finding"; else notok "--strict exits 1 on a finding (got $rc)"; fi
bash "$GUARD" --strict "$WORK/clean" >/dev/null 2>&1; rc=$?
if [ "$rc" -eq 0 ]; then ok "--strict exits 0 when clean"; else notok "--strict exits 0 when clean (got $rc)"; fi
bash "$GUARD" "$WORK/row-in-index" >/dev/null 2>&1; rc=$?
if [ "$rc" -eq 0 ]; then ok "without --strict a finding still exits 0"; else notok "without --strict a finding still exits 0 (got $rc)"; fi
for case_dir in clean row-in-index bad-name; do
  if bash "$GUARD" "$WORK/$case_dir" 2>&1 | bash "$CONTRACT" --validate >/dev/null 2>&1; then
    ok "$case_dir output passes check-structured-output-contract --validate"
  else
    notok "$case_dir output passes check-structured-output-contract --validate"
  fi
done

echo "TEST 7: the renderer emits a header and sorts entries numerically"
out=$(bash "$RENDER" --root "$WORK/clean" 2>&1); rc=$?
if [ "$rc" -eq 0 ]; then ok "render exits 0"; else notok "render exits 0 (got $rc)"; fi
if [ "$(sed -n 1p <<<"$out")" = "| Issue | Root Cause | Check Added | Fixed In |" ]; then
  ok "first line is the table header"
else
  notok "first line is the table header (got '$(sed -n 1p <<<"$out")')"
fi
if [ "$(sed -n 3p <<<"$out")" = "| first defect | first cause | first check | PR #9 |" ] &&
   [ "$(sed -n 4p <<<"$out")" = "| second defect | second cause | second check | issue #10 |" ]; then
  ok "entry 9 renders before entry 10 (numeric, not lexical, order)"
else
  notok "entry 9 renders before entry 10 (numeric, not lexical, order)"
fi
if [ "$(wc -l <<<"$out" | tr -d ' ')" = "4" ]; then ok "header + separator + one line per entry"; else notok "header + separator + one line per entry"; fi
bash "$RENDER" --root "$WORK/clean" --output "$WORK/rendered.md" >/dev/null 2>&1
if cmp -s "$WORK/rendered.md" <(printf '%s\n' "$out"); then ok "--output writes the same table"; else notok "--output writes the same table"; fi
bash "$RENDER" --root "$WORK/no-dir" >/dev/null 2>&1; rc=$?
if [ "$rc" -ne 0 ]; then ok "render fails on a missing entry directory"; else notok "render fails on a missing entry directory"; fi

echo "TEST 8: two branches that each add an entry merge with no merge driver (#2947 acceptance)"
g="$WORK/git"
mkdir -p "$g"
cp -R "$WORK/clean/docs" "$g/docs"
gitq() { git -C "$g" -c user.name=t -c user.email=t@example.invalid -c commit.gpgsign=false "$@" >/dev/null 2>&1; }
gitq init -q -b main
gitq add docs
gitq commit -q -m base
gitq switch -q -c pr-a
printf '| defect a | cause a | check a | #20 |\n' > "$g/docs/regression-ledger/20-defect-a.md"
gitq add docs
gitq commit -q -m a
gitq switch -q main
gitq switch -q -c pr-b
printf '| defect b | cause b | check b | #21 |\n' > "$g/docs/regression-ledger/21-defect-b.md"
gitq add docs
gitq commit -q -m b
# merge-tree performs the server-style merge: no checkout, no driver config.
if tree=$(git -C "$g" merge-tree --write-tree pr-a pr-b 2>/dev/null); then
  ok "merge-tree reports no conflict for two parallel entries"
  merged="$WORK/merged"
  mkdir -p "$merged"
  git -C "$g" archive "$tree" | tar -x -C "$merged"
  assert_finding "the merged tree passes the check" "$merged" 0
  rows=$(bash "$RENDER" --root "$merged" | grep -c '^| defect [ab] ')
  if [ "$rows" = "2" ]; then ok "the merged table renders both new entries"; else notok "the merged table renders both new entries (got $rows)"; fi
else
  notok "merge-tree reports no conflict for two parallel entries"
fi

echo "TEST 9: the live repository ledger passes"
out=$(bash "$GUARD" 2>&1)
if [ "$(field "$out" STATUS)" = "OK" ]; then
  ok "repo ledger STATUS=OK"
else
  notok "repo ledger STATUS=OK"
  printf '%s\n' "$out" | sed 's/^/      /' | head -20
fi
if [ "$(field "$out" ENTRY_COUNT)" -gt 400 ] 2>/dev/null; then
  ok "repo ledger carries the migrated entries (ENTRY_COUNT=$(field "$out" ENTRY_COUNT))"
else
  notok "repo ledger carries the migrated entries (ENTRY_COUNT=$(field "$out" ENTRY_COUNT))"
fi

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
