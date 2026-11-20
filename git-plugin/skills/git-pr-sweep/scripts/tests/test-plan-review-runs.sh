#!/usr/bin/env bash
# Tests for plan-review-runs.sh and merge-review.sh — pure jq, no network.
#
# Run: bash git-plugin/skills/git-pr-sweep/scripts/tests/test-plan-review-runs.sh
# Exit 0 = all pass, 1 = failures.
#
# plan-review-runs: small PRs share a group up to 3 PRs / 300 diff lines, a
# large PR is alone, a run holds at most 4 groups and 6 PRs, non-reviewable
# PRs are listed with their policy reason, and the real list-sweep-prs.sh
# roster plans cleanly.
# merge-review: full runs concatenate, a PR in two full runs is an ERROR, a
# verify-only row appends open/refuted and replaces unverified/verifierFailed
# only when the head matches, status is recomputed, an aborted run is an ERROR.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLAN="$SCRIPT_DIR/../plan-review-runs.sh"
MERGE="$SCRIPT_DIR/../merge-review.sh"
LISTER="$SCRIPT_DIR/../list-sweep-prs.sh"
FIX="$SCRIPT_DIR/fixtures"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../../../.." && pwd)"
VALIDATOR="$REPO_ROOT/scripts/check-structured-output-contract.sh"
PASS=0
FAIL=0

work=$(mktemp -d)
{ [ -n "$work" ] && [ -d "$work" ]; } || { echo "mktemp failed" >&2; exit 1; }
work=$(cd -P -- "$work" && pwd -P) || { echo "cannot resolve temp dir" >&2; exit 1; }
trap 'rm -rf "$work"' EXIT
command -v jq >/dev/null || { echo "jq required" >&2; exit 1; }

assert_eq() {
  local desc="$1" expected="$2" actual="$3"
  if [ "$expected" = "$actual" ]; then
    printf "  PASS: %s\n" "$desc"; PASS=$((PASS + 1))
  else
    printf "  FAIL: %s (expected [%s], got [%s])\n" "$desc" "$expected" "$actual"; FAIL=$((FAIL + 1))
  fi
}
validate() {
  local desc="$1" block="$2"
  if [ ! -f "$VALIDATOR" ]; then printf "  SKIP: %s (no validator)\n" "$desc"; return; fi
  if bash "$VALIDATOR" --validate - <<<"$block" >/dev/null 2>&1; then
    printf "  PASS: %s\n" "$desc"; PASS=$((PASS + 1))
  else
    printf "  FAIL: %s\n" "$desc"; FAIL=$((FAIL + 1))
  fi
}
sha() { printf '%040d' "$1"; }

# roster <json array of {number, diff_lines, changed_files, review?}>
roster() {
  jq -n --argjson rows "$1" '{repo: "acme/widgets", default_branch: "main", prs: [$rows[] | {
    number: 0, title: "t", url: "u", head: "h", head_sha: "", base: "main", is_draft: false,
    diff_lines: 10, changed_files: 1, author_kind: "self", draft_class: "not_draft",
    policy: {review: true, review_block: null, fix: true, fix_block: null}} * . | .head_sha = ("\(.number)" * 40 | .[0:40])]}'
}

echo "=== grouping and run packing ==="
# 1..4 small (100 lines each), 5 large (900), 6..7 small (50), 8 not reviewable,
# 9..12 large.
roster '[
  {"number":1,"diff_lines":100},{"number":2,"diff_lines":100},{"number":3,"diff_lines":100},
  {"number":4,"diff_lines":100},{"number":5,"diff_lines":900,"changed_files":20},
  {"number":6,"diff_lines":50},{"number":7,"diff_lines":50,"changed_files":7},
  {"number":8,"policy":{"review":false,"review_block":"release_please","fix":false,"fix_block":"release_please"}},
  {"number":9,"diff_lines":400},{"number":10,"diff_lines":400},{"number":11,"diff_lines":400},{"number":12,"diff_lines":400}
]' > "$work/r.json"
summary=$(bash "$PLAN" --out "$work/p.json" "$work/r.json"); rc=$?
assert_eq "exit 0" 0 "$rc"
assert_eq "small PRs pack 3 to a group under 300 lines; large and >6-file PRs stand alone; a 7th PR opens a new run" \
  '[[[1,2,3],[4,6],[5]],[[7],[9],[10],[11]],[[12]]]' "$(jq -c '[.runs[].groups]' "$work/p.json")"
