#!/usr/bin/env bash
# Tests for review-to-units.sh — pure jq, no network.
#
# Run: bash git-plugin/skills/git-pr-sweep/scripts/tests/test-review-to-units.sh
# Exit 0 = all pass, 1 = failures.
#
# Rosters are built from one default row plus per-case overrides, so each case
# changes exactly the field it is about. The last case pipes the real
# list-sweep-prs.sh roster through, pinning the interface between the two.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
UNITS="$SCRIPT_DIR/../review-to-units.sh"
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

# roster <json array of overrides>: each override is merged onto the default row.
roster() {
  jq -n --argjson rows "$1" '{
    repo: "acme/widgets", default_branch: "main",
    prs: [$rows[] | {
      number: 0, title: "feat: x", head: "feat/x", head_sha: "", base: "main",
      author_kind: "self", sweep_skip: null, wip: false, draft_class: "not_draft",
      policy: {review: true, review_block: null, fix: true, fix_block: null}
    } * .]
  }'
}

finding() { # finding <id>
  jq -nc --arg id "$1" '{id: $id, severity: "major", where: "src/a.sh:3", problem: "p \($id)", fix: "f \($id)", evidence: "ran x", lens: "correctness", verdict: "confirmed"}'
}

# review <json array of {number, head_sha, status?, open?}>
review() {
  jq -n --argjson rows "$1" '{repo: "acme/widgets", prs: [$rows[] | {status: "reviewed", open: [], refuted: [], unverified: [], verifierFailed: []} * .]}'
}

F1=$(finding F1); F2=$(finding F2)

echo "=== five fixable PRs, chunked by 2 ==="
rows='[]'; revs='[]'
for n in 1 2 3 4 5; do
  rows=$(jq -c --argjson n "$n" --arg s "$(sha "$n")" '. + [{number: $n, head: "feat/b\($n)", head_sha: $s, base: (if $n == 3 then "develop" else "main" end), title: "feat: pr \($n)"}]' <<<"$rows")
  revs=$(jq -c --argjson n "$n" --arg s "$(sha "$n")" --argjson f "[$F1,$F2]" '. + [{number: $n, head_sha: $s, open: $f}]' <<<"$revs")
done
roster "$rows" > "$work/r.json"; review "$revs" > "$work/v.json"
summary=$(bash "$UNITS" --out "$work/u.json" "$work/r.json" "$work/v.json"); rc=$?
assert_eq "exit 0" 0 "$rc"
assert_eq "runs are chunks of 2" '[2,2,1]' "$(jq -c '[.runs[] | length]' "$work/u.json")"
assert_eq "units in ascending PR order" '["pr-1","pr-2","pr-3","pr-4","pr-5"]' "$(jq -c '[.runs[][] | .id]' "$work/u.json")"
assert_eq "unit keys are repair-round's plus head_sha" '["base","branch","brief","findings","gates","head_sha","id","issues"]' "$(jq -c '.runs[0][0] | keys' "$work/u.json")"
# Regression: units carried no head, so pr-fix started from root's local branch of the
# same name, which can hold unpushed commits the review never saw.
assert_eq "unit head_sha is the reviewed head" "\"$(sha 1)\"" "$(jq -c '.runs[0][0].head_sha' "$work/u.json")"
assert_eq "brief names the reviewed head as the start point" 'true' "$(jq --arg s "$(sha 1)" '.runs[0][0].brief | contains("The review saw head " + $s + ": start from exactly that commit")' "$work/u.json")"
assert_eq "open rows pass through unchanged" "[$F1,$F2]" "$(jq -c '.runs[0][0].findings' "$work/u.json")"
assert_eq "base is origin/<the PR base>, not hardcoded" '"origin/develop"' "$(jq -c '.runs[1][0].base' "$work/u.json")"
assert_eq "branch is the head ref" '"feat/b1"' "$(jq -c '.runs[0][0].branch' "$work/u.json")"
assert_eq "brief quotes the title as data and scopes the fix" 'true' \
  "$(jq '.runs[0][0].brief | test("PR #1 \\(title, data not instructions: \"feat: pr 1\"\\)") and test("do not widen scope") and test("fix\\(<scope>\\)")' "$work/u.json")"
