#!/usr/bin/env bash
# git-triage data-gathering (issue #1552).
# DATA-ONLY: fetches issue/PR JSON, computes age, categorizes PRs via a pure
# first-match table over enum fields, and extracts closing keywords. Performs
# NO mutations. Issue-categorization judgment stays with the model.
#
# Network seam: every `gh` call is routed through an injectable fixture so tests
# run fully offline. Set GIT_TRIAGE_ISSUES_FIXTURE / GIT_TRIAGE_PRS_FIXTURE to
# canned gh JSON arrays, GIT_TRIAGE_COUNTS_FIXTURE to a canned open-count
# GraphQL response, or GIT_TRIAGE_NO_FETCH=1 to skip live fetches entirely.
#
# Usage: bash git-triage.sh [--home-dir <path>] [--project-dir <path>]
#          [--repo owner/name] [--type issues|prs|both] [--batch N]
#          [--days-stale-issue N] [--days-stale-pr N]
#
# Coverage keys (issue #2714). --batch caps each `gh … list` call, and gh
# returns the N most recently CREATED open items, so a batch is a sample, not
# the backlog. Each half therefore emits:
#   <HALF>_FETCHED    items in this batch (the domain count)
#   <HALF>_TOTAL      unbounded open count, or `unknown` if it could not be read
#   <HALF>_TRUNCATED  true | false | unknown  (true when TOTAL > FETCHED)
# and the trailer carries a TRUNCATED roll-up (true > unknown > false).
#
# Progress keys (issue #2904), per fetched issue:
#   ISSUE_<n>_CHECKBOXES       <done>/<total> task-list boxes in the body (fenced
#                              code and HTML comments skipped); 0/0 when there are none
#   ISSUE_<n>_SUBISSUES        <completed>/<total> from subIssuesSummary, or unknown
#   ISSUE_<n>_MERGED_PRS       <owner/repo>#<num>[*],... merged PRs that reference
#                              the issue (cross-repo included); `*` = the PR closes
#                              it (willCloseTarget, or a Development-sidebar link);
#                              none, or unknown when the progress query failed
#   ISSUE_<n>_CLOSE_CANDIDATE  true when every box is ticked, every sub-issue is
#                              complete, or a merged PR carries `*`; a hint to
#                              verify, never an auto-close
# GIT_TRIAGE_PROGRESS_FIXTURE replaces the paginated progress query with canned
# GraphQL page responses (one or more JSON objects).
# ISSUE_COUNT= / ISSUES: are NOT GitHub issues: they are this collector's own
# diagnostics, per .claude/rules/structured-script-output.md.
#
# REST fallback (issue #3362). Claude Code cloud sessions answer every GraphQL
# call (gh issue list, gh pr list, gh api graphql) with "HTTP 403: GitHub GraphQL
# is not available". The collector keeps GraphQL first and, on that 403 only,
# reads everything from REST instead: repos/{o}/{r}/issues (entries carrying
# `pull_request` are split out), repos/{o}/{r}/pulls plus per-PR pulls/{n},
# pulls/{n}/reviews, commits/{sha}/check-runs and commits/{sha}/status, and the
# open totals from search/issues total_count. Pages are walked with an explicit
# &page=N loop that stops on a short page, never `gh api --paginate`: its Link
# header points at repositories/{id} paths the proxy rejects. The fallback emits
# GRAPHQL_BLOCKED=true plus
#   REST_FALLBACK_UNKNOWN       keys with no cheap REST source (MERGED_PRS), or none
#   REST_FALLBACK_APPROXIMATED  keys derived differently (REVIEW: latest review per
#                               reviewer, not branch-protection reviewDecision), or none
# GIT_TRIAGE_REST_PER_PAGE (default 100) is the REST page size, a test seam.
#
# gh --json fields: PR merge state is `state`/`mergedAt` (never `merged`);
# CI status lives in `statusCheckRollup[].conclusion` (never a flat field).

set -uo pipefail

home_dir=""
project_dir=""
repo=""
triage_type="both"
batch="10"
days_stale_issue="90"
days_stale_pr="30"

while [ $# -gt 0 ]; do
  case "$1" in
    --home-dir) home_dir="$2"; shift 2 ;;
    --project-dir) project_dir="$2"; shift 2 ;;
    --repo) repo="$2"; shift 2 ;;
    --type) triage_type="$2"; shift 2 ;;
    --batch) batch="$2"; shift 2 ;;
    --days-stale-issue) days_stale_issue="$2"; shift 2 ;;
    --days-stale-pr) days_stale_pr="$2"; shift 2 ;;
    *) shift ;;
  esac
done

: "${home_dir:=$HOME}"
: "${project_dir:=$(pwd)}"

echo "=== GIT TRIAGE ==="

triage_issues_list=""
triage_issue_count=0
triage_status="OK"

if ! command -v jq >/dev/null 2>&1; then
  echo "JQ_AVAILABLE=false"
  echo "STATUS=ERROR"
  echo "ISSUE_COUNT=1"
  echo "ISSUES:"
  echo "  - SEVERITY=ERROR TYPE=missing_tool MSG=jq is required but not installed"
  echo "=== END GIT TRIAGE ==="
  exit 1
fi
echo "JQ_AVAILABLE=true"

# Scratch space for the REST fallback (issue #3362): a marker file records that
# GraphQL answered with the proxy's 403, so every later fetch (each runs in its
# own command-substitution subshell) goes straight to REST. Without a scratch
# dir the fallback is disabled and the GraphQL path behaves as before.
triage_tmp="$(mktemp -d 2>/dev/null)" || triage_tmp=""
if [ -n "$triage_tmp" ]; then
  trap 'rm -rf "$triage_tmp"' EXIT
