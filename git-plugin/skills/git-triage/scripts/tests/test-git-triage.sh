#!/usr/bin/env bash
# Regression test for git-triage.sh (issue #1552).
# Proves the pure first-match PR categorizer reads the enum fields correctly:
# a draft PR, a CONFLICTING PR, a FAILURE-check PR, and a mergeable+approved+
# passing PR each land in the correct category. Also checks closing-keyword
# extraction and age computation. Runs fully offline via the fixture seam.
# Exit 0 on success, non-zero on failure.

set -uo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
triage_script="${script_dir}/../git-triage.sh"

fail() {
  echo "FAIL: $1" >&2
  exit 1
}

pass() {
  echo "PASS: $1"
}

if ! command -v jq >/dev/null 2>&1; then
  echo "SKIP: jq not installed; cannot run git-triage tests"
  exit 0
fi

[ -f "$triage_script" ] || fail "git-triage.sh not found at $triage_script"

work_dir="$(mktemp -d)"
trap 'rm -rf "$work_dir"' EXIT

# Fixed "now" so ages are deterministic. 2026-06-10T00:00:00Z = 1781308800.
export GIT_TRIAGE_NOW_EPOCH=1781308800
export GIT_TRIAGE_NO_FETCH=1

# -----------------------------------------------------------------------------
# Planted PR fixture: one PR per category the first-match table must produce.
#   #1 draft                → draft (even though checks fail / conflicting)
#   #2 conflicting (not draft, checks pass) → needs-rebase
#   #3 FAILURE check (not draft, clean)     → needs-fix
#   #4 mergeable+CLEAN+APPROVED+SUCCESS     → ready-to-merge
#   #5 review null, checks pass, fresh      → awaiting-review
#   #6 review null, clean, old (>30d)       → stale  (updatedAt far in past)
# -----------------------------------------------------------------------------
prs_fixture="${work_dir}/prs.json"
cat > "$prs_fixture" <<'JSON'
[
  {"number":1,"title":"draft work","updatedAt":"2026-06-09T00:00:00Z","isDraft":true,
   "mergeable":"CONFLICTING","mergeStateStatus":"DIRTY","reviewDecision":null,
   "statusCheckRollup":[{"conclusion":"FAILURE"}],"body":"Fixes #100"},
  {"number":2,"title":"conflicting","updatedAt":"2026-06-09T00:00:00Z","isDraft":false,
   "mergeable":"CONFLICTING","mergeStateStatus":"DIRTY","reviewDecision":"APPROVED",
   "statusCheckRollup":[{"conclusion":"SUCCESS"}],"body":"Closes #200"},
  {"number":3,"title":"failing checks","updatedAt":"2026-06-09T00:00:00Z","isDraft":false,
   "mergeable":"MERGEABLE","mergeStateStatus":"CLEAN","reviewDecision":"APPROVED",
   "statusCheckRollup":[{"conclusion":"SUCCESS"},{"conclusion":"FAILURE"}],"body":""},
  {"number":4,"title":"ready","updatedAt":"2026-06-09T00:00:00Z","isDraft":false,
   "mergeable":"MERGEABLE","mergeStateStatus":"CLEAN","reviewDecision":"APPROVED",
   "statusCheckRollup":[{"conclusion":"SUCCESS"}],"body":"Resolves #300\nRelated: #301"},
  {"number":5,"title":"awaiting","updatedAt":"2026-06-09T00:00:00Z","isDraft":false,
   "mergeable":"MERGEABLE","mergeStateStatus":"CLEAN","reviewDecision":null,
   "statusCheckRollup":[{"conclusion":"SUCCESS"}],"body":""},
  {"number":6,"title":"old no review","updatedAt":"2026-01-01T00:00:00Z","isDraft":false,
   "mergeable":"MERGEABLE","mergeStateStatus":"BLOCKED","reviewDecision":"CHANGES_REQUESTED",
   "statusCheckRollup":[{"conclusion":"SUCCESS"}],"body":""}
]
JSON

export GIT_TRIAGE_PRS_FIXTURE="$prs_fixture"

out="$(bash "$triage_script" --type prs --days-stale-pr 30)"

assert_cat() {
  local num="$1" want="$2"
  echo "$out" | grep -q "^PR_${num}_CATEGORY=${want}$" \
    || fail "PR #${num} expected category=${want}, got:\n$(echo "$out" | grep "^PR_${num}_CATEGORY=")"
}

assert_cat 1 draft
pass "draft PR categorized as draft (overrides failing/conflicting)"