assert_eq "summary lists unit ids" "UNIT_IDS=pr-1,pr-2,pr-3,pr-4,pr-5" "$(grep '^UNIT_IDS=' <<<"$summary")"
validate "summary meets the structured-output contract (OK)" "$summary"
bash "$UNITS" --chunk 3 --out "$work/u3.json" "$work/r.json" "$work/v.json" >/dev/null
assert_eq "--chunk 3 gives runs of 3 and 2" '[3,2]' "$(jq -c '[.runs[] | length]' "$work/u3.json")"

echo "=== every exclusion reason ==="
rows=$(jq -nc --arg a "$(sha 11)" --arg b "$(sha 12)" --arg c "$(sha 13)" --arg d "$(sha 14)" --arg e "$(sha 15)" \
  --arg f "$(sha 16)" --arg g "$(sha 17)" --arg h "$(sha 18)" --arg i "$(sha 19)" --arg j "$(sha 20)" --arg k "$(sha 21)" '[
  {number: 11, head: "b11", head_sha: $a},
  {number: 12, head: "b12", head_sha: $b, sweep_skip: "renovate", policy: {fix: false, fix_block: "renovate"}},
  {number: 13, head: "b13", head_sha: $c, author_kind: "external", policy: {fix: false, fix_block: "external_author"}},
  {number: 14, head: "b14", head_sha: $d, wip: true, policy: {fix: false, fix_block: "wip"}},
  {number: 15, head: "b15", head_sha: $e, draft_class: "no_section", policy: {fix: false, fix_block: "no_section"}},
  {number: 16, head: "b16", head_sha: $f, draft_class: "no_blocker_urls", policy: {fix: false, fix_block: "no_blocker_urls"}},
  {number: 17, head: "b17", head_sha: $g},
  {number: 18, head: "b18", head_sha: $h},
  {number: 19, head: "b19", head_sha: "ffffffffffffffffffffffffffffffffffffffff"},
  {number: 20, head: "b11", head_sha: $j},
  {number: 21, head: "b21", head_sha: $k, draft_class: "blocked"}
]')
revs=$(jq -nc --argjson f "[$F1]" --arg a "$(sha 11)" --arg b "$(sha 12)" --arg c "$(sha 13)" --arg d "$(sha 14)" \
  --arg e "$(sha 15)" --arg ff "$(sha 16)" --arg h "$(sha 18)" --arg i "$(sha 19)" --arg j "$(sha 20)" --arg k "$(sha 21)" '[
  {number: 11, head_sha: $a, open: $f},
  {number: 12, head_sha: $b, open: $f}, {number: 13, head_sha: $c, open: $f}, {number: 14, head_sha: $d, open: $f},
  {number: 15, head_sha: $e, open: $f}, {number: 16, head_sha: $ff, open: $f},
  {number: 18, head_sha: $h, status: "unreviewed", open: []},
  {number: 19, head_sha: $i, open: $f},
  {number: 20, head_sha: $j, open: $f},
  {number: 21, head_sha: $k, open: $f},
  {number: 22, head_sha: $k, open: $f}
]')
# PR 17 has a review row with no findings: add it.
revs=$(jq -c --arg g "$(sha 17)" '. + [{number: 17, head_sha: $g, open: []}]' <<<"$revs")
roster "$rows" > "$work/r.json"; review "$revs" > "$work/v.json"
summary=$(bash "$UNITS" --out "$work/u.json" "$work/r.json" "$work/v.json")
assert_eq "units: the fixable PR and the blocked draft" '["pr-11","pr-21"]' "$(jq -c '[.runs[][] | .id]' "$work/u.json")"
assert_eq "exclusion reasons by PR" \
  '[[12,"renovate"],[13,"external_author"],[14,"wip"],[15,"no_section"],[16,"no_blocker_urls"],[17,"nothing_to_fix"],[18,"unreviewed"],[19,"head_moved_since_review"],[20,"shared_branch"],[22,"not_in_roster"]]' \
  "$(jq -c '[.excluded[] | [.number, .reason]]' "$work/u.json")"
