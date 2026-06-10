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

echo "ALL TESTS PASSED"