assert_cat 2 needs-rebase
pass "CONFLICTING PR categorized as needs-rebase (statusCheckRollup SUCCESS not misread)"

assert_cat 3 needs-fix
pass "PR with a FAILURE in statusCheckRollup[].conclusion categorized as needs-fix"

assert_cat 4 ready-to-merge
pass "mergeable+CLEAN+APPROVED+SUCCESS PR categorized as ready-to-merge"

assert_cat 5 awaiting-review
pass "null-review + passing checks PR categorized as awaiting-review"

assert_cat 6 changes-requested
pass "CHANGES_REQUESTED PR categorized as changes-requested"

# Closing-keyword extraction on PR #4 should find #300 (Resolves) but NOT #301 (Related).
echo "$out" | grep -q "^PR_4_CLOSES=#300$" \
  || fail "PR #4 closing keywords expected '#300', got:\n$(echo "$out" | grep '^PR_4_CLOSES=')"
pass "closing-keyword extraction finds Resolves #300, excludes Related #301"

# Age computation: PR #6 updated 2026-01-01, now 2026-06-10 → ~160 days, stale-eligible.
pr6_age=$(echo "$out" | grep "^PR_6_AGE_DAYS=" | cut -d= -f2)
[ "$pr6_age" -gt 30 ] 2>/dev/null \
  || fail "PR #6 age expected >30 days, got: $pr6_age"
pass "age computed from updatedAt (PR #6 = ${pr6_age}d > 30)"

# Trailer invariants.
echo "$out" | grep -q "^=== GIT TRIAGE ===$" || fail "missing section header"
echo "$out" | grep -q "^=== END GIT TRIAGE ===$" || fail "missing section footer"
echo "$out" | grep -q "^STATUS=" || fail "missing STATUS trailer"
echo "$out" | grep -q "^ISSUE_COUNT=" || fail "missing ISSUE_COUNT trailer"
pass "structured-output trailers present"

# -----------------------------------------------------------------------------
# Issues section via the issues fixture seam: age + stale-candidate flag.
# -----------------------------------------------------------------------------
issues_fixture="${work_dir}/issues.json"
cat > "$issues_fixture" <<'JSON'
[
  {"number":42,"title":"old issue references PR #99","body":"see #99","labels":[],
   "createdAt":"2025-06-01T00:00:00Z","updatedAt":"2025-06-01T00:00:00Z",
   "comments":[],"assignees":[],"author":{"login":"x"}},
  {"number":13,"title":"fresh","body":"recent work","labels":[],
   "createdAt":"2026-06-05T00:00:00Z","updatedAt":"2026-06-05T00:00:00Z",
   "comments":[{"id":1}],"assignees":[],"author":{"login":"y"}}
]
JSON

unset GIT_TRIAGE_PRS_FIXTURE
export GIT_TRIAGE_ISSUES_FIXTURE="$issues_fixture"

iout="$(bash "$triage_script" --type issues --days-stale-issue 90)"

echo "$iout" | grep -q "^ISSUE_42_STALE_CANDIDATE=true$" \
  || fail "issue #42 (>1yr old) expected STALE_CANDIDATE=true, got:\n$(echo "$iout" | grep '^ISSUE_42_STALE')"
echo "$iout" | grep -q "^ISSUE_13_STALE_CANDIDATE=false$" \
  || fail "issue #13 (fresh) expected STALE_CANDIDATE=false, got:\n$(echo "$iout" | grep '^ISSUE_13_STALE')"
pass "issue stale-candidate flag tracks age vs --days-stale-issue"

echo "$iout" | grep -q "^ISSUE_42_REFS=#99$" \
  || fail "issue #42 expected REFS=#99, got:\n$(echo "$iout" | grep '^ISSUE_42_REFS')"
pass "issue referenced-PR extraction finds #99"