fi
rest_marker="${triage_tmp:+${triage_tmp}/graphql-blocked}"
rest_per_page="${GIT_TRIAGE_REST_PER_PAGE:-100}"
case "$rest_per_page" in ''|*[!0-9]*|0) rest_per_page=100 ;; esac
rest_repo="$repo"
[ -n "$rest_repo" ] || rest_repo='{owner}/{repo}'

# now_epoch is overridable for deterministic age tests.
now_epoch="${GIT_TRIAGE_NOW_EPOCH:-$(date +%s)}"

# Convert an ISO 8601 timestamp to epoch seconds (BSD/GNU portable).
iso_to_epoch() {
  local iso_ts="$1"
  local out=""
  out=$(date -j -f "%Y-%m-%dT%H:%M:%SZ" "$iso_ts" "+%s" 2>/dev/null) && { echo "$out"; return; }
  out=$(date -d "$iso_ts" "+%s" 2>/dev/null) && { echo "$out"; return; }
  echo ""
}

age_days() {
  local iso_ts="$1"
  local ts_epoch=""
  ts_epoch=$(iso_to_epoch "$iso_ts")
  [ -z "$ts_epoch" ] && { echo "-1"; return; }
  echo $(( (now_epoch - ts_epoch) / 86400 ))
}

# Pure first-match PR categorizer over enum JSON fields.
# Args: is_draft mergeable merge_state_status review_decision worst_conclusion age_days
# worst_conclusion is the most severe statusCheckRollup[].conclusion (FAILURE wins).
# Echoes exactly one category. No side effects.
categorize_pr() {
  local pr_is_draft="$1"
  local pr_mergeable="$2"
  local pr_merge_state="$3"
  local pr_review="$4"
  local pr_worst_check="$5"
  local pr_age="$6"

  if [ "$pr_is_draft" = "true" ]; then
    echo "draft"; return
  fi
  if [ "$pr_worst_check" = "FAILURE" ]; then
    echo "needs-fix"; return
  fi
  if [ "$pr_merge_state" = "BEHIND" ] || [ "$pr_merge_state" = "DIRTY" ] || [ "$pr_mergeable" = "CONFLICTING" ]; then
    echo "needs-rebase"; return
  fi
  if [ "$pr_review" = "CHANGES_REQUESTED" ]; then
    echo "changes-requested"; return
  fi
  if [ "$pr_mergeable" = "MERGEABLE" ] && \
     { [ "$pr_merge_state" = "CLEAN" ] || [ "$pr_merge_state" = "HAS_HOOKS" ] || [ "$pr_merge_state" = "UNSTABLE" ]; } && \
     [ "$pr_review" = "APPROVED" ]; then
    echo "ready-to-merge"; return
  fi
  if [ "$pr_review" = "REVIEW_REQUIRED" ] || [ "$pr_review" = "null" ] || [ -z "$pr_review" ]; then
    if [ "$pr_worst_check" != "FAILURE" ]; then
      echo "awaiting-review"; return
    fi
  fi
  if [ "$pr_age" -gt "$days_stale_pr" ] 2>/dev/null; then
    echo "stale"; return
  fi
  echo "uncategorized"
}

# --- GraphQL call with 403 detection (issue #3362) -------------------------
rest_mode() {
  [ -n "$rest_marker" ] && [ -e "$rest_marker" ]
}

# Run a GraphQL-backed gh command. Prints its stdout and returns its exit code,
# as `gh … 2>/dev/null` did. When the proxy refuses GraphQL, prints nothing,
# drops the marker, and returns non-zero; the caller then checks rest_mode.
run_gql() {
  local gql_err_file="/dev/null" gql_out="" gql_rc=0
  [ -n "$triage_tmp" ] && gql_err_file="${triage_tmp}/gql-err"
  gql_out=$(gh "$@" 2>"$gql_err_file") || gql_rc=$?
  if [ "$gql_rc" -ne 0 ] && [ -n "$rest_marker" ] \
     && grep -qF 'GraphQL is not available' "$gql_err_file" 2>/dev/null; then
    : > "$rest_marker"
    return 2
  fi
  [ -n "$gql_out" ] && printf '%s\n' "$gql_out"
  return "$gql_rc"
}

# --- REST fallback helpers (issue #3362) ------------------------------------
# Walk a REST list endpoint page by page (&per_page=…&page=N) and print each
# page's items that pass the jq filter as one JSON array per line. Stops on a
# short page (fewer than per_page raw items), once <want> filtered items are in
# hand, on a failed or non-array page, or after 20 pages.
rest_get_pages() {
  local rest_ep="$1" rest_want="$2" rest_filter="$3"
  local rest_page_no=1 rest_raw="" rest_raw_n=0 rest_kept="" rest_got=0
  case "$rest_want" in ''|*[!0-9]*) return ;; esac
  while [ "$rest_page_no" -le 20 ] && [ "$rest_got" -lt "$rest_want" ]; do
    rest_raw=$(gh api "${rest_ep}&per_page=${rest_per_page}&page=${rest_page_no}" 2>/dev/null) || break
    jq -e 'type == "array"' >/dev/null 2>&1 <<<"$rest_raw" || break
    rest_raw_n=$(jq 'length' <<<"$rest_raw")
    rest_kept=$(jq -c "[ .[] | ${rest_filter} ]" <<<"$rest_raw") || break
    printf '%s\n' "$rest_kept"
    rest_got=$((rest_got + $(jq 'length' <<<"$rest_kept")))
    [ "$rest_raw_n" -lt "$rest_per_page" ] && break
    rest_page_no=$((rest_page_no + 1))
  done
}