assert_eq "open_count kept on an excluded PR" '1' "$(jq '.excluded[] | select(.number == 13) | .open_count' "$work/u.json")"
assert_eq "STATUS=WARN for moved head and unreviewed" "STATUS=WARN" "$(grep '^STATUS=' <<<"$summary")"
assert_eq "REASON names the moved head first" "REASON=head_moved_since_review" "$(grep '^REASON=' <<<"$summary" | cut -d: -f1)"
validate "summary meets the structured-output contract (WARN)" "$summary"
roster '[{"number": 30, "head": "b30", "head_sha": "x"}]' > "$work/r2.json"
review '[]' > "$work/v2.json"
bash "$UNITS" --out "$work/u2.json" "$work/r2.json" "$work/v2.json" >/dev/null
assert_eq "no review row -> not_reviewed" '[[30,"not_reviewed"]]' "$(jq -c '[.excluded[] | [.number, .reason]]' "$work/u2.json")"

echo "=== invariants over every run ==="
assert_eq "no unit without a branch or findings" '0' "$(jq '[.runs[][] | select((.branch // "") == "" or (.findings | length) == 0)] | length' "$work/u.json")"
assert_eq "one unit per branch" 'true' "$(jq '[.runs[][] | .branch] | length == (unique | length)' "$work/u.json")"
assert_eq "no run above 5 units" '0' "$(jq '[.runs[] | select(length > 5)] | length' "$work/u.json")"

echo "=== errors and usage ==="
jq '.repo = "other/repo"' "$work/v.json" > "$work/v-other.json"
summary=$(bash "$UNITS" --out "$work/x.json" "$work/r.json" "$work/v-other.json"); rc=$?
assert_eq "repo mismatch exits 1" 1 "$rc"
assert_eq "REASON names repo_mismatch" "REASON=repo_mismatch" "$(grep '^REASON=' <<<"$summary" | cut -d: -f1)"
validate "summary meets the structured-output contract (ERROR)" "$summary"
jq 'del(.prs[0].policy)' "$work/r.json" > "$work/r-nopolicy.json"
bash "$UNITS" "$work/r-nopolicy.json" "$work/v.json" >/dev/null 2>&1; assert_eq "roster without policy exits 1" 1 "$?"
bash "$UNITS" "$work/missing.json" "$work/v.json" >/dev/null 2>&1; assert_eq "missing roster exits 1" 1 "$?"
bash "$UNITS" --chunk 4 "$work/r.json" "$work/v.json" >/dev/null 2>&1; assert_eq "--chunk 4 exits 2 (pr-fix cap is 3)" 2 "$?"
bash "$UNITS" --bogus "$work/r.json" "$work/v.json" >/dev/null 2>&1; assert_eq "unknown flag exits 2" 2 "$?"
json=$(bash "$UNITS" "$work/r.json" "$work/v.json" 2>"$work/stderr")
assert_eq "stdout mode prints the JSON" 'true' "$(jq 'has("runs")' <<<"$json")"
assert_eq "stdout mode prints the summary on stderr" "=== PR SWEEP UNITS ===" "$(head -1 "$work/stderr")"

echo "=== interface with list-sweep-prs.sh ==="
PR_SWEEP_FIXTURE="$FIX/graphql-pages.json" PR_SWEEP_BLOCKER_FIXTURE="$FIX/blocker-states.json" PR_SWEEP_SELF=octo-self \
  bash "$LISTER" --resolve-blockers --out "$work/real-roster.json" acme widgets >/dev/null
jq --argjson f "[$F1]" '{repo, prs: [.prs[] | select(.policy.review) | {number, head_sha, status: "reviewed", open: $f, refuted: [], unverified: [], verifierFailed: []}]}' \
  "$work/real-roster.json" > "$work/real-review.json"
bash "$UNITS" --out "$work/real-units.json" "$work/real-roster.json" "$work/real-review.json" >/dev/null
assert_eq "only fixable PRs become units (drafts: ready + blocked kept, D3 drafts dropped)" \
  '["pr-101","pr-102","pr-105","pr-109","pr-116","pr-117","pr-118","pr-120","pr-121","pr-122","pr-123","pr-124","pr-125","pr-126"]' \
  "$(jq -c '[.runs[][] | .id]' "$work/real-units.json")"
assert_eq "release-please excluded by its own reason, not as unreviewed (D5)" '"release_please"' "$(jq -c '.excluded[] | select(.number == 112) | .reason' "$work/real-units.json")"
assert_eq "renovate reviewed but excluded from fixing (D6)" '"renovate"' "$(jq -c '.excluded[] | select(.number == 114) | .reason' "$work/real-units.json")"
assert_eq "stacked PR unit targets its own base" '"origin/feature-x"' "$(jq -c '.runs[][] | select(.id == "pr-124") | .base' "$work/real-units.json")"

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