# -----------------------------------------------------------------------------
# Enhancement #2480: the issue half must emit a title, so the collector's own
# output is readable without a second `gh issue list` pass purely to recover a
# field the first call already fetched.
#
# The same fixture exercises the empty-field column shift the title column would
# otherwise land in: `read` with a tab IFS collapses consecutive tabs, so before
# the `none` guard an issue with no `#N` references reported the comment count
# as its REFS and an empty COMMENTS (and would have reported garbage as TITLE).
# Issue #77 below has no references, two comments, and a title carrying a tab,
# an `=`, a backtick and a `#`-ref-lookalike inside a code span.
# -----------------------------------------------------------------------------
titles_fixture="${work_dir}/issues-2480.json"
cat > "$titles_fixture" <<'JSON'
[
  {"number":77,"title":"fix(x):\tKEY=VALUE `--flag` breaks","body":"plain text, no refs","labels":[],
   "createdAt":"2026-06-01T00:00:00Z","updatedAt":"2026-06-05T00:00:00Z",
   "comments":[{"id":1},{"id":2}],"assignees":[],"author":{"login":"x"}},
  {"number":78,"title":"refactor collector","body":"supersedes #99","labels":[],
   "createdAt":"2026-06-01T00:00:00Z","updatedAt":"2026-06-05T00:00:00Z",
   "comments":[],"assignees":[],"author":{"login":"y"}}
]
JSON

export GIT_TRIAGE_ISSUES_FIXTURE="$titles_fixture"
tout="$(bash "$triage_script" --type issues --days-stale-issue 90)"

echo "$tout" | grep -q "^ISSUE_78_TITLE=refactor collector$" \
  || fail "#2480: issue #78 expected TITLE=refactor collector, got:\n$(echo "$tout" | grep '^ISSUE_78_TITLE')"
pass "#2480: issue title emitted as ISSUE_<n>_TITLE"

# Tab sanitized to a space; the rest of the title survives verbatim on one line.
# shellcheck disable=SC2016  # the backticks are literal title text in the fixture
echo "$tout" | grep -q '^ISSUE_77_TITLE=fix(x): KEY=VALUE `--flag` breaks$' \
  || fail "#2480: issue #77 title expected tab-sanitized and intact, got:\n$(echo "$tout" | grep '^ISSUE_77_TITLE')"
pass "#2480: tabs in a title are sanitized, KEY=VALUE line stays single-line"

# Every emitted title key must be on its own line — one TITLE per fetched issue.
title_lines=$(echo "$tout" | grep -c "^ISSUE_[0-9]*_TITLE=")
[ "$title_lines" -eq 2 ] \
  || fail "#2480: expected 2 ISSUE_<n>_TITLE lines, got ${title_lines}"
pass "#2480: one TITLE line per fetched issue"

# Column-shift guard: an issue with no references reports REFS=none and its
# real comment count, not the count-as-refs / empty-comments shift.
echo "$tout" | grep -q "^ISSUE_77_REFS=none$" \
  || fail "#2480: issue #77 (no refs) expected REFS=none, got:\n$(echo "$tout" | grep '^ISSUE_77_REFS')"
echo "$tout" | grep -q "^ISSUE_77_COMMENTS=2$" \
  || fail "#2480: issue #77 expected COMMENTS=2 (empty refs must not shift columns), got:\n$(echo "$tout" | grep '^ISSUE_77_COMMENTS')"
pass "#2480: empty refs field does not shift the COMMENTS/TITLE columns"

# Refs extraction still works alongside the new column.
echo "$tout" | grep -q "^ISSUE_78_REFS=#99$" \
  || fail "#2480: issue #78 expected REFS=#99, got:\n$(echo "$tout" | grep '^ISSUE_78_REFS')"
pass "#2480: referenced-PR extraction unaffected by the title column"

# -----------------------------------------------------------------------------
# Regression for #1627: a bot PR with a large multi-line body (embedded tabs +
# newlines) and an empty-string reviewDecision. Before the fix, the body was
# packed into the categorization @tsv row as the 8th field; embedded tabs slid
# every column right, so WORST_CHECK held the body, REVIEW held the worst-check
# conclusion, and the PR fell through to `uncategorized`. The body now travels
# in its own jq pass keyed by PR number, and empty-string reviewDecision is
# normalized to null — so a passing, no-review bot PR lands in awaiting-review
# and its enum columns stay clean.
# -----------------------------------------------------------------------------
prs1627_fixture="${work_dir}/prs-1627.json"
cat > "$prs1627_fixture" <<'JSON'
[
  {"number":1202,"title":"chore(deps): bump foo","updatedAt":"2026-06-09T00:00:00Z","isDraft":false,
   "mergeable":"MERGEABLE","mergeStateStatus":"CLEAN","reviewDecision":"",
   "statusCheckRollup":[{"conclusion":"SUCCESS"}],
   "body":"Bumps foo from 1.0 to 2.0.\n\n| Package\tOld\tNew |\n|---|---|---|\n| foo\t1.0\t2.0 |\n\nThis closes #4242 and also Fixes #4243.\n\n<details>\n<summary>Commits</summary>\n- abc\tdef\tghi\n</details>"}
]
JSON

