#!/usr/bin/env bash
# Tests for list-sweep-prs.sh — offline, from fixtures/graphql-pages.json.
#
# Run: bash git-plugin/skills/git-pr-sweep/scripts/tests/test-list-sweep-prs.sh
# Exit 0 = all pass, 1 = failures.
#
# A `gh` shim that records every call sits first on PATH, so a fixture seam that
# silently falls through to the network fails the "no gh call" assertion.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
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

mkdir -p "$work/bin"
cat > "$work/bin/gh" <<EOF
#!/usr/bin/env bash
echo "\$*" >> "$work/gh-calls"
exit 1
EOF
chmod +x "$work/bin/gh"
command -v jq >/dev/null || { echo "jq required" >&2; exit 1; }
PATH="$work/bin:$PATH"
[ "$(command -v gh)" = "$work/bin/gh" ] || { echo "gh shim not first on PATH" >&2; exit 1; }

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
    printf "  FAIL: %s\n" "$desc"; bash "$VALIDATOR" --validate - <<<"$block" | sed 's/^/    /'; FAIL=$((FAIL + 1))
  fi
}

run() { # run <out-file> [args...]; summary on stdout, exit code in $rc
  local out="$1"; shift
  summary=$(PR_SWEEP_FIXTURE="${FIXTURE:-$FIX/graphql-pages.json}" \
            PR_SWEEP_BLOCKER_FIXTURE="$FIX/blocker-states.json" \
            PR_SWEEP_SELF="${SELF-octo-self}" \
            bash "$LISTER" --out "$out" "$@" acme widgets)
  rc=$?
}

pr() { jq -c --argjson n "$1" ".prs[] | select(.number == \$n) | $2" "$R"; }

echo "=== list-sweep-prs: full run with --resolve-blockers ==="
R="$work/roster.json"
run "$R" --resolve-blockers
assert_eq "exit 0" 0 "$rc"
assert_eq "STATUS=WARN (unknown blocker + truncated contexts)" "STATUS=WARN" "$(grep '^STATUS=' <<<"$summary")"
validate "summary block meets the structured-output contract (WARN)" "$summary"
assert_eq "both pages read" 2 "$(jq .pages "$R")"
assert_eq "page-2 PR #126 present" '126' "$(pr 126 .number)"
assert_eq "all 26 PRs listed" 26 "$(jq '.prs | length' "$R")"
assert_eq "not truncated" false "$(jq .truncated "$R")"
assert_eq "default branch read once" '"main"' "$(jq -c .default_branch "$R")"
assert_eq "self recorded from seam" '"octo-self"' "$(jq -c .self "$R")"
assert_eq "drafts included" 6 "$(jq .counts.drafts "$R")"
assert_eq "is_draft carried" true "$(pr 102 .is_draft)"
assert_eq "sorted ascending" true "$(jq '[.prs[].number] == ([.prs[].number] | sort)' "$R")"
assert_eq "no gh call with every seam set" "" "$(cat "$work/gh-calls" 2>/dev/null)"

echo "=== author_kind ==="
assert_eq "self" '"self"' "$(pr 101 .author_kind)"
assert_eq "Bot typename" '"bot"' "$(pr 116 .author_kind)"
assert_eq "app/ login" '"bot"' "$(pr 117 .author_kind)"
assert_eq "[bot] login" '"bot"' "$(pr 118 .author_kind)"
assert_eq "external" '"external"' "$(pr 119 .author_kind)"

echo "=== sweep_skip and policy ==="
assert_eq "release-please by head" '"release_please"' "$(pr 112 .sweep_skip)"
assert_eq "release-please by login" '"release_please"' "$(pr 113 .sweep_skip)"
assert_eq "renovate" '"renovate"' "$(pr 114 .sweep_skip)"
assert_eq "cross-repo head" '"cross_repo_head"' "$(pr 115 .sweep_skip)"
assert_eq "plain PR not skipped" 'null' "$(pr 101 .sweep_skip)"
assert_eq "release-please not reviewed (D5)" '{"review":false,"review_block":"release_please","fix":false,"fix_block":"release_please"}' "$(pr 112 .policy)"
assert_eq "renovate reviewed, never fixed (D6)" '{"review":true,"review_block":null,"fix":false,"fix_block":"renovate"}' "$(pr 114 .policy)"
assert_eq "external author reviewed, not fixed" '[true,"external_author"]' "$(pr 119 '[.policy.review, .policy.fix_block]')"
assert_eq "WIP non-draft not fixed" '"wip"' "$(pr 107 .policy.fix_block)"
assert_eq "no-section draft not fixed (D3)" '"no_section"' "$(pr 103 .policy.fix_block)"
assert_eq "zero-URL draft not fixed (D3)" '"no_blocker_urls"' "$(pr 104 .policy.fix_block)"
assert_eq "blocked draft still fixable" 'true' "$(pr 105 .policy.fix)"