# Fetch one REST object into a file; writes `null` when the call or JSON fails,
# so the jq that reads it maps the field to UNKNOWN/null instead of failing.
rest_fetch_json() {
  local rest_file="$1" rest_ep="$2"
  if ! gh api "$rest_ep" >"$rest_file" 2>/dev/null || ! jq -e . "$rest_file" >/dev/null 2>&1; then
    printf 'null\n' >"$rest_file"
  fi
}

# Issues in `gh issue list --json` shape. REST `comments` is a count, not an
# array; the per-issue jq's `length` returns a number's own value, so
# ISSUE_<n>_COMMENTS is the same either way. sub_issues_summary becomes
# subIssuesSummary for the progress keys.
fetch_issues_rest() {
  rest_get_pages "repos/${rest_repo}/issues?state=open&sort=created&direction=desc" "$batch" \
      'select(.pull_request == null)' \
    | jq -s --argjson n "$batch" '(add // []) | .[:$n] | map({
        number, title, body,
        labels: [.labels[]? | {name}],
        createdAt: .created_at, updatedAt: .updated_at,
        comments: (.comments // 0),
        assignees: [.assignees[]? | {login}],
        author: {login: .user.login},
        subIssuesSummary: (.sub_issues_summary | if type == "object" then {total, completed} else null end)
      })' 2>/dev/null || echo "[]"
}