unset GIT_TRIAGE_ISSUES_FIXTURE
export GIT_TRIAGE_PRS_FIXTURE="$prs1627_fixture"

rout="$(bash "$triage_script" --type prs --days-stale-pr 30)"

# WORST_CHECK must hold a real conclusion enum, never PR body text.
echo "$rout" | grep -q "^PR_1202_WORST_CHECK=SUCCESS$" \
  || fail "PR #1202 WORST_CHECK expected SUCCESS (body must not bleed into the enum), got:\n$(echo "$rout" | grep '^PR_1202_WORST_CHECK=')"
pass "#1627: multi-line body does not shift WORST_CHECK column"

# REVIEW must be the normalized null, never the worst-check conclusion.
echo "$rout" | grep -q "^PR_1202_REVIEW=null$" \
  || fail "PR #1202 REVIEW expected null (empty-string normalized), got:\n$(echo "$rout" | grep '^PR_1202_REVIEW=')"
pass "#1627: empty-string reviewDecision normalized to null"

# With clean columns the PR categorizes correctly instead of uncategorized.
echo "$rout" | grep -q "^PR_1202_CATEGORY=awaiting-review$" \
  || fail "PR #1202 expected category=awaiting-review, got:\n$(echo "$rout" | grep '^PR_1202_CATEGORY=')"
pass "#1627: passing no-review bot PR categorizes as awaiting-review (not uncategorized)"

# Closing keywords still extracted from the multi-line body, in its own pass.
echo "$rout" | grep -q "^PR_1202_CLOSES=#4242,#4243$" \
  || fail "PR #1202 CLOSES expected '#4242,#4243', got:\n$(echo "$rout" | grep '^PR_1202_CLOSES=')"
pass "#1627: closing-keyword extraction survives the separate-pass refactor"

# The body itself must never appear verbatim in the KEY=VALUE output.
if echo "$rout" | grep -q "Bumps foo from"; then
  fail "#1627: PR body leaked into the structured output"
fi
pass "#1627: PR body never leaks into KEY=VALUE output"

# -----------------------------------------------------------------------------
# Enhancement #1628: when ≥2 bot-authored needs-fix PRs share an identical
# failing-check signature, they almost always have ONE shared root cause (e.g.
# Dependabot can't update bun.lock → every npm-bump PR fails the frozen-lockfile
# step before lint/typecheck run). The script rolls them into a single
# SYSTEMATIC_FAILURE_* hint. The fixture below mixes:
#   #1202,#1203,#1204  bot PRs, identical signature (orders vary)  → grouped
#   #1300              human PR, same signature                    → excluded (not a bot)
#   #1301              bot PR, solo "E2E" signature                → excluded (count 1)
# Signature names are sorted by `unique`, so input order does not matter.
# -----------------------------------------------------------------------------
prs1628_fixture="${work_dir}/prs-1628.json"
cat > "$prs1628_fixture" <<'JSON'
[
  {"number":1202,"title":"chore(deps): bump a","updatedAt":"2026-06-09T00:00:00Z","isDraft":false,
   "mergeable":"MERGEABLE","mergeStateStatus":"CLEAN","reviewDecision":"",
   "author":{"login":"dependabot[bot]","is_bot":true},
   "statusCheckRollup":[{"name":"Lint","conclusion":"FAILURE"},{"name":"Type Check","conclusion":"FAILURE"},{"name":"Unit Tests","conclusion":"FAILURE"}],"body":""},
  {"number":1203,"title":"chore(deps): bump b","updatedAt":"2026-06-09T00:00:00Z","isDraft":false,
   "mergeable":"MERGEABLE","mergeStateStatus":"CLEAN","reviewDecision":"",
   "author":{"login":"dependabot[bot]","is_bot":true},
   "statusCheckRollup":[{"name":"Type Check","conclusion":"FAILURE"},{"name":"Lint","conclusion":"FAILURE"},{"name":"Unit Tests","conclusion":"FAILURE"}],"body":""},
  {"number":1204,"title":"chore(deps): bump c","updatedAt":"2026-06-09T00:00:00Z","isDraft":false,
   "mergeable":"MERGEABLE","mergeStateStatus":"CLEAN","reviewDecision":"",
   "author":{"login":"renovate[bot]"},
   "statusCheckRollup":[{"name":"Unit Tests","conclusion":"FAILURE"},{"name":"Lint","conclusion":"FAILURE"},{"name":"Type Check","conclusion":"FAILURE"}],"body":""},
  {"number":1300,"title":"human fix","updatedAt":"2026-06-09T00:00:00Z","isDraft":false,
   "mergeable":"MERGEABLE","mergeStateStatus":"CLEAN","reviewDecision":"REVIEW_REQUIRED",
   "author":{"login":"alice"},
   "statusCheckRollup":[{"name":"Lint","conclusion":"FAILURE"},{"name":"Type Check","conclusion":"FAILURE"},{"name":"Unit Tests","conclusion":"FAILURE"}],"body":""},
  {"number":1301,"title":"chore(deps): solo","updatedAt":"2026-06-09T00:00:00Z","isDraft":false,
   "mergeable":"MERGEABLE","mergeStateStatus":"CLEAN","reviewDecision":"",
   "author":{"login":"dependabot[bot]","is_bot":true},
   "statusCheckRollup":[{"name":"E2E","conclusion":"FAILURE"}],"body":""}
]
JSON

