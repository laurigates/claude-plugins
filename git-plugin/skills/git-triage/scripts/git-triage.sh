#!/usr/bin/env bash
# git-triage data-gathering (issue #1552).
# DATA-ONLY: fetches issue/PR JSON, computes age, categorizes PRs via a pure
# first-match table over enum fields, and extracts closing keywords. Performs
# NO mutations. Issue-categorization judgment stays with the model.
#
# Network seam: every `gh` call is routed through an injectable fixture so tests
# run fully offline. Set GIT_TRIAGE_ISSUES_FIXTURE / GIT_TRIAGE_PRS_FIXTURE to
# canned gh JSON arrays, or GIT_TRIAGE_NO_FETCH=1 to skip live fetches entirely.
#
# Usage: bash git-triage.sh [--home-dir <path>] [--project-dir <path>]
#          [--repo owner/name] [--type issues|prs|both] [--batch N]
#          [--days-stale-issue N] [--days-stale-pr N]
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
  local repo_flag=()
  [ -n "$repo" ] && repo_flag=(--repo "$repo")
  gh issue list "${repo_flag[@]}" --state open --limit "$batch" \
    --json number,title,body,labels,createdAt,updatedAt,comments,assignees,author 2>/dev/null || echo "[]"
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
  local repo_flag=()
  [ -n "$repo" ] && repo_flag=(--repo "$repo")
  gh pr list "${repo_flag[@]}" --state open --limit "$batch" \
    --json number,title,createdAt,updatedAt,mergeable,mergeStateStatus,reviewDecision,statusCheckRollup,isDraft,baseRefName,headRefName,author,labels,body 2>/dev/null || echo "[]"
}

# --- Issues section -------------------------------------------------------
if [ "$triage_type" != "prs" ]; then
  issues_json=$(fetch_issues)
  if ! echo "$issues_json" | jq empty 2>/dev/null; then
    issues_json="[]"
    triage_issues_list="${triage_issues_list}  - SEVERITY=WARN TYPE=invalid_issues_json MSG=issue fetch returned non-JSON\n"
    triage_issue_count=$((triage_issue_count + 1))
    [ "$triage_status" = "OK" ] && triage_status="WARN"
  fi
  issue_total=$(echo "$issues_json" | jq 'length')
  echo "ISSUES_FETCHED=${issue_total}"

  # Per-issue: number, age, referenced PR numbers (closing-keyword candidates).
  echo "$issues_json" | jq -r '.[] | [
    (.number|tostring),
    .updatedAt,
    ((.title + " " + (.body // "")) | [scan("#[0-9]+")] | unique | join(",")),
    (.comments | length | tostring)
  ] | @tsv' 2>/dev/null | while IFS=$'\t' read -r issue_num issue_updated issue_refs issue_comments; do
    issue_age=$(age_days "$issue_updated")
    echo "ISSUE_${issue_num}_AGE_DAYS=${issue_age}"
    echo "ISSUE_${issue_num}_REFS=${issue_refs:-none}"
    echo "ISSUE_${issue_num}_COMMENTS=${issue_comments}"
    if [ "$issue_age" -gt "$days_stale_issue" ] 2>/dev/null; then
      echo "ISSUE_${issue_num}_STALE_CANDIDATE=true"
    else
      echo "ISSUE_${issue_num}_STALE_CANDIDATE=false"
    fi
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
  pr_total=$(echo "$prs_json" | jq 'length')
  echo "PRS_FETCHED=${pr_total}"

  # Per-PR: pull the enum fields + worst CI conclusion, then categorize purely.
  # worst conclusion: FAILURE > CANCELLED > SUCCESS; null/empty → none.
  while IFS=$'\t' read -r pr_num pr_updated pr_draft pr_mergeable pr_state pr_review pr_worst pr_body; do
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
    # Closing-keyword extraction from the PR body (audit candidates).
    pr_closes=$(printf '%s' "$pr_body" | grep -oiE '(closes|fixes|resolves)[[:space:]]+#[0-9]+' | grep -oE '#[0-9]+' | sort -u | tr '\n' ',' | sed 's/,$//')
    echo "PR_${pr_num}_CLOSES=${pr_closes:-none}"
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
      (.reviewDecision // "null"),
      worst(.statusCheckRollup // []),
      (.body // "")
    ] | @tsv' 2>/dev/null)
fi

echo "STATUS=${triage_status}"
echo "ISSUE_COUNT=${triage_issue_count}"
if [ -n "$triage_issues_list" ]; then
  echo "ISSUES:"
  echo -e "$triage_issues_list" | sed '/^$/d'
fi
echo "=== END GIT TRIAGE ==="

[ "$triage_status" = "ERROR" ] && exit 1
exit 0
