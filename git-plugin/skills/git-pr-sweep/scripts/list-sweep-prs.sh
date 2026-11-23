#!/usr/bin/env bash
# list-sweep-prs.sh — the roster for a git-pr-sweep run: every open PR in one
# repo, drafts included, classified for the review, fix and merge stages.
#
# DATA-ONLY. Reads GitHub, mutates nothing. Classification is pure jq over the
# fetched fields, so every rule is unit-testable from a fixture.
#
# Usage:
#   list-sweep-prs.sh [--resolve-blockers] [--max-prs N] [--out FILE] <owner> <repo>
#
#   --resolve-blockers  read the state of every PR URL found under a draft's
#                       `## Draft status` section (gh pr view <url> --json state).
#                       Required before the merge gate: without it no draft can
#                       be a ready_candidate.
#   --max-prs N         ceiling on PRs read (default 500). Reaching it sets
#                       "truncated": true and STATUS=WARN; never a silent cut.
#   --out FILE          write the JSON roster to FILE and print the summary block
#                       on stdout. Without it the JSON goes to stdout and the
#                       summary to stderr.
#
# Output JSON (the PR body is never emitted; only fields derived from it):
#   {repo, default_branch, self, fetched, pages, truncated, max_prs,
#    blockers_resolved, counts:{...},
#    prs:[{number, title, url, is_draft, author, author_kind, author_association,
#          head, head_sha, base, base_is_default, cross_repo, labels,
#          additions, deletions, changed_files, diff_lines,
#          wip, wip_markers, draft_class,
#          draft_status:{section_present, blockers:[{url, state?}]},
#          ci, ci_failed, ci_truncated, merge_state, review_decision,
#          sweep_skip, policy:{review, review_block, fix, fix_block}}]}
#
# Classification:
#   author_kind   self (login == the gh user) | bot (__typename Bot, *[bot],
#                 app/*) | external
#   sweep_skip    release_please | renovate | cross_repo_head | null
#   wip           title prefix WIP / [WIP] / DNM / [DNM] (case-insensitive) or a
#                 label wip / do-not-merge / blocked (case-insensitive)
#   draft_class   not_draft | wip | no_section | no_blocker_urls | blocked |
#                 blockers_unresolved | ready_candidate (first match, in order)
#   ci            red | pending | green | none, latest CheckRun per
#                 (workflow, name), the reduction merge-chain.sh uses
#   policy.review false for release_please and cross_repo_head; renovate PRs
#                 are reviewed and reported, never fixed or merged
#   policy.fix    false for any sweep_skip, an external author, a WIP marker,
#                 or a draft with no section / no blocker URL
#
# Test seams (no network):
#   PR_SWEEP_FIXTURE=<file>          JSON array of GraphQL page responses,
#                                    consumed in order, replaces gh api graphql
#   PR_SWEEP_BLOCKER_FIXTURE=<file>  JSON object {"<pr url>": "<STATE>"}
#   PR_SWEEP_SELF=<login>            replaces gh api user
#
# Exit: 0 OK/WARN, 1 ERROR, 2 usage.
#
# gh --json fields: PR state is `state` (never `merged`); CI lives in the
# statusCheckRollup contexts (never a flat conclusion field).

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=SCRIPTDIR/lib/summary.sh disable=SC1091
source "$SCRIPT_DIR/lib/summary.sh"

usage() {
  echo "Usage: list-sweep-prs.sh [--resolve-blockers] [--max-prs N] [--out FILE] <owner> <repo>" >&2
  exit 2
}

resolve_blockers=false
max_prs=500
out_file=""
positional=()
while [ $# -gt 0 ]; do
  case "$1" in
    --resolve-blockers) resolve_blockers=true; shift ;;
    --max-prs) [ $# -ge 2 ] || usage; max_prs="$2"; shift 2 ;;
    --out) [ $# -ge 2 ] || usage; out_file="$2"; shift 2 ;;
    -h|--help) usage ;;
    --) shift; while [ $# -gt 0 ]; do positional+=("$1"); shift; done ;;
    -*) echo "Unknown flag: $1" >&2; exit 2 ;;
    *) positional+=("$1"); shift ;;
  esac
