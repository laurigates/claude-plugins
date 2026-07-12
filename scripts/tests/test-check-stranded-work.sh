#!/usr/bin/env bash
# Regression test for scripts/check-stranded-work.sh.
#
# Drives the pure classify stage via --fixture, so it is hermetic: no network, no gh,
# no git remote. The fixture encodes the six branch shapes seen in the 2026-07-12
# sweep of this repo — including the two that MUST NOT be reported, which is where
# a naive implementation goes wrong.
# shellcheck disable=SC2015  # file-level: `grep -q … && pass … || fail …` is the deliberate
# test idiom here — `pass` always exits 0, so the `|| fail` branch only runs on a real miss.
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
check="$script_dir/check-stranded-work.sh"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

fail=0
pass() { echo "PASS: $1"; }
fail() { echo "FAIL: $1"; fail=1; }

cat > "$tmp/fixture.json" <<'JSON'
[
  {"repo":"o/r","branch":"feat/pi-installer-recipes","sha":"1258","ahead":2,"last_commit":"2026-07-12",
   "pr_number":2049,"pr_merged":false,"pr_closed":true,"base_exists":false},

  {"repo":"o/r","branch":"claude/pip-to-uv-hook","sha":"15e9","ahead":2,"last_commit":"2026-03-20",
   "pr_number":null,"pr_merged":false,"pr_closed":false,"base_exists":true},

  {"repo":"o/r","branch":"fix/taskwarrior-hyphenated-tags","sha":"16dc","ahead":2,"last_commit":"2026-05-06",
   "pr_number":1245,"pr_merged":false,"pr_closed":true,"base_exists":true},

  {"repo":"o/r","branch":"feat/configure-instrumentation","sha":"f736","ahead":3,"last_commit":"2026-07-05",
   "pr_number":1977,"pr_merged":true,"pr_closed":false,"base_exists":true},

  {"repo":"o/r","branch":"feat/pi-tier-installer","sha":"1318","ahead":1,"last_commit":"2026-07-12",
   "pr_number":2054,"pr_merged":false,"pr_closed":false,"base_exists":true}
]
JSON

out="$("$check" --fixture "$tmp/fixture.json")"

# 1. The auto-close shape: closed-unmerged AND base ref gone. This is the #2049 bug.
if grep -q 'BRANCH=feat/pi-installer-recipes .*VERDICT=stranded_autoclose' <<<"$out"; then
  pass "auto-closed stacked PR (base ref deleted) is reported as stranded"
else
  fail "auto-closed stacked PR was NOT reported"
fi

# 2. Branch with commits and no PR ever — no event fires for these, sweep-only.
if grep -q 'BRANCH=claude/pip-to-uv-hook .*VERDICT=stranded_no_pr' <<<"$out"; then
  pass "never-PR'd branch with unlanded commits is reported"
else
  fail "never-PR'd branch was NOT reported"
fi

# 3. NEGATIVE: a deliberate human close (base still alive) must NOT be reported.
#    11 of 26 dead branches in the real sweep were this shape. Reporting them
#    would bury the real strands in noise and train the reader to ignore the issue.
if grep -q 'fix/taskwarrior-hyphenated-tags' <<<"$out"; then
  fail "deliberate close (base ref alive) was WRONGLY reported as stranded"
else
  pass "deliberate close (base ref alive) is correctly ignored"
fi

# 4. NEGATIVE: a merged PR is landed, even though squash rewrote the SHA so the
#    branch still looks 'ahead'. Ancestry alone would misreport this.
if grep -q 'feat/configure-instrumentation' <<<"$out"; then
  fail "squash-merged branch was WRONGLY reported as stranded"
else
  pass "squash-merged branch (still ahead by SHA) is correctly ignored"
fi

# 5. NEGATIVE: an open PR is in-flight, not stranded.
if grep -q 'feat/pi-tier-installer VERDICT=stranded' <<<"$out"; then
  fail "open PR was WRONGLY reported as stranded"