unset GIT_TRIAGE_ISSUES_FIXTURE
export GIT_TRIAGE_PRS_FIXTURE="$prs1628_fixture"

sout="$(bash "$triage_script" --type prs --days-stale-pr 30)"

# Exactly one systematic-failure group is emitted.
echo "$sout" | grep -q "^SYSTEMATIC_FAILURE_COUNT=1$" \
  || fail "#1628 expected SYSTEMATIC_FAILURE_COUNT=1, got:\n$(echo "$sout" | grep '^SYSTEMATIC_FAILURE_COUNT=')"
pass "#1628: exactly one systematic-failure group emitted"

# The group lists the three bot PRs with the shared signature.
echo "$sout" | grep -q "^SYSTEMATIC_FAILURE_1_PRS=#1202,#1203,#1204$" \
  || fail "#1628 expected grouped PRs '#1202,#1203,#1204', got:\n$(echo "$sout" | grep '^SYSTEMATIC_FAILURE_1_PRS=')"
pass "#1628: the three bot PRs sharing a signature are grouped (order-independent)"

# The signature is the sorted, |-joined failing-check names.
echo "$sout" | grep -q "^SYSTEMATIC_FAILURE_1_SIGNATURE=Lint|Type Check|Unit Tests$" \
  || fail "#1628 expected signature 'Lint|Type Check|Unit Tests', got:\n$(echo "$sout" | grep '^SYSTEMATIC_FAILURE_1_SIGNATURE=')"
pass "#1628: signature is the sorted |-joined failing-check names"

# A human-authored PR with the SAME signature is not folded into the bot group.
if echo "$sout" | grep -q "#1300"; then
  fail "#1628: human-authored PR #1300 must not be grouped as a systematic bot failure"
fi
pass "#1628: human-authored PR with the same signature is excluded"

# A bot PR whose signature is unique (count 1) is not grouped.
if echo "$sout" | grep -q "#1301"; then
  fail "#1628: solo-signature bot PR #1301 must not be grouped (count 1)"
fi
pass "#1628: solo-signature bot PR is excluded (needs >=2 to be systematic)"

# -----------------------------------------------------------------------------
# Regression for #2714: the rollup counters contradicted the per-item output
# (ISSUE_COUNT=0 four lines below ten populated issue blocks), and --batch
# truncated silently (10 of 68 open issues fetched, nothing said so).
#
#   (a) the DOMAIN count ISSUES_FETCHED must equal the number of emitted
#       ISSUE_<n>_TITLE blocks — asserted by VALUE, not by key presence (the
#       only prior counter check, above, asserts ISSUE_COUNT merely exists);
#   (b) ISSUES_TOTAL carries the unbounded open count and ISSUES_TRUNCATED /
#       TRUNCATED say whether the batch dropped anything — paired with the twin
#       (total == fetched -> false) so a collector hardwired to "true" fails;
#   (c) ISSUE_COUNT keeps its structured-script-output meaning (the collector's
#       own diagnostics): 0 on a clean fixture, 1 on invalid JSON, moving
#       independently of ISSUES_FETCHED — the two keys are provably distinct.
#
# The counts fixtures reproduce the REAL response of the GraphQL query the
# script issues, captured live 2026-09-23 against laurigates/claude-plugins and
# ForumViriumHelsinki/infrastructure; only the integers differ.
# -----------------------------------------------------------------------------
counts_fixture() {  # counts_fixture <path> <issues_total> <prs_total>
  printf '{"data":{"repository":{"issues":{"totalCount":%s},"pullRequests":{"totalCount":%s}}}}\n' \
    "$2" "$3" > "$1"
}
line_value() {  # line_value <output> <KEY> -> value of the first ^KEY= line
  grep -m1 "^$2=" <<<"$1" | cut -d= -f2-
}
assert_line() {  # assert_line <output> <exact line> <label>
  grep -qxF -- "$2" <<<"$1" \
    || fail "$3: expected line '$2', got: '$(grep -m1 "^${2%%=*}=" <<<"$1")'"
}
refute_key() {  # refute_key <output> <KEY> <label>
  if grep -q "^$2=" <<<"$1"; then
    fail "$3: key $2 must not be emitted, got: '$(grep -m1 "^$2=" <<<"$1")'"
  fi
}