done
[ "${#positional[@]}" -eq 2 ] || usage
[[ "$max_prs" =~ ^[1-9][0-9]*$ ]] || { echo "--max-prs must be a positive integer" >&2; exit 2; }
owner="${positional[0]}"
repo="${positional[1]}"

SUMMARY_FD=2
# shellcheck disable=SC2034 # SUMMARY_FD is read by lib/summary.sh
[ -n "$out_file" ] && SUMMARY_FD=1
summary_init "PR SWEEP ROSTER"
summary_kv REPO "$owner/$repo"

fail() {
  summary_issue ERROR "$1" "$2"
  summary_emit
  exit 1
}

command -v jq >/dev/null 2>&1 || fail missing_tool "jq is required but not installed"
if [ -z "${PR_SWEEP_FIXTURE:-}" ] || { [ "$resolve_blockers" = true ] && [ -z "${PR_SWEEP_BLOCKER_FIXTURE:-}" ]; } || [ -z "${PR_SWEEP_SELF:-}" ]; then
  command -v gh >/dev/null 2>&1 || fail missing_tool "gh is required but not installed"
fi

work=$(mktemp -d) || fail mktemp_failed "could not create a temp directory"
{ [ -n "$work" ] && [ -d "$work" ]; } || fail mktemp_failed "could not create a temp directory"
trap 'rm -rf "$work"' EXIT

# --- self ------------------------------------------------------------------
# Never hardcode a login: the self/external split decides which PRs may merge.
if [ -n "${PR_SWEEP_SELF:-}" ]; then
  self_login="$PR_SWEEP_SELF"
else
  self_login=$(gh api user --jq .login 2>/dev/null) || self_login=""
fi
[ -n "$self_login" ] || fail self_unknown "could not read the gh user login (gh api user); author_kind self cannot be decided"
summary_kv SELF "$self_login"

# --- fetch, paginated --------------------------------------------------------
# shellcheck disable=SC2016
graphql_query='
query($owner: String!, $repo: String!, $cursor: String) {
  repository(owner: $owner, name: $repo) {
    defaultBranchRef { name }
    pullRequests(states: OPEN, first: 50, after: $cursor, orderBy: {field: CREATED_AT, direction: ASC}) {
      pageInfo { hasNextPage endCursor }
      nodes {
        number title url isDraft body authorAssociation
        author { login __typename }
        headRefName headRefOid baseRefName isCrossRepository
        headRepositoryOwner { login }
        additions deletions changedFiles
        labels(first: 50) { nodes { name } }
        mergeStateStatus reviewDecision
        commits(last: 1) { nodes { commit { statusCheckRollup { state
          contexts(first: 100) { totalCount nodes {
            __typename
            ... on CheckRun { name status conclusion startedAt completedAt
                              checkSuite { workflowRun { workflow { name } } } }
            ... on StatusContext { context state }
          } } } } } }
      }
    }
  }
}'

echo '[]' > "$work/nodes.json"
page=0
cursor=""
default_branch=""
truncated=false
while :; do
  if [ -n "${PR_SWEEP_FIXTURE:-}" ]; then
    resp=$(jq -c --argjson i "$page" '.[$i] // empty' "$PR_SWEEP_FIXTURE" 2>/dev/null) ||
      fail fixture_unreadable "PR_SWEEP_FIXTURE is not a JSON array: $PR_SWEEP_FIXTURE"
    [ -n "$resp" ] || fail fixture_exhausted "page $((page + 1)) requested but the fixture has only $page page(s)"
  else
    gh_args=(api graphql -f "query=$graphql_query" -F "owner=$owner" -F "repo=$repo")
    [ -n "$cursor" ] && gh_args+=(-f "cursor=$cursor")
    resp=$(gh "${gh_args[@]}" 2>"$work/gh.err") ||
      fail graphql_failed "gh api graphql failed on page $((page + 1)): $(head -c 160 "$work/gh.err")"
  fi
  printf '%s' "$resp" > "$work/page.json"
  jq -e . "$work/page.json" >/dev/null 2>&1 || fail graphql_unparseable "page $((page + 1)) is not JSON"
  gql_err=$(jq -r '(.errors // [])[0].message // empty' "$work/page.json")
  [ -z "$gql_err" ] || fail graphql_error "$gql_err"
  jq -e '.data.repository != null' "$work/page.json" >/dev/null ||
    fail repo_not_found "repository $owner/$repo not found or not readable"
  if [ "$page" -eq 0 ]; then
    default_branch=$(jq -r '.data.repository.defaultBranchRef.name // empty' "$work/page.json")
  fi
  jq -s '.[0] + (.[1].data.repository.pullRequests.nodes // [])' \
    "$work/nodes.json" "$work/page.json" > "$work/nodes.next" && mv "$work/nodes.next" "$work/nodes.json"
  page=$((page + 1))
  has_next=$(jq -r '.data.repository.pullRequests.pageInfo.hasNextPage // false' "$work/page.json")
  cursor=$(jq -r '.data.repository.pullRequests.pageInfo.endCursor // empty' "$work/page.json")
  count=$(jq 'length' "$work/nodes.json")
  [ "$has_next" = "true" ] || break
  if [ "$count" -ge "$max_prs" ]; then truncated=true; break; fi
  [ -n "$cursor" ] || fail graphql_no_cursor "hasNextPage is true but endCursor is empty on page $page"