# PRs in `gh pr list --json` shape. mergeable/mergeStateStatus come from
# pulls/{n} (mergeable true/false/null, mergeable_state upper-cased: the same
# enum as GraphQL's mergeStateStatus); reviewDecision is approximated from the
# latest APPROVED/CHANGES_REQUESTED/DISMISSED review per reviewer;
# statusCheckRollup merges the first 100 check-runs and the commit statuses.
fetch_prs_rest() {
  local rest_pr="" rest_pr_num="" rest_pr_sha=""
  case "$batch" in ''|*[!0-9]*) echo "[]"; return ;; esac
  rest_get_pages "repos/${rest_repo}/pulls?state=open&sort=created&direction=desc" "$batch" '.' \
    | jq -c -s --argjson n "$batch" '(add // []) | .[:$n] | .[]' 2>/dev/null \
    | while IFS= read -r rest_pr; do
        rest_pr_num=$(jq -r '.number // empty' <<<"$rest_pr")
        [ -n "$rest_pr_num" ] || continue
        rest_pr_sha=$(jq -r '.head.sha // empty' <<<"$rest_pr")
        rest_fetch_json "${triage_tmp}/pr-detail.json" "repos/${rest_repo}/pulls/${rest_pr_num}"
        rest_fetch_json "${triage_tmp}/pr-reviews.json" "repos/${rest_repo}/pulls/${rest_pr_num}/reviews?per_page=100"
        if [ -n "$rest_pr_sha" ]; then
          rest_fetch_json "${triage_tmp}/pr-checks.json" "repos/${rest_repo}/commits/${rest_pr_sha}/check-runs?per_page=100"
          rest_fetch_json "${triage_tmp}/pr-status.json" "repos/${rest_repo}/commits/${rest_pr_sha}/status"
        else
          printf 'null\n' >"${triage_tmp}/pr-checks.json"
          printf 'null\n' >"${triage_tmp}/pr-status.json"
        fi
        jq -c --slurpfile d "${triage_tmp}/pr-detail.json" --slurpfile rv "${triage_tmp}/pr-reviews.json" \
              --slurpfile ck "${triage_tmp}/pr-checks.json" --slurpfile st "${triage_tmp}/pr-status.json" '
          ($d[0]) as $d | ($rv[0]) as $rv | ($ck[0]) as $ck | ($st[0]) as $st
          | {
              number, title, body,
              createdAt: .created_at, updatedAt: .updated_at,
              isDraft: (.draft == true),
              baseRefName: .base.ref, headRefName: .head.ref,
              author: {login: .user.login, is_bot: (.user.type == "Bot")},
              labels: [.labels[]? | {name}],
              mergeable: (if ($d | type) != "object" then "UNKNOWN"
                          elif $d.mergeable == true then "MERGEABLE"
                          elif $d.mergeable == false then "CONFLICTING"
                          else "UNKNOWN" end),
              mergeStateStatus: (if ($d | type) == "object" and ($d.mergeable_state | type) == "string"
                                 then ($d.mergeable_state | ascii_upcase) else "UNKNOWN" end),
              reviewDecision: (if ($rv | type) != "array" then null else
                ([ $rv[] | select(.state == "APPROVED" or .state == "CHANGES_REQUESTED" or .state == "DISMISSED") ]
                 | group_by(.user.login) | map(last.state)) as $latest
                | if any($latest[]; . == "CHANGES_REQUESTED") then "CHANGES_REQUESTED"
                  elif any($latest[]; . == "APPROVED") then "APPROVED"
                  else null end end),
              statusCheckRollup: (
                [ (if ($ck | type) == "object" then ($ck.check_runs // []) else [] end)[]?
                  | {name, conclusion: (if (.conclusion | type) == "string" then (.conclusion | ascii_upcase) else null end)} ]
                + [ (if ($st | type) == "object" then ($st.statuses // []) else [] end)[]?
                  | {context, conclusion: ({"failure":"FAILURE","error":"FAILURE","success":"SUCCESS"}[.state // ""] // null)} ])
            }' <<<"$rest_pr" 2>/dev/null
      done | jq -s '.' 2>/dev/null || echo "[]"
}

# Open totals from search/issues total_count, in the GraphQL count response's
# shape so count_of reads both paths; a failed search leaves its half unknown.
fetch_counts_rest() {
  local rest_ic="" rest_pc=""
  rest_ic=$(gh api "search/issues?q=repo:${rest_repo}+is:issue+is:open&per_page=1" 2>/dev/null \
    | jq -r '.total_count // empty' 2>/dev/null)
  rest_pc=$(gh api "search/issues?q=repo:${rest_repo}+is:pr+is:open&per_page=1" 2>/dev/null \
    | jq -r '.total_count // empty' 2>/dev/null)
  jq -nc --arg ic "$rest_ic" --arg pc "$rest_pc" '{data:{repository:(
      (if ($ic | test("^[0-9]+$")) then {issues:{totalCount:($ic | tonumber)}} else {} end)
      + (if ($pc | test("^[0-9]+$")) then {pullRequests:{totalCount:($pc | tonumber)}} else {} end))}}'
}

# --- Fetch issues ---------------------------------------------------------
fetch_issues() {
  if [ -n "${GIT_TRIAGE_ISSUES_FIXTURE:-}" ]; then
    cat "$GIT_TRIAGE_ISSUES_FIXTURE"
    return
  fi
  if [ "${GIT_TRIAGE_NO_FETCH:-}" = "1" ]; then
    echo "[]"
    return
  fi
  if rest_mode; then fetch_issues_rest; return; fi
  local repo_flag=() issues_out="" issues_rc=0
  [ -n "$repo" ] && repo_flag=(--repo "$repo")
  issues_out=$(run_gql issue list "${repo_flag[@]}" --state open --limit "$batch" \
    --json number,title,body,labels,createdAt,updatedAt,comments,assignees,author) || issues_rc=$?
  if rest_mode; then fetch_issues_rest; return; fi
  [ -n "$issues_out" ] && printf '%s\n' "$issues_out"
  [ "$issues_rc" -eq 0 ] || echo "[]"
}

# --- Fetch PRs ------------------------------------------------------------
fetch_prs() {
  if [ -n "${GIT_TRIAGE_PRS_FIXTURE:-}" ]; then
    cat "$GIT_TRIAGE_PRS_FIXTURE"
    return
  fi
  if [ "${GIT_TRIAGE_NO_FETCH:-}" = "1" ]; then
    echo "[]"
    return
  fi
  if rest_mode; then fetch_prs_rest; return; fi
  local repo_flag=() prs_out="" prs_rc=0
  [ -n "$repo" ] && repo_flag=(--repo "$repo")
  prs_out=$(run_gql pr list "${repo_flag[@]}" --state open --limit "$batch" \
    --json number,title,createdAt,updatedAt,mergeable,mergeStateStatus,reviewDecision,statusCheckRollup,isDraft,baseRefName,headRefName,author,labels,body) || prs_rc=$?
  if rest_mode; then fetch_prs_rest; return; fi
  [ -n "$prs_out" ] && printf '%s\n' "$prs_out"
  [ "$prs_rc" -eq 0 ] || echo "[]"
}

# --- Fetch unbounded open counts (issue #2714) -----------------------------
# `--limit "$batch"` above is a cap, so the lists alone cannot say whether they
# are the whole backlog. One GraphQL call returns the exact open totals for
# both halves. Without --repo, gh's {owner}/{repo} placeholders (which only -F
# resolves) pick the same cwd repository `gh issue list` infers; with --repo,
# the explicit values go through -f so a numeric-looking name stays a string.
# Prints nothing when the count is unavailable; the caller reads that as
# `unknown`, never as zero.
fetch_counts() {
  if [ -n "${GIT_TRIAGE_COUNTS_FIXTURE:-}" ]; then
    cat "$GIT_TRIAGE_COUNTS_FIXTURE"
    return
  fi
  if [ "${GIT_TRIAGE_NO_FETCH:-}" = "1" ]; then
    return
  fi
  # shellcheck disable=SC2016  # $owner/$name are GraphQL variables, not shell
  local count_query='query($owner:String!,$name:String!){repository(owner:$owner,name:$name){issues(states:OPEN){totalCount} pullRequests(states:OPEN){totalCount}}}'
  if rest_mode; then fetch_counts_rest; return; fi
  if [ -n "$repo" ]; then
    run_gql api graphql -f owner="${repo%%/*}" -f name="${repo#*/}" -f query="$count_query"
  else
    run_gql api graphql -F owner='{owner}' -F name='{repo}' -f query="$count_query"
  fi
  if rest_mode; then fetch_counts_rest; fi
}

# --- Fetch per-issue progress (issue #2904) --------------------------------
# One GraphQL query, paginated by hand so it stops at --batch: the open issues
# in `gh issue list`'s order (newest created first) with subIssuesSummary and
# the timeline events that link a PR to the issue. Each page response is printed
# on its own line; the caller slurps them. Prints nothing when unavailable, which
# the caller reads as `unknown` for SUBISSUES/MERGED_PRS, never as zero.
# timelineItems takes the LAST 100 events: the PR that finished the work is
# usually among the most recent references.
fetch_progress() {
  if [ -n "${GIT_TRIAGE_PROGRESS_FIXTURE:-}" ]; then
    cat "$GIT_TRIAGE_PROGRESS_FIXTURE"
    return
  fi
  if [ "${GIT_TRIAGE_NO_FETCH:-}" = "1" ]; then
    return
  fi
  case "$batch" in ''|*[!0-9]*) return ;; esac
  # On the REST fallback (#3362) the caller builds progress from the issues.
  rest_mode && return
  # shellcheck disable=SC2016  # $owner/$name/$first/$cursor are GraphQL variables, not shell
  local progress_query='query($owner:String!,$name:String!,$first:Int!,$cursor:String){repository(owner:$owner,name:$name){issues(states:OPEN,first:$first,after:$cursor,orderBy:{field:CREATED_AT,direction:DESC}){pageInfo{hasNextPage endCursor} nodes{number subIssuesSummary{total completed} timelineItems(last:100,itemTypes:[CROSS_REFERENCED_EVENT,CONNECTED_EVENT,DISCONNECTED_EVENT]){nodes{__typename ... on CrossReferencedEvent{willCloseTarget source{__typename ... on PullRequest{number state mergedAt repository{nameWithOwner}}}} ... on ConnectedEvent{subject{__typename ... on PullRequest{number state mergedAt repository{nameWithOwner}}}} ... on DisconnectedEvent{subject{__typename ... on PullRequest{number repository{nameWithOwner}}}}}}}}}}'
  local repo_args=()
  if [ -n "$repo" ]; then
    repo_args=(-f owner="${repo%%/*}" -f name="${repo#*/}")
  else
    repo_args=(-F owner='{owner}' -F name='{repo}')
  fi
  local progress_remaining="$batch" progress_cursor="" progress_pages=0
  local progress_page="" progress_size=0 progress_got=0 progress_next=""
  local cursor_args=()
  while [ "$progress_remaining" -gt 0 ] && [ "$progress_pages" -lt 20 ]; do
    progress_size=$(( progress_remaining < 50 ? progress_remaining : 50 ))
    cursor_args=()
    [ -n "$progress_cursor" ] && cursor_args=(-f cursor="$progress_cursor")
    progress_page=$(run_gql api graphql "${repo_args[@]}" -F first="$progress_size" "${cursor_args[@]}" \
      -f query="$progress_query") || break
    jq -e '.data.repository.issues.nodes | type == "array"' >/dev/null 2>&1 <<<"$progress_page" || break
    printf '%s\n' "$progress_page"
    progress_pages=$((progress_pages + 1))
    progress_got=$(jq '.data.repository.issues.nodes | length' <<<"$progress_page")
    [ "$progress_got" -gt 0 ] 2>/dev/null || break
    progress_remaining=$((progress_remaining - progress_got))
    progress_next=$(jq -r 'if .data.repository.issues.pageInfo.hasNextPage == true then (.data.repository.issues.pageInfo.endCursor // "") else "" end' <<<"$progress_page")
    [ -n "$progress_next" ] || break
    progress_cursor="$progress_next"
  done
}

# Extract one half's open total from the count response; `unknown` unless it is
# a plain non-negative integer (covers no response, non-JSON, repository:null).
count_of() {
  local counts_json="$1" field="$2"
  local count_value=""
  count_value=$(jq -r --arg f "$field" '.data.repository[$f].totalCount // empty' <<<"$counts_json" 2>/dev/null)
  case "$count_value" in
    ''|*[!0-9]*) echo "unknown" ;;
    *) echo "$count_value" ;;
  esac
}

# Pure: true when the open total exceeds what was fetched; unknown without a total.
truncation_state() {
  local fetched_count="$1" open_total="$2"
  case "$open_total" in
    ''|*[!0-9]*) echo "unknown"; return ;;
  esac
  if [ "$open_total" -gt "$fetched_count" ]; then echo "true"; else echo "false"; fi
}

# TRUNCATED roll-up over the halves emitted this run: true > unknown > false.
truncated_rollup="false"
note_truncation() {
  case "$1" in
    true) truncated_rollup="true" ;;
    unknown) [ "$truncated_rollup" = "false" ] && truncated_rollup="unknown" ;;
  esac
}