echo "=== wip markers (D4) ==="
assert_eq "label WIP, case-insensitive" '["label:WIP"]' "$(pr 106 .wip_markers)"
assert_eq "title [WIP]" '["title:[WIP]"]' "$(pr 107 .wip_markers)"
assert_eq "title WIP:" 'true' "$(pr 108 .wip)"
assert_eq "title 'wipe ...' is not WIP" 'false' "$(pr 109 .wip)"
assert_eq "title DNM, case-insensitive" '["title:dnm"]' "$(pr 110 .wip_markers)"
assert_eq "labels do-not-merge + Blocked; 'work in progress' is not a marker" '["label:do-not-merge","label:Blocked"]' "$(pr 111 .wip_markers)"

# Regression: no fixture title started with "[DNM]", so dropping \[dnm\] from the
# wip_markers regex kept the suite green while "[DNM] foo" stopped being WIP (D4).
jq '[.[0] | .data.repository.pullRequests.pageInfo.hasNextPage = false
     | .data.repository.pullRequests.nodes |= [.[0] | .title = "[DNM] try a thing" | .labels.nodes = []]]' \
  "$FIX/graphql-pages.json" > "$work/dnm-page.json"
PR_SWEEP_FIXTURE="$work/dnm-page.json" PR_SWEEP_SELF=octo-self bash "$LISTER" --out "$work/dnm.json" acme widgets >/dev/null
assert_eq "title [DNM], bracketed" '[true,["title:[DNM]"]]' "$(jq -c '.prs[0] | [.wip, .wip_markers]' "$work/dnm.json")"

echo "=== draft_class ==="
assert_eq "not_draft" '"not_draft"' "$(pr 101 .draft_class)"
assert_eq "ready_candidate" '"ready_candidate"' "$(pr 102 .draft_class)"
assert_eq "no_section" '"no_section"' "$(pr 103 .draft_class)"
assert_eq "no_blocker_urls" '"no_blocker_urls"' "$(pr 104 .draft_class)"
assert_eq "blocked (OPEN blocker; heading case-insensitive)" '"blocked"' "$(pr 105 .draft_class)"
assert_eq "wip outranks a merged blocker" '"wip"' "$(pr 106 .draft_class)"
assert_eq "unreadable blocker stays blocked" '"blocked"' "$(pr 126 .draft_class)"
assert_eq "unreadable blocker state UNKNOWN" '"UNKNOWN"' "$(pr 126 '.draft_status.blockers[0].state')"

echo "=== Draft status URL extraction ==="
assert_eq "dedup, cross-repo kept, trailing ).,; stripped, ### stays inside, outside URLs ignored" \
  '["https://github.com/acme/widgets/pull/90","https://github.com/other/lib/pull/7","https://github.com/acme/widgets/pull/92"]' \
  "$(pr 102 '[.draft_status.blockers[].url]')"
assert_eq "resolved states attached" '["MERGED","MERGED","MERGED"]' "$(pr 102 '[.draft_status.blockers[].state]')"
assert_eq "section_present for a draft with the section" 'true' "$(pr 102 .draft_status.section_present)"
assert_eq "no section -> no blockers" '{"section_present":false,"blockers":[]}' "$(pr 103 .draft_status)"

echo "=== CI reduction ==="
assert_eq "superseded CANCELLED run is not red" '"green"' "$(pr 120 .ci)"
assert_eq "StatusContext ERROR is red" '["red",["ci/legacy"]]' "$(pr 121 '[.ci, .ci_failed]')"
assert_eq "in-progress run is pending" '"pending"' "$(pr 122 .ci)"
assert_eq "no rollup is none" '"none"' "$(pr 123 .ci)"
assert_eq "more than 100 checks reads pending, never green" '["pending",true]' "$(pr 125 '[.ci, .ci_truncated]')"
assert_eq "base_is_default false for a stacked base" 'false' "$(pr 124 .base_is_default)"
assert_eq "diff_lines = additions + deletions" '[12,1]' "$(pr 101 '[.diff_lines, .changed_files]')"

echo "=== body text never leaves the script ==="
assert_eq "no body key" 'false' "$(jq '[.prs[] | has("body")] | any' "$R")"
if grep -q 'SENTINEL-BODY-TEXT' "$R"; then
  printf "  FAIL: body sentinel leaked into the roster\n"; FAIL=$((FAIL + 1))