unset GIT_TRIAGE_PRS_FIXTURE
export GIT_TRIAGE_ISSUES_FIXTURE="$issues_fixture"   # two issues: #42, #13

# (b) total > fetched -> truncated.
counts_fixture "${work_dir}/counts-68-3.json" 68 3
export GIT_TRIAGE_COUNTS_FIXTURE="${work_dir}/counts-68-3.json"
trunc_out="$(bash "$triage_script" --type issues --batch 2)"

# (a) the domain count equals the emitted blocks, by value.
title_blocks=$(grep -c '^ISSUE_[0-9]*_TITLE=' <<<"$trunc_out")
fetched_value=$(line_value "$trunc_out" ISSUES_FETCHED)
[ "$title_blocks" -eq 2 ] \
  || fail "#2714: fixture should emit 2 ISSUE_<n>_TITLE blocks, got ${title_blocks}"
[ "$fetched_value" = "$title_blocks" ] \
  || fail "#2714: ISSUES_FETCHED='${fetched_value}' must equal the ${title_blocks} emitted ISSUE_<n>_TITLE blocks"
pass "#2714 (a): ISSUES_FETCHED equals the number of emitted issue blocks (${title_blocks})"

assert_line "$trunc_out" "ISSUES_TOTAL=68" "#2714 (b)"
assert_line "$trunc_out" "ISSUES_TRUNCATED=true" "#2714 (b)"
assert_line "$trunc_out" "TRUNCATED=true" "#2714 (b)"
pass "#2714 (b): 2 of 68 fetched reports ISSUES_TOTAL=68 and TRUNCATED=true"

# (c) on a clean run the diagnostic trailer stays empty, whatever the domain count.
assert_line "$trunc_out" "ISSUE_COUNT=0" "#2714 (c)"
assert_line "$trunc_out" "STATUS=OK" "#2714 (c)"
if grep -qx 'ISSUES:' <<<"$trunc_out"; then
  fail "#2714 (c): a clean run must not emit the diagnostic ISSUES: block"
fi
# A truncated batch is a caveat on coverage, not a collector fault.
pass "#2714 (c): clean fixture keeps ISSUE_COUNT=0 / STATUS=OK beside 2 fetched issues"

# --type issues emits no PR-half keys.
refute_key "$trunc_out" PRS_TOTAL "#2714"
refute_key "$trunc_out" PRS_TRUNCATED "#2714"
pass "#2714: --type issues emits no PRS_TOTAL / PRS_TRUNCATED"

# (b) twin: total == fetched -> not truncated. Guard integrity: without this a
# collector that always printed TRUNCATED=true would pass the block above.
counts_fixture "${work_dir}/counts-2-3.json" 2 3
export GIT_TRIAGE_COUNTS_FIXTURE="${work_dir}/counts-2-3.json"
twin_out="$(bash "$triage_script" --type issues --batch 2)"
assert_line "$twin_out" "ISSUES_FETCHED=2" "#2714 (b twin)"
assert_line "$twin_out" "ISSUES_TOTAL=2" "#2714 (b twin)"
assert_line "$twin_out" "ISSUES_TRUNCATED=false" "#2714 (b twin)"
assert_line "$twin_out" "TRUNCATED=false" "#2714 (b twin)"
pass "#2714 (b twin): 2 of 2 fetched reports TRUNCATED=false"

# No counts available (offline / GIT_TRIAGE_NO_FETCH) -> unknown, never a
# confident false: a count that was not taken must not read as "complete".
unset GIT_TRIAGE_COUNTS_FIXTURE
unknown_out="$(bash "$triage_script" --type issues --batch 2)"
assert_line "$unknown_out" "ISSUES_TOTAL=unknown" "#2714 (unknown)"
assert_line "$unknown_out" "ISSUES_TRUNCATED=unknown" "#2714 (unknown)"
assert_line "$unknown_out" "TRUNCATED=unknown" "#2714 (unknown)"
assert_line "$unknown_out" "STATUS=OK" "#2714 (unknown)"
pass "#2714: no count available reports ISSUES_TOTAL/TRUNCATED=unknown, not false"

