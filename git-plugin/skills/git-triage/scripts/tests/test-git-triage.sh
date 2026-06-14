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

echo "ALL TESTS PASSED"
