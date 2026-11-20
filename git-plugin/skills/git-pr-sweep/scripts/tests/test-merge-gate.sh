#!/usr/bin/env bash
# Tests for merge-gate.sh — pure jq, no network.
#
# Run: bash git-plugin/skills/git-pr-sweep/scripts/tests/test-merge-gate.sh
# Exit 0 = all pass, 1 = failures.
#
# Every roster row starts from one row that passes all eight gates; each case
# overrides the field(s) for a single gate and asserts that gate alone failed.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GATE="$SCRIPT_DIR/../merge-gate.sh"
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
FX=$(sha 9999)   # a head produced by a fix push

# Base row passes every gate. Overrides use jq's recursive merge (*).
roster() {
  jq -n --argjson rows "$1" '{
    repo: "acme/widgets", default_branch: "main", blockers_resolved: true,
    prs: [$rows[] | ({
      title: "feat: x", author: "octo-self", author_kind: "self", head: "feat/x", base: "main",
      base_is_default: true, is_draft: false, wip: false, wip_markers: [], draft_class: "not_draft",
      draft_status: {section_present: false, blockers: []}, ci: "green", ci_failed: [], sweep_skip: null
    } * .) | .url = "https://github.com/acme/widgets/pull/\(.number)"
           | .head_sha = (.head_sha // ("\(.number)" | ("0" * (40 - length)) + .))]
  }'
}
review() {
  jq -n --argjson rows "$1" '{repo: "acme/widgets", prs: [$rows[]
    | {status: "reviewed", open: [], refuted: [], unverified: [], verifierFailed: []} * .
    | .head_sha = (.head_sha // ("\(.number)" | ("0" * (40 - length)) + .))]}'
}
F='{"id":"F1","severity":"major","where":"a.sh:1","problem":"p","fix":"f","evidence":"e","lens":"correctness","verdict":"confirmed"}'

rows=$(jq -nc --arg fx "$FX" '[
  {number: 1},
  {number: 2, sweep_skip: "renovate", author_kind: "bot"},
  {number: 3, author: "stranger", author_kind: "external"},
  {number: 4, wip: true, wip_markers: ["title:WIP"]},
  {number: 5}, {number: 6}, {number: 7}, {number: 8}, {number: 9},
  {number: 10, head_sha: $fx},
  {number: 11, head_sha: "eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee"},
  {number: 12},
  {number: 13, ci: "red", ci_failed: ["lint", "test"]},
  {number: 14, ci: "pending"},
  {number: 15, base: "feature-x", base_is_default: false},
  {number: 16, is_draft: true, draft_class: "ready_candidate", draft_status: {section_present: true, blockers: [{url: "https://github.com/acme/widgets/pull/90", state: "MERGED"}]}},
  {number: 17, is_draft: true, draft_class: "ready_candidate", ci: "pending"},
  {number: 18, is_draft: true, draft_class: "blocked", draft_status: {section_present: true, blockers: [{url: "https://github.com/acme/widgets/pull/90", state: "MERGED"}, {url: "https://github.com/acme/widgets/pull/91", state: "OPEN"}]}},
  {number: 19, is_draft: true, draft_class: "no_section"},
  {number: 20},
  {number: 21, is_draft: true, draft_class: "no_blocker_urls", draft_status: {section_present: true, blockers: []}},
  {number: 22, is_draft: true, draft_class: "blockers_unresolved"},
  {number: 23, sweep_skip: "release_please", author_kind: "bot"}
]')
revs=$(jq -nc --argjson f "[$F]" '[
  {number: 1}, {number: 2}, {number: 3}, {number: 4},
  {number: 5, open: $f},
  {number: 6, status: "partial", unverified: [{claim: "c", pr: 6}]},
  {number: 7, status: "partial", verifierFailed: ["7:a.sh:1"]},
  {number: 8, open: $f}, {number: 9, open: $f}, {number: 10, open: $f},
  {number: 11}, {number: 12, open: $f},
  {number: 13}, {number: 14}, {number: 15}, {number: 16}, {number: 17}, {number: 18}, {number: 19},
  {number: 21}, {number: 22}, {number: 23}
]')
fixes=$(jq -nc --arg fx "$FX" '{prs: [
  {number: 8, row_status: "FIX_NEEDED", pushed_status: null, head_sha: null, detail: ""},
  {number: 9, row_status: "PASS", pushed_status: "skipped", head_sha: $fx, detail: "remote moved"},
  {number: 10, row_status: "REPAIRED_PASS", pushed_status: "pushed", head_sha: $fx, detail: ""},
  {number: 12, row_status: "PASS", pushed_status: "pushed", head_sha: $fx, detail: ""}
]}')
roster "$rows" > "$work/r.json"; review "$revs" > "$work/v.json"; printf '%s' "$fixes" > "$work/f.json"

# A gh/git shim that records any call: the gate must make none.
mkdir -p "$work/bin"
for tool in gh git; do
  printf '#!/usr/bin/env bash\necho "%s $*" >> "%s/calls"\nexit 1\n' "$tool" "$work" > "$work/bin/$tool"
  chmod +x "$work/bin/$tool"
done

echo "=== gates G1-G8, one failure each ==="
summary=$(PATH="$work/bin:$PATH" bash "$GATE" --out "$work/plan.json" "$work/r.json" "$work/v.json" "$work/f.json"); rc=$?
assert_eq "exit 0" 0 "$rc"
P="$work/plan.json"
rep() { jq -c --argjson n "$1" ".report[] | select(.number == \$n) | $2" "$P"; }
assert_eq "baseline row passes" 'true' "$(jq '.passed | index(1) != null' "$P")"
assert_eq "G1 skip (renovate) fails alone" '["skip"]' "$(rep 2 .failed)"
assert_eq "G1 skip (release-please) names its own flow" 'true' "$(rep 23 '.reason | test("release-please-pr-workflow")')"
assert_eq "G2 author fails alone" '["author"]' "$(rep 3 .failed)"
assert_eq "G3 wip fails alone and names the marker" '[["wip"],"WIP/do-not-merge marker: title:WIP"]' "$(rep 4 '[.failed, .reason]')"
assert_eq "G4 open finding, no fix" '[["review"],"1 open finding(s), no fix ran"]' "$(rep 5 '[.failed, .reason]')"
assert_eq "G4 unverified finding" '["review"]' "$(rep 6 .failed)"
assert_eq "G4 dead verifier" 'true' "$(rep 7 '.failed == ["review"] and (.reason | test("1 dead verifier"))')"
assert_eq "G4 fix row FIX_NEEDED" 'true' "$(rep 8 '.failed == ["review"] and (.reason | test("FIX_NEEDED"))')"
assert_eq "G4 fix PASS but pushed_status skipped" 'true' "$(rep 9 '.failed[0] == "review" and (.reason | test("not pushed \\(skipped\\)"))')"
assert_eq "open finding fixed + pushed + head moved to the fix head passes" 'true' "$(jq '.passed | index(10) != null' "$P")"
assert_eq "G5 head moved after review fails alone" '["head"]' "$(rep 11 .failed)"
assert_eq "G5 fix pushed but roster still at the reviewed head" '["head"]' "$(rep 12 .failed)"
assert_eq "G6 ci red fails alone and names the checks" '[["ci"],"CI red: lint, test"]' "$(rep 13 '[.failed, .reason]')"
assert_eq "non-draft with pending CI passes G6" 'true' "$(jq '.passed | index(14) != null' "$P")"
assert_eq "G7 stacked base fails alone" '["base"]' "$(rep 15 .failed)"
assert_eq "ready draft with green CI passes and is readied" '[true,[16]]' "$(jq -c '[(.passed | index(16) != null), .ready]' "$P")"
assert_eq "G8 ready draft with pending CI fails" '[["draft"],"draft CI is pending; readying needs green"]' "$(rep 17 '[.failed, .reason]')"
assert_eq "G8 blocked draft lists only the unmerged blocker" '"blocked by https://github.com/acme/widgets/pull/91 (OPEN)"' "$(rep 18 .reason)"
assert_eq "G8 draft without the section" '["draft"]' "$(rep 19 .failed)"
assert_eq "G8 zero-URL draft is the owner's call" 'true' "$(rep 21 '.reason | test("owner")')"
assert_eq "G8 unresolved blockers ask for --resolve-blockers" 'true' "$(rep 22 '.reason | test("--resolve-blockers")')"
assert_eq "no review row fails G4 first" '"review"' "$(rep 20 .gate)"
assert_eq "external author never in merge" 'false' "$(jq '[.merge[][]] | index(3) != null' "$P")"
assert_eq "only drafts are readied" '[16]' "$(jq -c '.ready' "$P")"
assert_eq "merge = passed, ascending" '[[1,10,14,16]]' "$(jq -c '.merge' "$P")"
assert_eq "report rows carry url and open_count" '["https://github.com/acme/widgets/pull/5",1]' "$(rep 5 '[.url, .open_count]')"
assert_eq "summary pastes the chunk as a literal list" "MERGE_CHUNK_1=1,10,14,16" "$(grep '^MERGE_CHUNK_1=' <<<"$summary")"
assert_eq "summary counts per first gate (PRs 5-9 and 20)" "GATE_REVIEW=6" "$(grep '^GATE_REVIEW=' <<<"$summary")"
validate "summary meets the structured-output contract (OK)" "$summary"
assert_eq "no gh or git call" "" "$(cat "$work/calls" 2>/dev/null)"

echo "=== purity: runs with gh and git absent from PATH ==="
mkdir -p "$work/stripped"
for tool in jq cat tr dirname; do ln -s "$(command -v "$tool")" "$work/stripped/$tool"; done
PATH="$work/stripped" "$(command -v bash)" "$GATE" --out "$work/plan-stripped.json" "$work/r.json" "$work/v.json" "$work/f.json" >/dev/null 2>&1
assert_eq "exit 0 with a PATH holding only jq/cat/tr/dirname" 0 "$?"
assert_eq "same plan as the full-PATH run" "$(jq -c . "$P")" "$(jq -c . "$work/plan-stripped.json")"

echo "=== chunks of 8, ascending ==="
many=$(jq -nc '[range(1; 19) | {number: (100 - .)}]')
roster "$many" > "$work/r-many.json"
review "$many" > "$work/v-many.json"
bash "$GATE" --out "$work/p-many.json" "$work/r-many.json" "$work/v-many.json" >/dev/null
assert_eq "18 passing PRs -> chunks 8,8,2" '[8,8,2]' "$(jq -c '[.merge[] | length]' "$work/p-many.json")"
assert_eq "ascending across chunks" 'true' "$(jq '[.merge[][]] == ([.merge[][]] | sort)' "$work/p-many.json")"
bash "$GATE" --chunk 3 --out "$work/p3.json" "$work/r-many.json" "$work/v-many.json" >/dev/null
assert_eq "--chunk 3" '[3,3,3,3,3,3]' "$(jq -c '[.merge[] | length]' "$work/p3.json")"

echo "=== fix input as repair-round returns ==="
rr=$(jq -nc --arg fx "$FX" '{
  rows: [{unit: "pr-10", branch: "feat/x", status: "REPAIRED_PASS", fix: {head_sha: $fx}},
         {unit: "pr-12", branch: "feat/x", status: "PASS", fix: {head_sha: $fx}}],
  finalisePlan: [{unit: "pr-10", branch: "feat/x", head_sha: $fx}, {unit: "pr-12", branch: "feat/x", head_sha: $fx}],
  pushed: [{unit: "pr-10", branch: "feat/x", status: "pushed", detail: ""}, {unit: "pr-12", branch: "feat/x", status: "failed", detail: "rejected"}]}')
printf '%s' "$rr" > "$work/rr.json"
bash "$GATE" --out "$work/p-rr.json" "$work/r.json" "$work/v.json" "$work/rr.json" >/dev/null
assert_eq "single RR return: pushed PR passes" 'true' "$(jq '.passed | index(10) != null' "$work/p-rr.json")"
assert_eq "single RR return: failed push fails G4" 'true' "$(jq '.report[] | select(.number == 12) | .reason | test("not pushed \\(failed\\)")' "$work/p-rr.json")"
jq -nc --slurpfile a "$work/rr.json" '[$a[0], {rows: [{unit: "pr-12", status: "PASS", fix: {}}], finalisePlan: [{unit: "pr-12", head_sha: "'"$(sha 12)"'"}], pushed: [{unit: "pr-12", status: "pushed", detail: ""}]}]' > "$work/rr-array.json"
bash "$GATE" --out "$work/p-rra.json" "$work/r.json" "$work/v.json" "$work/rr-array.json" >/dev/null
assert_eq "array of RR returns: the later row for a PR wins" 'true' "$(jq '.passed | index(12) != null' "$work/p-rra.json")"
jq -c '.[1]' "$work/rr-array.json" > "$work/rr-second.json"
bash "$GATE" --out "$work/p-rr2.json" "$work/r.json" "$work/v.json" "$work/rr.json" "$work/rr-second.json" >/dev/null
assert_eq "two fix files: the later file's row for a PR wins" 'true' "$(jq '(.passed | index(12) != null) and (.passed | index(10) != null)' "$work/p-rr2.json")"
bash "$GATE" --out "$work/p-rr3.json" "$work/r.json" "$work/v.json" "$work/rr-second.json" "$work/rr.json" >/dev/null
assert_eq "two fix files in the other order: the earlier pushed row loses" 'true' "$(jq '.passed | index(12) == null' "$work/p-rr3.json")"
jq '.rows[0].unit = "unit-1"' "$work/rr.json" > "$work/rr-bad.json"
summary=$(bash "$GATE" --out "$work/x.json" "$work/r.json" "$work/v.json" "$work/rr-bad.json"); rc=$?
assert_eq "a unit id that is not pr-<n> exits 1" 1 "$rc"
assert_eq "REASON names bad_fix" "REASON=bad_fix" "$(grep '^REASON=' <<<"$summary" | cut -d: -f1)"
validate "summary meets the structured-output contract (ERROR)" "$summary"

echo "=== interface with list-sweep-prs.sh ==="
PR_SWEEP_FIXTURE="$FIX/graphql-pages.json" PR_SWEEP_BLOCKER_FIXTURE="$FIX/blocker-states.json" PR_SWEEP_SELF=octo-self \
  bash "$LISTER" --resolve-blockers --out "$work/real-roster.json" acme widgets >/dev/null
jq '{repo, prs: [.prs[] | select(.policy.review) | {number, head_sha, status: "reviewed", open: [], refuted: [], unverified: [], verifierFailed: []}]}' \
  "$work/real-roster.json" > "$work/real-review.json"
bash "$GATE" --out "$work/real-plan.json" "$work/real-roster.json" "$work/real-review.json" >/dev/null
assert_eq "real roster: ready drafts" '[102]' "$(jq -c '.ready' "$work/real-plan.json")"
assert_eq "real roster: renovate reported, not merged (D6)" '"skip"' "$(jq -c '.report[] | select(.number == 114) | .gate' "$work/real-plan.json")"
assert_eq "real roster: release-please reported, not merged (D5)" '["skip","skip"]' "$(jq -c '[.report[] | select(.number == 112 or .number == 113) | .gate]' "$work/real-plan.json")"
assert_eq "real roster: every reported row has a gate and reason" '0' "$(jq '[.report[] | select((.gate // "") == "" or (.reason // "") == "")] | length' "$work/real-plan.json")"
assert_eq "real roster: passed and reported partition the roster" 'true' \
  "$(jq -n --slurpfile p "$work/real-plan.json" --slurpfile r "$work/real-roster.json" '(($p[0].passed + [$p[0].report[].number]) | sort) == ([$r[0].prs[].number] | sort)')"

echo "=== usage ==="
bash "$GATE" --bogus "$work/r.json" "$work/v.json" >/dev/null 2>&1; assert_eq "unknown flag exits 2" 2 "$?"
bash "$GATE" "$work/r.json" >/dev/null 2>&1; assert_eq "missing review exits 2" 2 "$?"
bash "$GATE" --chunk 9 "$work/r.json" "$work/v.json" >/dev/null 2>&1; assert_eq "--chunk 9 exits 2" 2 "$?"
bash "$GATE" "$work/r.json" "$work/missing.json" >/dev/null 2>&1; assert_eq "missing review file exits 1" 1 "$?"

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