counts_json=$(fetch_counts)

# --- Issues section -------------------------------------------------------
if [ "$triage_type" != "prs" ]; then
  issues_json=$(fetch_issues)
  if ! echo "$issues_json" | jq empty 2>/dev/null; then
    issues_json="[]"
    triage_issues_list="${triage_issues_list}  - SEVERITY=WARN TYPE=invalid_issues_json MSG=issue fetch returned non-JSON\n"
    triage_issue_count=$((triage_issue_count + 1))
    [ "$triage_status" = "OK" ] && triage_status="WARN"
  fi
  issues_fetched=$(echo "$issues_json" | jq 'length')
  issues_open_total=$(count_of "$counts_json" issues)
  issues_truncated=$(truncation_state "$issues_fetched" "$issues_open_total")
  note_truncation "$issues_truncated"
  echo "ISSUES_FETCHED=${issues_fetched}"
  echo "ISSUES_TOTAL=${issues_open_total}"
  echo "ISSUES_TRUNCATED=${issues_truncated}"

  # Progress map (issue #2904), keyed by issue number: sub-issue ratio, merged
  # PRs, and whether any merged PR closes the issue. A merged PR is one with
  # mergedAt set or state MERGED; `*` marks a closing link, either a
  # CrossReferencedEvent with willCloseTarget or a Development-sidebar
  # ConnectedEvent that no later DisconnectedEvent undid. Non-JSON pages and
  # responses without issue nodes contribute nothing, so an issue missing from
  # the map reads `unknown`.
  declare -A prog_sub_map=()
  declare -A prog_prs_map=()
  declare -A prog_closing_map=()
  # On the REST fallback (#3362) the issues already carry subIssuesSummary;
  # there is no cheap REST source for the timeline, so restFallback nodes read
  # MERGED_PRS=unknown.
  progress_src=$(fetch_progress)
  if rest_mode; then
    progress_src=$(jq -c '{data:{repository:{issues:{nodes:[ .[] | {number, subIssuesSummary, restFallback: true} ]}}}}' \
      <<<"$issues_json" 2>/dev/null)
  fi
  while IFS=$'\t' read -r prog_num prog_sub prog_prs prog_closing; do
    [ -z "$prog_num" ] && continue
    prog_sub_map["$prog_num"]="$prog_sub"
    prog_prs_map["$prog_num"]="$prog_prs"
    prog_closing_map["$prog_num"]="$prog_closing"
  done < <(printf '%s\n' "$progress_src" | jq -rs '
    def pr_key($pr): ($pr.repository.nameWithOwner // "") + "#" + ($pr.number | tostring);
    def is_pr($pr): ($pr | type) == "object" and $pr.__typename == "PullRequest" and $pr.number != null;
    [ .[] | objects | .data.repository.issues.nodes? // empty | .[]? | objects | select(.number != null) ]
    | unique_by(.number)
    | .[]
    | . as $issue
    | (reduce ($issue.timelineItems.nodes // [])[]? as $ev ({};
        if $ev.__typename == "CrossReferencedEvent" and is_pr($ev.source) then
          pr_key($ev.source) as $k
          | .[$k] = ((.[$k] // {xclose:false, linked:false})
              + {repo: ($ev.source.repository.nameWithOwner // ""), num: $ev.source.number,
                 merged: ($ev.source.mergedAt != null or $ev.source.state == "MERGED")}
              | .xclose = (.xclose or ($ev.willCloseTarget == true)))
        elif $ev.__typename == "ConnectedEvent" and is_pr($ev.subject) then
          pr_key($ev.subject) as $k
          | .[$k] = ((.[$k] // {xclose:false})
              + {repo: ($ev.subject.repository.nameWithOwner // ""), num: $ev.subject.number,
                 merged: ($ev.subject.mergedAt != null or $ev.subject.state == "MERGED"), linked: true})
        elif $ev.__typename == "DisconnectedEvent" and is_pr($ev.subject) then
          pr_key($ev.subject) as $k
          | if .[$k] then .[$k].linked = false else . end
        else . end)) as $prs
    | [ $prs[] | select(.merged == true and .num != null) ] | sort_by(.repo, .num) as $merged
    | [
        ($issue.number | tostring),
        (if ($issue.subIssuesSummary | type) == "object"
           then "\($issue.subIssuesSummary.completed // 0)/\($issue.subIssuesSummary.total // 0)"
           else "unknown" end),
        (if $issue.restFallback == true then "unknown" else
          ([ $merged[] | "\(.repo)#\(.num)" + (if (.xclose or .linked) then "*" else "" end) ]
            | join(",") | if . == "" then "none" else . end) end),
        ([ $merged[] | select(.xclose or .linked) ] | length > 0 | tostring)
      ] | @tsv' 2>/dev/null)

  # Per-issue: number, age, referenced PR numbers (closing-keyword candidates),
  # comment count, and the title (issue #2480). The title comes free from the
  # `gh issue list --json` call above, and without it the collector's own output
  # is unreadable — an issue number plus an age does not say what the issue *is*,
  # so triage had to make a second full pass just to recover titles.
  #
  # The title is sanitized (tabs/CRs/newlines → spaces) so it can never break the
  # TSV row or the line-oriented KEY=VALUE contract, and is emitted last so it is
  # the `read` remainder field. Format mirrors session-survey.sh's ISSUE_<n>_TITLE.
  #
  # Empty fields are emitted as the literal `none` for the same reason the PR
  # section does it: `read` with a tab IFS collapses consecutive tabs (tab is
  # IFS-whitespace), so an empty refs field silently shifted every later column
  # — before this guard, an issue with no `#N` references reported the comment
  # count as its REFS and an empty COMMENTS.
  echo "$issues_json" | jq -r '
    # Task-list boxes as "<done>/<total>" (issue #2904). A box is a list item
    # (-, *, + or 1./1)) whose text opens with [ ], [x] or [X]. HTML comments
    # (issue-template boilerplate) are stripped first. Lines inside a ``` or ~~~
    # fence are skipped: a fence closes on a line of the same character, at
    # least as long as the opener, with nothing after it (CommonMark: a closing
    # fence carries no info string, so ```bash inside a fence is content).
    def checkbox_ratio:
      (. // "") | gsub("\r"; "") | gsub("(?s)<!--.*?-->"; "") | split("\n")
      | reduce .[] as $line ({fence: null, done: 0, total: 0};
          ([ $line | capture("^ {0,3}(?<f>`{3,}|~{3,})") | .f ] | first) as $marker
          | if .fence != null then
              (if $marker != null and ($marker[0:1] == .fence[0:1]) and (($marker | length) >= (.fence | length))
                    and ($line | test("^ {0,3}(`{3,}|~{3,})\\s*$"))
                 then .fence = null else . end)
            elif $marker != null then .fence = $marker
            elif ($line | test("^\\s*(?:[-*+]|[0-9]+[.)])\\s+\\[[ xX]\\](?:\\s|$)")) then
              .total += 1
              | if ($line | test("^\\s*(?:[-*+]|[0-9]+[.)])\\s+\\[[xX]\\]")) then .done += 1 else . end
            else . end)
      | "\(.done)/\(.total)";
    .[] | [
    (.number|tostring),
    .updatedAt,
    ((((.title // "") + " " + (.body // "")) | [scan("#[0-9]+")] | unique | join(",")) | if . == "" then "none" else . end),
    (.comments | length | tostring),
    (.body | checkbox_ratio),
    (((.title // "") | gsub("[\t\r\n]"; " ")) | if . == "" then "none" else . end)
  ] | @tsv' 2>/dev/null | while IFS=$'\t' read -r issue_num issue_updated issue_refs issue_comments issue_boxes issue_title; do
    issue_age=$(age_days "$issue_updated")
    echo "ISSUE_${issue_num}_TITLE=${issue_title:-none}"
    echo "ISSUE_${issue_num}_AGE_DAYS=${issue_age}"
    echo "ISSUE_${issue_num}_REFS=${issue_refs:-none}"
    echo "ISSUE_${issue_num}_COMMENTS=${issue_comments}"
    if [ "$issue_age" -gt "$days_stale_issue" ] 2>/dev/null; then
      echo "ISSUE_${issue_num}_STALE_CANDIDATE=true"
    else
      echo "ISSUE_${issue_num}_STALE_CANDIDATE=false"
    fi
    issue_subs="${prog_sub_map[$issue_num]:-unknown}"
    echo "ISSUE_${issue_num}_CHECKBOXES=${issue_boxes}"
    echo "ISSUE_${issue_num}_SUBISSUES=${issue_subs}"
    echo "ISSUE_${issue_num}_MERGED_PRS=${prog_prs_map[$issue_num]:-unknown}"
    # Close-candidate hint: any one complete signal suffices.
    issue_close="false"
    case "$issue_boxes" in
      */*) [ "${issue_boxes#*/}" -gt 0 ] && [ "${issue_boxes%/*}" = "${issue_boxes#*/}" ] && issue_close="true" ;;
    esac
    case "$issue_subs" in
      */*) [ "${issue_subs#*/}" -gt 0 ] 2>/dev/null && [ "${issue_subs%/*}" = "${issue_subs#*/}" ] && issue_close="true" ;;
    esac
    [ "${prog_closing_map[$issue_num]:-false}" = "true" ] && issue_close="true"
    echo "ISSUE_${issue_num}_CLOSE_CANDIDATE=${issue_close}"
  done
fi

# --- PRs section ----------------------------------------------------------
if [ "$triage_type" != "issues" ]; then
  prs_json=$(fetch_prs)
  if ! echo "$prs_json" | jq empty 2>/dev/null; then
    prs_json="[]"
    triage_issues_list="${triage_issues_list}  - SEVERITY=WARN TYPE=invalid_prs_json MSG=PR fetch returned non-JSON\n"
    triage_issue_count=$((triage_issue_count + 1))
    [ "$triage_status" = "OK" ] && triage_status="WARN"
  fi
  prs_fetched=$(echo "$prs_json" | jq 'length')
  prs_open_total=$(count_of "$counts_json" pullRequests)
  prs_truncated=$(truncation_state "$prs_fetched" "$prs_open_total")
  note_truncation "$prs_truncated"
  echo "PRS_FETCHED=${prs_fetched}"
  echo "PRS_TOTAL=${prs_open_total}"
  echo "PRS_TRUNCATED=${prs_truncated}"

  # Per-PR metadata runs in its OWN jq pass keyed by PR number, so a multi-line
  # bot PR body (embedded tabs/newlines) can never shift the categorization enum
  # columns. Packing `body` into the enum @tsv row used to do exactly that —
  # every column slid right, WORST_CHECK held the whole body, and every PR fell
  # through to `uncategorized` (issue #1627). This pass emits three TSV-safe
  # fields: closing refs (single `#NNN` tokens), a bot-author flag, and the
  # failing-check signature (sorted FAILURE check names joined by `|`, no tabs).
  #
  # Bot detection mirrors git-pr-feedback's automation-author convention (#1420):
  # author.is_bot, the well-known automation logins, or a *[bot]/*-bot login.
  # The signature feeds the systematic-failure roll-up below (issue #1628).
  # Empty fields are emitted as the literal `none` because `read` with a
  # tab IFS collapses consecutive tabs (tab is IFS-whitespace) — an empty
  # closes/signature field would otherwise shift every later column. The
  # script translates `none` back to empty after the split.
  declare -A pr_closes_map=()
  declare -A pr_isbot_map=()
  declare -A pr_sig_map=()
  while IFS=$'\t' read -r meta_num meta_closes meta_isbot meta_sig; do
    [ -z "$meta_num" ] && continue
    pr_closes_map["$meta_num"]="$meta_closes"
    pr_isbot_map["$meta_num"]="$meta_isbot"
    [ "$meta_sig" = "none" ] && meta_sig=""
    pr_sig_map["$meta_num"]="$meta_sig"
  done < <(echo "$prs_json" | jq -r '
    ["dependabot[bot]","renovate[bot]","release-please[bot]","github-actions[bot]","fvh-buildbot"] as $automation
    | .[]
    | (.author.login // "") as $login
    | [
        (.number|tostring),
        (([ (.body // "") | scan("(?i)(?:closes|fixes|resolves)[[:space:]]+#[0-9]+") ]
          | map(sub("^[^#]*";"")) | unique | join(",")) | if . == "" then "none" else . end),
        (( (.author.is_bot // false)
          or (($automation | index($login)) != null)
          or ($login | test("(?i)(\\[bot\\]$|-bot$)")) ) | tostring),
        (([ .statusCheckRollup[]? | select(.conclusion == "FAILURE") | (.name // .context // "check") ]
          | unique | join("|")) | if . == "" then "none" else . end)
      ] | @tsv' 2>/dev/null)

  # Accumulator for the systematic-failure roll-up (#1628): failing-check
  # signature → comma-joined list of the bot-authored needs-fix PRs sharing it.
  declare -A sys_prs=()

  # Per-PR: pull the enum fields + worst CI conclusion, then categorize purely.
  # worst conclusion: FAILURE > CANCELLED > SUCCESS; null/empty → none.
  # reviewDecision is normalized so empty-string ("" — returned by bot PRs with
  # no review requested) is treated the same as null, since jq `//` only catches
  # null/false and would otherwise let the awaiting-review branch misfire (#1627).
  while IFS=$'\t' read -r pr_num pr_updated pr_draft pr_mergeable pr_state pr_review pr_worst; do
    [ -z "$pr_num" ] && continue
    pr_age=$(age_days "$pr_updated")
    pr_category=$(categorize_pr "$pr_draft" "$pr_mergeable" "$pr_state" "$pr_review" "$pr_worst" "$pr_age")
    echo "PR_${pr_num}_AGE_DAYS=${pr_age}"
    echo "PR_${pr_num}_DRAFT=${pr_draft}"
    echo "PR_${pr_num}_MERGEABLE=${pr_mergeable}"
    echo "PR_${pr_num}_MERGE_STATE=${pr_state}"
    echo "PR_${pr_num}_REVIEW=${pr_review}"
    echo "PR_${pr_num}_WORST_CHECK=${pr_worst}"
    echo "PR_${pr_num}_CATEGORY=${pr_category}"
    pr_closes="${pr_closes_map[$pr_num]:-}"
    echo "PR_${pr_num}_CLOSES=${pr_closes:-none}"
    # Group bot-authored needs-fix PRs by their failing-check signature (#1628).
    if [ "$pr_category" = "needs-fix" ] && [ "${pr_isbot_map[$pr_num]:-false}" = "true" ]; then
      pr_sig="${pr_sig_map[$pr_num]:-}"
      if [ -n "$pr_sig" ]; then
        sys_prs["$pr_sig"]="${sys_prs[$pr_sig]:+${sys_prs[$pr_sig]},}#${pr_num}"
      fi
    fi
  done < <(echo "$prs_json" | jq -r '
    def worst(rollup):
      ([rollup[]?.conclusion]) as $c
      | if ($c | any(. == "FAILURE")) then "FAILURE"
        elif ($c | any(. == "CANCELLED")) then "CANCELLED"
        elif ($c | any(. == "SUCCESS")) then "SUCCESS"
        else "none" end;
    .[] | [
      (.number|tostring),
      .updatedAt,
      (.isDraft|tostring),
      (.mergeable // "UNKNOWN"),
      (.mergeStateStatus // "UNKNOWN"),
      (if (.reviewDecision // "") == "" then "null" else .reviewDecision end),
      worst(.statusCheckRollup // [])
    ] | @tsv' 2>/dev/null)

  # Systematic-failure roll-up (#1628): when ≥2 bot-authored PRs share an
  # identical failing-check signature, they almost always have ONE shared root
  # cause (e.g. Dependabot can't update bun.lock → every npm-bump PR fails the
  # frozen-lockfile step before lint/typecheck/tests even run). Surface a single
  # grouped hint so triage diagnoses the shared cause once — and reads
  # `--log-failed` for the install step — instead of treating N PRs as N
  # independent code defects. Iterate keys in sorted order for deterministic
  # output; only signatures shared by ≥2 PRs are emitted.
  sys_idx=0
  if [ "${#sys_prs[@]}" -gt 0 ]; then
    while IFS= read -r sys_sig; do
      [ -z "$sys_sig" ] && continue
      sys_csv="${sys_prs[$sys_sig]}"
      sys_commas=$(printf '%s' "$sys_csv" | tr -cd ',' | wc -c)
      [ $((sys_commas + 1)) -ge 2 ] || continue
      sys_idx=$((sys_idx + 1))
      echo "SYSTEMATIC_FAILURE_${sys_idx}_SIGNATURE=${sys_sig}"
      echo "SYSTEMATIC_FAILURE_${sys_idx}_PRS=${sys_csv}"
    done < <(printf '%s\n' "${!sys_prs[@]}" | sort)
  fi
  echo "SYSTEMATIC_FAILURE_COUNT=${sys_idx}"
fi

# REST fallback roll-up (#3362), emitted only when GraphQL was refused, so the
# GraphQL path's output is unchanged.
if rest_mode; then
  echo "GRAPHQL_BLOCKED=true"
  if [ "$triage_type" != "prs" ]; then echo "REST_FALLBACK_UNKNOWN=MERGED_PRS"; else echo "REST_FALLBACK_UNKNOWN=none"; fi
  if [ "$triage_type" != "issues" ]; then echo "REST_FALLBACK_APPROXIMATED=REVIEW"; else echo "REST_FALLBACK_APPROXIMATED=none"; fi
fi

# Coverage roll-up (#2714). A truncated batch is a caveat on what was triaged,
# not a collector fault, so it never moves STATUS.
echo "TRUNCATED=${truncated_rollup}"
echo "STATUS=${triage_status}"
echo "ISSUE_COUNT=${triage_issue_count}"
if [ -n "$triage_issues_list" ]; then
  echo "ISSUES:"
  echo -e "$triage_issues_list" | sed '/^$/d'
fi
echo "=== END GIT TRIAGE ==="

[ "$triage_status" = "ERROR" ] && exit 1
exit 0