# The REAL not-found response (repository: null + errors) must also read unknown.
printf '%s\n' '{"data":{"repository":null},"errors":[{"type":"NOT_FOUND","path":["repository"],"locations":[{"line":1,"column":37}],"message":"Could not resolve to a Repository with the name '"'"'acme/nope'"'"'."}]}' \
  > "${work_dir}/counts-not-found.json"
export GIT_TRIAGE_COUNTS_FIXTURE="${work_dir}/counts-not-found.json"
nf_out="$(bash "$triage_script" --type issues --batch 2)"
assert_line "$nf_out" "ISSUES_TOTAL=unknown" "#2714 (not found)"
assert_line "$nf_out" "TRUNCATED=unknown" "#2714 (not found)"
printf 'not json\n' > "${work_dir}/counts-garbage.json"
export GIT_TRIAGE_COUNTS_FIXTURE="${work_dir}/counts-garbage.json"
garbage_out="$(bash "$triage_script" --type issues --batch 2)"
assert_line "$garbage_out" "ISSUES_TOTAL=unknown" "#2714 (garbage)"
pass "#2714: a not-found or non-JSON count response reads unknown"

# (c) invalid issue JSON: the DIAGNOSTIC count moves to 1 while the DOMAIN
# count moves to 0 — opposite directions, so the keys cannot be the same count.
printf 'not json at all\n' > "${work_dir}/issues-invalid.json"
export GIT_TRIAGE_ISSUES_FIXTURE="${work_dir}/issues-invalid.json"
counts_fixture "${work_dir}/counts-5-0.json" 5 0
export GIT_TRIAGE_COUNTS_FIXTURE="${work_dir}/counts-5-0.json"
bad_out="$(bash "$triage_script" --type issues --batch 2)"
assert_line "$bad_out" "ISSUE_COUNT=1" "#2714 (c invalid)"
assert_line "$bad_out" "STATUS=WARN" "#2714 (c invalid)"
assert_line "$bad_out" "ISSUES_FETCHED=0" "#2714 (c invalid)"
grep -qx 'ISSUES:' <<<"$bad_out" \
  || fail "#2714 (c invalid): the diagnostic ISSUES: block must list the invalid fetch"
grep -q 'TYPE=invalid_issues_json' <<<"$bad_out" \
  || fail "#2714 (c invalid): expected TYPE=invalid_issues_json in the ISSUES: block"
# A failed fetch against 5 open issues is "0 of 5", not a clean zero.
assert_line "$bad_out" "ISSUES_TOTAL=5" "#2714 (c invalid)"
assert_line "$bad_out" "ISSUES_TRUNCATED=true" "#2714 (c invalid)"
pass "#2714 (c): invalid JSON gives ISSUE_COUNT=1 with ISSUES_FETCHED=0 and 0-of-5 truncation"

# PR half: the same --batch caps gh pr list, so it carries the same keys.
export GIT_TRIAGE_ISSUES_FIXTURE="$issues_fixture"
export GIT_TRIAGE_PRS_FIXTURE="$prs_fixture"          # six PRs
counts_fixture "${work_dir}/counts-2-23.json" 2 23
export GIT_TRIAGE_COUNTS_FIXTURE="${work_dir}/counts-2-23.json"
both_out="$(bash "$triage_script" --type both --batch 10)"
assert_line "$both_out" "PRS_FETCHED=6" "#2714 (prs)"
assert_line "$both_out" "PRS_TOTAL=23" "#2714 (prs)"
assert_line "$both_out" "PRS_TRUNCATED=true" "#2714 (prs)"
assert_line "$both_out" "ISSUES_TRUNCATED=false" "#2714 (prs)"
assert_line "$both_out" "TRUNCATED=true" "#2714 (prs)"
pass "#2714: PR half reports 6 of 23; the roll-up is true when either half is truncated"

counts_fixture "${work_dir}/counts-2-6.json" 2 6
export GIT_TRIAGE_COUNTS_FIXTURE="${work_dir}/counts-2-6.json"
none_out="$(bash "$triage_script" --type both --batch 10)"
assert_line "$none_out" "PRS_TRUNCATED=false" "#2714 (prs twin)"
assert_line "$none_out" "TRUNCATED=false" "#2714 (prs twin)"
pass "#2714: both halves complete gives TRUNCATED=false"