else
  printf "  PASS: body sentinel absent from the roster\n"; PASS=$((PASS + 1))
fi

echo "=== without --resolve-blockers ==="
R="$work/roster-unresolved.json"
run "$R"
assert_eq "blockers_resolved false" false "$(jq .blockers_resolved "$R")"
assert_eq "ready draft reads blockers_unresolved" '"blockers_unresolved"' "$(pr 102 .draft_class)"
assert_eq "blocker rows carry no state" 'false' "$(pr 102 '[.draft_status.blockers[] | has("state")] | any')"
assert_eq "no blocker WARN" "" "$(grep 'TYPE=blocker_unresolved' <<<"$summary")"

echo "=== truncation ceiling ==="
R="$work/roster-max5.json"
run "$R" --max-prs 5
assert_eq "cut to 5" 5 "$(jq '.prs | length' "$R")"
assert_eq "truncated true" true "$(jq .truncated "$R")"
assert_eq "stopped after page 1" 1 "$(jq .pages "$R")"
assert_eq "REASON names truncation first" "REASON=truncated" "$(grep '^REASON=' <<<"$summary" | cut -d: -f1)"
R="$work/roster-max11.json"
run "$R" --max-prs 11
assert_eq "ceiling reached exactly with a next page -> truncated" '[11,true,1]' "$(jq -c '[(.prs | length), .truncated, .pages]' "$R")"
R="$work/roster-max26.json"
run "$R" --max-prs 26
assert_eq "ceiling equal to the total -> not truncated" '[26,false,2]' "$(jq -c '[(.prs | length), .truncated, .pages]' "$R")"

echo "=== OK path, stdout mode ==="
jq '[.[0] | .data.repository.pullRequests.pageInfo.hasNextPage = false
     | .data.repository.pullRequests.nodes |= [.[0]]]' "$FIX/graphql-pages.json" > "$work/one-page.json"
json=$(PR_SWEEP_FIXTURE="$work/one-page.json" PR_SWEEP_SELF=octo-self bash "$LISTER" acme widgets 2>"$work/stderr")
rc=$?
assert_eq "exit 0" 0 "$rc"
assert_eq "stdout is the JSON roster" '[101]' "$(jq -c '[.prs[].number]' <<<"$json")"
assert_eq "summary on stderr, STATUS=OK" "STATUS=OK" "$(grep '^STATUS=' "$work/stderr")"
assert_eq "no REASON on OK" "" "$(grep '^REASON=' "$work/stderr")"
validate "summary block meets the structured-output contract (OK)" "$(cat "$work/stderr")"

echo "=== errors ==="
printf '[{"errors":[{"message":"Could not resolve to a Repository"}]}]' > "$work/gql-error.json"
FIXTURE="$work/gql-error.json" run "$work/x.json"
assert_eq "GraphQL error exits 1" 1 "$rc"
assert_eq "REASON names graphql_error" "REASON=graphql_error" "$(grep '^REASON=' <<<"$summary" | cut -d: -f1)"
validate "summary block meets the structured-output contract (ERROR)" "$summary"
assert_eq "no roster written on error" "absent" "$(if [ -f "$work/x.json" ]; then echo present; else echo absent; fi)"
jq '[.[0]]' "$FIX/graphql-pages.json" > "$work/short.json"
FIXTURE="$work/short.json" run "$work/x.json"
assert_eq "hasNextPage with no next page exits 1" 1 "$rc"
assert_eq "REASON names fixture_exhausted" "REASON=fixture_exhausted" "$(grep '^REASON=' <<<"$summary" | cut -d: -f1)"
SELF="" run "$work/x.json"
assert_eq "unknown self login exits 1 (gh shim fails)" 1 "$rc"
assert_eq "REASON names self_unknown" "REASON=self_unknown" "$(grep '^REASON=' <<<"$summary" | cut -d: -f1)"
assert_eq "the self lookup went to gh api user" "api user --jq .login" "$(tail -1 "$work/gh-calls")"

echo "=== usage ==="
bash "$LISTER" --bogus acme widgets >/dev/null 2>&1; assert_eq "unknown flag exits 2" 2 "$?"
bash "$LISTER" acme >/dev/null 2>&1; assert_eq "one positional exits 2" 2 "$?"
bash "$LISTER" --max-prs 0 acme widgets >/dev/null 2>&1; assert_eq "--max-prs 0 exits 2" 2 "$?"

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