else
  pass "open PR is correctly ignored"
fi

# 6. Counts and STATUS.
grep -q '^STRANDED_AUTOCLOSE=1$'  <<<"$out" && pass "STRANDED_AUTOCLOSE=1" || fail "wrong STRANDED_AUTOCLOSE"
grep -q '^STRANDED_NO_PR=1$'      <<<"$out" && pass "STRANDED_NO_PR=1"     || fail "wrong STRANDED_NO_PR"
grep -q '^CLOSED_DELIBERATE=1$'   <<<"$out" && pass "CLOSED_DELIBERATE=1"  || fail "wrong CLOSED_DELIBERATE"
grep -q '^LANDED=1$'              <<<"$out" && pass "LANDED=1"             || fail "wrong LANDED"
grep -q '^STATUS=WARN$'           <<<"$out" && pass "STATUS=WARN when strands exist" || fail "expected STATUS=WARN"

# 7. Clean repo → PASS, and --issue-body emits nothing (workflow skips issue creation).
cat > "$tmp/clean.json" <<'JSON'
[
  {"repo":"o/r","branch":"feat/live","sha":"aaaa","ahead":1,"last_commit":"2026-07-12",
   "pr_number":2054,"pr_merged":false,"pr_closed":false,"base_exists":true}
]
JSON
clean_out="$("$check" --fixture "$tmp/clean.json")"
grep -q '^STATUS=PASS$' <<<"$clean_out" && pass "STATUS=PASS with no strands" || fail "expected STATUS=PASS"

body="$("$check" --fixture "$tmp/clean.json" --issue-body)"
if [ -z "$body" ]; then
  pass "--issue-body emits nothing when clean (no spurious issue)"
else
  fail "--issue-body emitted content for a clean repo"
fi

# 8. NEGATIVE: a branch pushed today with no PR yet is someone mid-work, not a strand.
#    The live run against the real repo flagged exactly this (docs/adr-okf-mapping,
#    pushed the same day) — nagging in-flight work would make the audit noise.
today="$(date -u +%F)"
cat > "$tmp/inflight.json" <<JSON
[
  {"repo":"o/r","branch":"docs/adr-okf-mapping","sha":"bbbb","ahead":1,"last_commit":"$today",
   "pr_number":null,"pr_merged":false,"pr_closed":false,"base_exists":true}
]
JSON
inflight_out="$("$check" --fixture "$tmp/inflight.json")"
if grep -q 'VERDICT=stranded' <<<"$inflight_out"; then
  fail "branch pushed today (no PR yet) was WRONGLY reported as stranded"
else
  pass "branch pushed today (no PR yet) is treated as in-flight, not stranded"
fi
grep -q '^IN_FLIGHT=1$' <<<"$inflight_out" && pass "IN_FLIGHT=1" || fail "wrong IN_FLIGHT count"
grep -q '^STATUS=PASS$' <<<"$inflight_out" && pass "in-flight branch alone yields STATUS=PASS" || fail "in-flight branch should not WARN"

# ...but the SAME branch, aged past the grace period, IS a strand.
aged_out="$("$check" --fixture "$tmp/inflight.json" --min-age-days 0)"
grep -q 'VERDICT=stranded_no_pr' <<<"$aged_out" && pass "same branch past grace period IS reported" || fail "aged never-PR'd branch not reported"

# 9. --issue-body renders both sections when strands exist.
body="$("$check" --fixture "$tmp/fixture.json" --issue-body)"
grep -q 'Auto-closed with unlanded work' <<<"$body" && pass "issue body has auto-close section" || fail "missing auto-close section"
grep -q "Pushed but never PR'd"          <<<"$body" && pass "issue body has never-PR'd section" || fail "missing never-PR'd section"
grep -q 'cannot be reopened'             <<<"$body" && pass "issue body states PR cannot be reopened" || fail "missing reopen warning"

[ "$fail" -eq 0 ] && echo "ALL TESTS PASSED" || echo "SOME TESTS FAILED"
exit "$fail"