assert_eq "no run exceeds 4 groups or 6 PRs" 'true' "$(jq '[.runs[] | (.groups | length) <= 4 and (.prs | length) <= 6] | all' "$work/p.json")"
assert_eq "run prs equal the union of its groups, ascending" 'true' "$(jq '[.runs[] | (.prs | map(.number)) == (.groups | flatten | sort)] | all' "$work/p.json")"
assert_eq "non-reviewable PR listed with its policy reason" '[{"number":8,"reason":"release_please"}]' "$(jq -c '.not_reviewed' "$work/p.json")"
assert_eq "run rows carry what pr-review reads" '["base","changed_files","diff_lines","draft_class","head","head_sha","is_draft","number","title"]' \
  "$(jq -c '.runs[0].prs[0] | del(.url, .author_kind) | keys' "$work/p.json")"
assert_eq "limits echo the template caps" '{"max_prs":6,"max_groups":4,"max_per_group":3}' "$(jq -c '.limits | {max_prs, max_groups, max_per_group}' "$work/p.json")"
assert_eq "summary RUNS" "RUNS=3" "$(grep '^RUNS=' <<<"$summary")"
validate "summary meets the structured-output contract" "$summary"

echo "=== six small PRs: two groups in one run ==="
roster '[{"number":1},{"number":2},{"number":3},{"number":4},{"number":5},{"number":6}]' > "$work/r6.json"
bash "$PLAN" --out "$work/p6.json" "$work/r6.json" >/dev/null
assert_eq "six tiny PRs → one run of two groups" '[[[1,2,3],[4,5,6]]]' "$(jq -c '[.runs[].groups]' "$work/p6.json")"

echo "=== five large PRs: a second run ==="
roster '[{"number":1,"diff_lines":500},{"number":2,"diff_lines":500},{"number":3,"diff_lines":500},{"number":4,"diff_lines":500},{"number":5,"diff_lines":500}]' > "$work/r5.json"
bash "$PLAN" --out "$work/p5.json" "$work/r5.json" >/dev/null
assert_eq "five large PRs → runs of 4 and 1 groups" '[4,1]' "$(jq -c '[.runs[].groups | length]' "$work/p5.json")"

echo "=== empty and bad input ==="
roster '[]' > "$work/r0.json"
bash "$PLAN" --out "$work/p0.json" "$work/r0.json" >/dev/null; assert_eq "empty roster exits 0" 0 "$?"
assert_eq "empty roster → no runs" '[]' "$(jq -c '.runs' "$work/p0.json")"
echo '{"prs":[{"number":1}]}' > "$work/bad.json"
bash "$PLAN" "$work/bad.json" >/dev/null 2>&1; assert_eq "roster without policy/diff fields exits 1" 1 "$?"
bash "$PLAN" --bogus "$work/r.json" >/dev/null 2>&1; assert_eq "unknown flag exits 2" 2 "$?"

echo "=== the real lister's roster plans cleanly ==="
if [ -f "$FIX/graphql-pages.json" ]; then
  PR_SWEEP_FIXTURE="$FIX/graphql-pages.json" PR_SWEEP_SELF=lauri bash "$LISTER" --out "$work/live.json" acme widgets >/dev/null 2>&1
  bash "$PLAN" --out "$work/plive.json" "$work/live.json" >/dev/null; assert_eq "lister roster → planner exit 0" 0 "$?"
  assert_eq "every reviewable PR planned exactly once" \
    "$(jq '[.prs[] | select(.policy.review)] | length' "$work/live.json")" "$(jq '[.runs[].prs[]] | length' "$work/plive.json")"
fi

