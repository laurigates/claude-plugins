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

# 10. Regression for #2411: a PR opened from a DIFFERENTLY-NAMED head ref must
#     still classify as landed, not stranded_no_pr. classify() alone can't
#     exercise this — the fix lives in collect()'s gh lookups — so this stubs
#     `gh`/`git` on PATH and runs the real script end-to-end, reproducing the
#     exact #2124 case from the issue (an emoji-named head ref whose tip SHA
#     equals claude/pr-2124-merge-midrgh's tip, but whose name never matches).
stub_dir="$tmp/stubs"
mkdir -p "$stub_dir"

cat > "$stub_dir/gh" <<'STUB'
#!/usr/bin/env bash
case "$*" in
  "repo view o/r --json defaultBranchRef --jq .defaultBranchRef.name")
    echo "main" ;;
  "api repos/o/r/branches --paginate --jq .[].name")
    echo "claude/pr-2124-merge-midrgh" ;;
  "api repos/o/r/branches/claude/pr-2124-merge-midrgh --jq .commit.sha")
    echo "4d2504df566ba7ceff95acb3401c16adfdec21c4" ;;
  "api repos/o/r/commits/4d2504df566ba7ceff95acb3401c16adfdec21c4 --jq .commit.committer.date[0:10]")
    echo "2026-07-27" ;;
  "api repos/o/r/compare/main...claude/pr-2124-merge-midrgh --jq .ahead_by")
    echo "3" ;;
  "pr list -R o/r --head claude/pr-2124-merge-midrgh --state all --limit 1 --json number,state,mergedAt,baseRefName")
    echo "[]" ;;
  "pr list -R o/r --state all --limit 100 --search 4d2504df566ba7ceff95acb3401c16adfdec21c4 --json number,state,mergedAt,headRefOid")
    echo '[{"number":2124,"state":"MERGED","mergedAt":"2026-07-27T11:14:41Z","headRefOid":"4d2504df566ba7ceff95acb3401c16adfdec21c4"}]' ;;
  *)
    echo "STUB: unhandled gh call: $*" >&2
    exit 1 ;;
esac
STUB
chmod +x "$stub_dir/gh"

cat > "$stub_dir/git" <<'STUB'
#!/usr/bin/env bash
# Force collect() into the gh-api ahead-count fallback (branch not fetched
# locally), so the fixture doesn't need a real git object for the fake SHA.
exit 1
STUB
chmod +x "$stub_dir/git"

sha_out="$(PATH="$stub_dir:$PATH" "$check" --repo o/r 2>&1)"

if grep -q 'VERDICT=stranded_no_pr' <<<"$sha_out"; then
  fail "PR opened from a differently-named head ref (#2124 shape) was WRONGLY reported as stranded_no_pr"
else
  pass "PR opened from a differently-named head ref is matched by tip SHA and not reported as stranded"
fi

grep -q '^LANDED=1$' <<<"$sha_out" && pass "SHA-matched merged PR counted as LANDED" || fail "SHA-matched merged PR not counted as LANDED (got: $(grep '^LANDED=' <<<"$sha_out"))"
grep -q '^STRANDED_NO_PR=0$' <<<"$sha_out" && pass "STRANDED_NO_PR=0 after SHA fallback match" || fail "STRANDED_NO_PR nonzero after SHA fallback match (got: $(grep '^STRANDED_NO_PR=' <<<"$sha_out"))"

# 11. Regression for #2478: every push-by-SHA in the rendered Recovery recipe
#     must spell the destination `refs/heads/<branch>`. `<sha>:<branch>` is
#     only accepted when the branch ALREADY exists on the remote — a bare
#     commit object on the left gives git no ref namespace to infer from — and
#     this recipe is pasted verbatim by whoever refiles the strand. The block
#     used to disagree with itself: the force-push line carried the short form
#     while the delete-recovery line two rows down carried the full one.
#     Counted, not grepped for a literal, so the pair cannot drift apart again.
body="$("$check" --fixture "$tmp/fixture.json" --issue-body)"
all_pushes="$(grep -cE 'git push[^`]*origin +"?(\$\{sha\}|<sha>):' <<<"$body" || true)"
full_pushes="$(grep -cE 'git push[^`]*origin +"?(\$\{sha\}|<sha>):refs/heads/' <<<"$body" || true)"
if [ "$all_pushes" -ge 1 ]; then
  pass "issue body still prescribes push-by-SHA ($all_pushes lines; assertion non-vacuous)"
else
  fail "no push-by-SHA line in --issue-body — the #2478 assertion would be vacuous"
fi
if [ "$all_pushes" = "$full_pushes" ]; then
  pass "every push-by-SHA in the recovery recipe names refs/heads/<branch>"
else
  fail "recovery recipe has $((all_pushes - full_pushes)) push-by-SHA line(s) without refs/heads/ (#2478): $(grep -E 'git push[^`]*origin +"?(\$\{sha\}|<sha>):' <<<"$body" | grep -v 'refs/heads/' || true)"
fi

[ "$fail" -eq 0 ] && echo "ALL TESTS PASSED" || echo "SOME TESTS FAILED"
exit "$fail"