# Roll-up precedence: true beats unknown, unknown beats false.
printf '%s\n' '{"data":{"repository":{"issues":{"totalCount":2}}}}' > "${work_dir}/counts-issues-only.json"
export GIT_TRIAGE_COUNTS_FIXTURE="${work_dir}/counts-issues-only.json"
half_out="$(bash "$triage_script" --type both --batch 10)"
assert_line "$half_out" "PRS_TOTAL=unknown" "#2714 (precedence)"
assert_line "$half_out" "ISSUES_TRUNCATED=false" "#2714 (precedence)"
assert_line "$half_out" "TRUNCATED=unknown" "#2714 (precedence: unknown beats false)"
printf '%s\n' '{"data":{"repository":{"issues":{"totalCount":68}}}}' > "${work_dir}/counts-issues-68-only.json"
export GIT_TRIAGE_COUNTS_FIXTURE="${work_dir}/counts-issues-68-only.json"
half_true_out="$(bash "$triage_script" --type both --batch 10)"
assert_line "$half_true_out" "TRUNCATED=true" "#2714 (precedence: true beats unknown)"
pass "#2714: TRUNCATED roll-up precedence is true > unknown > false"

# Live path: every fixture seam above bypasses the gh call, so the real count
# query is pinned separately through an executable stub gh on PATH. The stub's
# totals (4242 / 17) are values no fixture above uses, so seeing them proves the
# stub — not a fixture, not the real gh — answered.
stub_dir="${work_dir}/stub-bin"
mkdir -p "$stub_dir"
cat > "${stub_dir}/gh" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "${GH_STUB_LOG:?}"
case "$1 $2" in
  "issue list"|"pr list") printf '[]\n' ;;
  "api graphql") printf '{"data":{"repository":{"issues":{"totalCount":4242},"pullRequests":{"totalCount":17}}}}\n' ;;
  *) exit 1 ;;
esac
STUB
chmod +x "${stub_dir}/gh"
[ -x "${stub_dir}/gh" ] || fail "#2714 (live): stub gh is not executable"
[ "$(PATH="${stub_dir}:$PATH" command -v gh)" = "${stub_dir}/gh" ] \
  || fail "#2714 (live): stub gh is not the gh in effect on PATH"

run_live() {  # run_live <log> <args...>
  local log="$1"; shift
  env -u GIT_TRIAGE_NO_FETCH -u GIT_TRIAGE_ISSUES_FIXTURE -u GIT_TRIAGE_PRS_FIXTURE \
      -u GIT_TRIAGE_COUNTS_FIXTURE PATH="${stub_dir}:$PATH" GH_STUB_LOG="$log" \
      bash "$triage_script" "$@"
}

live_log="${work_dir}/gh-live-repo.log"
live_out="$(run_live "$live_log" --type both --repo acme/widgets)"
assert_line "$live_out" "ISSUES_TOTAL=4242" "#2714 (live --repo)"
assert_line "$live_out" "PRS_TOTAL=17" "#2714 (live --repo)"
grep -q '^api graphql .*-f owner=acme -f name=widgets' "$live_log" \
  || fail "#2714 (live --repo): expected 'gh api graphql -f owner=acme -f name=widgets', got: $(grep '^api' "$live_log")"
grep -qF 'issues(states:OPEN){totalCount}' "$live_log" \
  || fail "#2714 (live --repo): the count query must ask issues(states:OPEN){totalCount}"
grep -qF 'pullRequests(states:OPEN){totalCount}' "$live_log" \
  || fail "#2714 (live --repo): the count query must ask pullRequests(states:OPEN){totalCount}"
[ "$(grep -c '^api graphql' "$live_log")" -eq 1 ] \
  || fail "#2714 (live --repo): both totals must come from ONE graphql call"
pass "#2714 (live): --repo owner/name drives one graphql count query for both halves"

live_log2="${work_dir}/gh-live-cwd.log"
live_out2="$(run_live "$live_log2" --type issues)"
assert_line "$live_out2" "ISSUES_TOTAL=4242" "#2714 (live cwd)"
grep -qF 'api graphql -F owner={owner} -F name={repo}' "$live_log2" \
  || fail "#2714 (live cwd): without --repo the query must use gh's {owner}/{repo} placeholders, got: $(grep '^api' "$live_log2")"
pass "#2714 (live): without --repo the count query resolves the cwd repo via {owner}/{repo}"

echo "ALL TESTS PASSED"