done
count=$(jq 'length' "$work/nodes.json")
if [ "$count" -gt "$max_prs" ]; then
  truncated=true
  jq --argjson m "$max_prs" '.[:$m]' "$work/nodes.json" > "$work/nodes.next" && mv "$work/nodes.next" "$work/nodes.json"
fi
[ -n "$default_branch" ] || fail no_default_branch "repository $owner/$repo reports no default branch"

# --- shared jq definitions -----------------------------------------------------
# shellcheck disable=SC2016
jq_defs='
def draft_section:
  ((.body // "") | gsub("\r"; "") | split("\n")) as $lines
  | (first(range(0; $lines | length) as $i
           | select($lines[$i] | test("^##\\s+Draft status\\s*$"; "i")) | $i) // null) as $start
  | if $start == null then null
    else ($lines[$start + 1:]) as $rest
      | (first(range(0; $rest | length) as $j | select($rest[$j] | test("^##\\s")) | $j) // ($rest | length)) as $end
      | ($rest[:$end] | join("\n"))
    end;
def blocker_urls:
  if . == null then []
  else [scan("https://github\\.com/[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+/pull/[0-9]+")]
    | reduce .[] as $u ([]; if any(.[]; . == $u) then . else . + [$u] end)
  end;
'

# --- blocker resolution ----------------------------------------------------------
echo '{}' > "$work/states.json"
if [ "$resolve_blockers" = true ]; then
  jq -r "$jq_defs"' [.[] | select(.isDraft == true) | draft_section | blocker_urls[]] | unique[]' \
    "$work/nodes.json" > "$work/blocker-urls.txt"
  while IFS= read -r url; do
    [ -n "$url" ] || continue
    if [ -n "${PR_SWEEP_BLOCKER_FIXTURE:-}" ]; then
      state=$(jq -r --arg u "$url" '.[$u] // empty' "$PR_SWEEP_BLOCKER_FIXTURE" 2>/dev/null) || state=""
    else
      state=$(gh pr view "$url" --json state --jq .state 2>/dev/null) || state=""
    fi
    if [ -z "$state" ]; then
      state="UNKNOWN"
      summary_issue WARN blocker_unresolved "could not read the state of $url; the draft stays blocked"
    fi
    jq --arg u "$url" --arg s "$state" '. + {($u): $s}' "$work/states.json" > "$work/states.next" &&
      mv "$work/states.next" "$work/states.json"
  done < "$work/blocker-urls.txt"
fi

# --- classify ---------------------------------------------------------------------
fetched=$(date -u +%Y-%m-%dT%H:%M:%SZ)
# shellcheck disable=SC2016
jq_classify="$jq_defs"'
def lc: ascii_downcase;
def author_kind($self):
  (.author.login // "") as $l
  | if $l != "" and $l == $self then "self"
    elif (.author.__typename // "") == "Bot" or ($l | endswith("[bot]")) or ($l | startswith("app/")) then "bot"
    else "external" end;
def sweep_skip:
  (.author.login // "") as $l | (.headRefName // "") as $h
  | if ($h | startswith("release-please--")) or ($l | contains("release-please")) then "release_please"
    elif ($h | startswith("renovate/")) or ($l | contains("renovate")) then "renovate"
    elif (.isCrossRepository // false) then "cross_repo_head"
    else null end;
def wip_markers:
  ([(.labels.nodes // [])[] | .name | select(lc as $n | ["wip", "do-not-merge", "blocked"] | index($n)) | "label:" + .])
  + [(.title // "") | capture("^\\s*(?<m>\\[wip\\]|\\[dnm\\]|wip\\b|dnm\\b)"; "i") | "title:" + .m];
# Latest CheckRun per (workflow, name): a run cancelled by concurrency sits beside
# the run that superseded it, and only the latest counts (merge-chain.sh wait_for_ci).
def ci_contexts:
  ((.commits.nodes // [])[0].commit.statusCheckRollup.contexts.nodes // [])
  | map(if .__typename == "CheckRun"
        then {__typename, name, status, conclusion, startedAt, completedAt,
              workflowName: (.checkSuite.workflowRun.workflow.name // "")}
        else . end) as $r
  | [$r[] | select(.__typename != "CheckRun")]
    + ([$r[] | select(.__typename == "CheckRun")]
       | group_by([.workflowName // "", .name])
       | map(max_by(
           ((.startedAt // "") | if startswith("0001-") then "" else . end) as $s
           | ((.completedAt // "") | if startswith("0001-") then "" else . end) as $c
           | if (.status // "COMPLETED") != "COMPLETED" then ["9999", ""] else [$s, $c] end)));
def is_status_context: .__typename == "StatusContext" or (has("state") and (has("status") | not));
def ctx_failed:
  if is_status_context then (.state == "FAILURE" or .state == "ERROR")
  # An allowlist: a completed run passes only on SUCCESS, NEUTRAL or SKIPPED, so a
  # null conclusion or one GitHub adds later reads red instead of falling to green.
  else (.status == "COMPLETED" and ((.conclusion // "") as $c
        | ["SUCCESS", "NEUTRAL", "SKIPPED"] | index($c) | not)) end;
def ctx_pending:
  if is_status_context then (.state == "PENDING" or .state == "EXPECTED")
  else (.status != "COMPLETED") end;
def ci_truncated:
  (((.commits.nodes // [])[0].commit.statusCheckRollup.contexts.totalCount // 0)
   > (((.commits.nodes // [])[0].commit.statusCheckRollup.contexts.nodes // []) | length));

. as $nodes
| [$nodes[]
  | . as $pr
  | author_kind($self) as $ak
  | sweep_skip as $skip
  | wip_markers as $wm
  | ($wm | length > 0) as $wip
  | (if ($pr.isDraft // false) then draft_section else null end) as $section
  | ($section | blocker_urls) as $urls
  | [$urls[] | if $resolved then {url: ., state: ($states[.] // "UNKNOWN")} else {url: .} end] as $blockers
  | (if ($pr.isDraft // false) | not then "not_draft"
     elif $wip then "wip"
     elif $section == null then "no_section"
     elif ($urls | length) == 0 then "no_blocker_urls"
     elif ($resolved | not) then "blockers_unresolved"
     elif any($blockers[]; .state != "MERGED") then "blocked"
     else "ready_candidate" end) as $dclass
  | ($pr | ci_contexts) as $ctx
  | [$ctx[] | select(ctx_failed) | (.name // .context // "?")] as $failed
  | ($pr | ci_truncated) as $ctrunc
  | (if ($failed | length) > 0 then "red"
     elif any($ctx[]; ctx_pending) or $ctrunc then "pending"
     elif ($ctx | length) > 0 then "green"
     else "none" end) as $ci
  | (if $skip == "release_please" or $skip == "cross_repo_head" then $skip else null end) as $review_block
  | (if $skip != null then $skip
     elif $ak == "external" then "external_author"
     elif $wip then "wip"
     elif ($dclass == "no_section" or $dclass == "no_blocker_urls") then $dclass
     else null end) as $fix_block
  | {
      number: $pr.number,
      title: ($pr.title // ""),
      url: ($pr.url // ""),
      is_draft: ($pr.isDraft // false),
      author: ($pr.author.login // ""),
      author_kind: $ak,
      author_association: ($pr.authorAssociation // null),
      head: ($pr.headRefName // ""),
      head_sha: ($pr.headRefOid // ""),
      base: ($pr.baseRefName // ""),
      base_is_default: (($pr.baseRefName // "") == $default),
      cross_repo: ($pr.isCrossRepository // false),
      labels: [($pr.labels.nodes // [])[] | .name],
      additions: ($pr.additions // 0),
      deletions: ($pr.deletions // 0),
      changed_files: ($pr.changedFiles // 0),
      diff_lines: (($pr.additions // 0) + ($pr.deletions // 0)),
      wip: $wip,
      wip_markers: $wm,
      draft_class: $dclass,
      draft_status: {section_present: ($section != null), blockers: $blockers},
      ci: $ci,
      ci_failed: $failed,
      ci_truncated: $ctrunc,
      merge_state: ($pr.mergeStateStatus // null),
      review_decision: ($pr.reviewDecision // null),
      sweep_skip: $skip,
      policy: {review: ($review_block == null), review_block: $review_block,
               fix: ($fix_block == null), fix_block: $fix_block}
    }]
| sort_by(.number) as $prs
| {
    repo: $repo, default_branch: $default, self: $self, fetched: $fetched,
    pages: $pages, truncated: $truncated, max_prs: $max, blockers_resolved: $resolved,
    counts: {
      prs: ($prs | length),
      drafts: ([$prs[] | select(.is_draft)] | length),
      ready_candidates: ([$prs[] | select(.draft_class == "ready_candidate")] | length),
      wip: ([$prs[] | select(.wip)] | length),
      skipped: ([$prs[] | select(.sweep_skip != null)] | length),
      reviewable: ([$prs[] | select(.policy.review)] | length),
      fixable: ([$prs[] | select(.policy.fix)] | length),
      ci_red: ([$prs[] | select(.ci == "red")] | length),
      ci_truncated: ([$prs[] | select(.ci_truncated)] | length)
    },
    prs: $prs
  }'

jq --arg self "$self_login" --arg default "$default_branch" --arg repo "$owner/$repo" \
   --arg fetched "$fetched" --argjson pages "$page" --argjson truncated "$truncated" \
   --argjson max "$max_prs" --argjson resolved "$resolve_blockers" \
   --slurpfile states_in "$work/states.json" \
   "\$states_in[0] as \$states | $jq_classify" \
   "$work/nodes.json" > "$work/roster.json" 2>"$work/jq.err" ||
  fail classify_failed "jq classification failed: $(head -c 160 "$work/jq.err")"

# --- summary ------------------------------------------------------------------------
c() { jq -r ".counts.$1" "$work/roster.json"; }
summary_kv DEFAULT_BRANCH "$default_branch"
summary_kv PRS_FETCHED "$(c prs)"
summary_kv PAGES "$page"
summary_kv TRUNCATED "$truncated"
summary_kv BLOCKERS_RESOLVED "$resolve_blockers"
summary_kv DRAFTS "$(c drafts)"
summary_kv READY_CANDIDATES "$(c ready_candidates)"
summary_kv WIP "$(c wip)"
summary_kv SKIPPED "$(c skipped)"
summary_kv REVIEWABLE "$(c reviewable)"
summary_kv FIXABLE "$(c fixable)"
summary_kv CI_RED "$(c ci_red)"
[ "$truncated" = true ] &&
  summary_issue WARN truncated "stopped at --max-prs $max_prs; PRs past the ceiling are not in the roster"
ci_trunc=$(c ci_truncated)
[ "$ci_trunc" -gt 0 ] &&
  summary_issue WARN ci_contexts_truncated "$ci_trunc PR(s) have more than 100 checks; their ci reads pending, never green"

if [ -n "$out_file" ]; then
  cp "$work/roster.json" "$out_file" || fail write_failed "could not write $out_file"
  summary_kv OUT "$out_file"
else
  cat "$work/roster.json"
fi
summary_emit
exit 0