echo "=== merge-review ==="
row() { # row <number> <head> [extra json]
  jq -nc --argjson n "$1" --arg h "$2" --argjson x "${3:-{\}}" \
    '{number: $n, head_sha: $h, status: "reviewed", lensesFailed: [], open: [], refuted: [], unverified: [], verifierFailed: [], stats: {}} * $x'
}
O='{"id":"F1","severity":"major","where":"a:1","problem":"p","fix":"f","evidence":"e","lens":"correctness","verdict":"confirmed"}'
C='{"pr":2,"title":"t","file":"b","line":2,"severity":"medium","claim":"c","failure_scenario":"","suggested_fix":"","lens":"spec","raised_by":["spec"],"also":[]}'
jq -n --argjson a "$(row 1 "$(sha 1)" "{\"open\":[$O]}")" --argjson b "$(row 2 "$(sha 2)" "{\"unverified\":[$C],\"status\":\"partial\"}")" \
  '{repo: "acme/widgets", mode: "full", status: "partial", prs: [$a, $b]}' > "$work/run1.json"
jq -n --argjson c "$(row 3 "$(sha 3)" '{"lensesFailed":["spec"],"status":"partial"}')" \
  '{repo: "acme/widgets", mode: "full", status: "partial", prs: [$c]}' > "$work/run2.json"
jq -n --argjson v "$(row 2 "$(sha 2)" "{\"open\":[$O]}")" --argjson s "$(row 3 "$(sha 9)")" \
  '{repo: "acme/widgets", mode: "verify-only", status: "reviewed", prs: [$v, $s]}' > "$work/verify.json"
summary=$(bash "$MERGE" --out "$work/review.json" "$work/run1.json" "$work/run2.json" "$work/verify.json"); rc=$?
assert_eq "merge exit 0 (WARN)" 0 "$rc"
assert_eq "three PRs, ascending" '[1,2,3]' "$(jq -c '[.prs[].number]' "$work/review.json")"
assert_eq "verify-only row replaces unverified and appends open → reviewed" '"reviewed"|1|0' \
  "$(jq -r '.prs[1] | "\(.status | tojson)|\(.open | length)|\(.unverified | length)"' "$work/review.json")"
assert_eq "verify-only row with a moved head is skipped; lens gap keeps PR 3 partial" '"partial"' "$(jq -c '.prs[2].status' "$work/review.json")"
assert_eq "stale verify row reported" 'true' "$(grep -q 'TYPE=stale_verify' <<<"$summary" && echo true || echo false)"
validate "merge summary meets the structured-output contract (WARN)" "$summary"
bash "$MERGE" --out "$work/rv2.json" "$work/run1.json" "$work/verify.json" >/dev/null
jq -n --argjson o "$O" '{repo: "acme/widgets", mode: "verify-only", prs: [{number: 1, head_sha: "'"$(sha 1)"'", open: [$o], unverified: [], verifierFailed: []}]}' > "$work/v1.json"
bash "$MERGE" --out "$work/rv3.json" "$work/run1.json" "$work/v1.json" >/dev/null
assert_eq "appended open rows are renumbered F1..Fn" '["F1","F2"]' "$(jq -c '[.prs[0].open[].id]' "$work/rv3.json")"
bash "$MERGE" "$work/run1.json" "$work/run1.json" >/dev/null 2>&1; assert_eq "a PR in two full runs exits 1" 1 "$?"
echo '{"abort":true,"reason":"over-cap"}' > "$work/ab.json"
bash "$MERGE" "$work/run1.json" "$work/ab.json" >/dev/null 2>&1; assert_eq "an aborted run exits 1" 1 "$?"
jq '.repo = "other/repo"' "$work/run2.json" > "$work/other.json"
bash "$MERGE" "$work/run1.json" "$work/other.json" >/dev/null 2>&1; assert_eq "runs for two repos exit 1" 1 "$?"
bash "$MERGE" >/dev/null 2>&1; assert_eq "no run files exits 2" 2 "$?"

echo "=== merge-review output feeds merge-gate ==="
bash "$SCRIPT_DIR/../merge-gate.sh" --out "$work/plan.json" "$work/r.json" "$work/review.json" >/dev/null 2>&1
assert_eq "merge-gate accepts merged review.json" 0 "$?"

echo
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
