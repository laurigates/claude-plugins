#!/usr/bin/env bash
# git-pr data-gathering (issue #1552).
# DATA-ONLY: detects PR readiness (fetch + ahead-count + existing-PR probe),
# audits closing keywords in a PR body, and scans for stacked dependents.
# Performs NO mutations and writes NO PR body — PR-body authoring stays with
# the model.
#
# Seams (fully offline tests):
#   GIT_PR_NO_FETCH=1            skip `git fetch`
#   GIT_PR_EXISTING_PR_FIXTURE  canned `gh pr view --json number,state` JSON
#   GIT_PR_DEPENDENTS_FIXTURE   canned `gh pr list --base <head>` JSON array
#   --body-file <path>          audit closing keywords in this body instead of gh
#   --base <ref>                base ref for ahead-count (default origin/main)
#
# Usage: bash git-pr.sh [--home-dir <path>] [--project-dir <path>]
#          [--base <ref>] [--body-file <path>]
#
# gh --json fields: PR merge/open state is `state` (OPEN/CLOSED/MERGED), never a
# `merged` field. CI status would live in `statusCheckRollup[]` (not used here).

set -uo pipefail

home_dir=""
project_dir=""
base_ref="origin/main"
body_file=""

while [ $# -gt 0 ]; do
  case "$1" in
    --home-dir) home_dir="$2"; shift 2 ;;
    --project-dir) project_dir="$2"; shift 2 ;;
    --base) base_ref="$2"; shift 2 ;;
    --body-file) body_file="$2"; shift 2 ;;
    *) shift ;;
  esac
done

: "${home_dir:=$HOME}"
: "${project_dir:=$(pwd)}"

repo_dir="$project_dir"

echo "=== GIT PR ==="

gitpr_issues_list=""
gitpr_issue_count=0
gitpr_status="OK"

if ! command -v jq >/dev/null 2>&1; then
  echo "JQ_AVAILABLE=false"
  echo "STATUS=ERROR"
  echo "ISSUE_COUNT=1"
  echo "ISSUES:"
  echo "  - SEVERITY=ERROR TYPE=missing_tool MSG=jq is required but not installed"
  echo "=== END GIT PR ==="
  exit 1
fi
echo "JQ_AVAILABLE=true"

if ! git -C "$repo_dir" rev-parse --git-dir >/dev/null 2>&1; then
  echo "GIT_REPO=false"
  echo "STATUS=ERROR"
  echo "ISSUE_COUNT=1"
  echo "ISSUES:"
  echo "  - SEVERITY=ERROR TYPE=not_a_repo MSG=${repo_dir} is not a git repository"
  echo "=== END GIT PR ==="
  exit 1
fi
echo "GIT_REPO=true"

current_branch=$(git -C "$repo_dir" branch --show-current 2>/dev/null || echo "")
echo "CURRENT_BRANCH=${current_branch:-detached}"

# --- Readiness: fetch + ahead-count --------------------------------------
if [ "${GIT_PR_NO_FETCH:-}" != "1" ]; then
  git -C "$repo_dir" fetch origin "${base_ref#origin/}" >/dev/null 2>&1 || true
  echo "FETCHED=true"
else
  echo "FETCHED=false"
fi

ahead=$(git -C "$repo_dir" rev-list --count "${base_ref}..HEAD" 2>/dev/null || echo "0")
echo "AHEAD_COUNT=${ahead}"
if [ "$ahead" = "0" ]; then
  echo "PR_READY=false"
  gitpr_issues_list="${gitpr_issues_list}  - SEVERITY=WARN TYPE=no_commits MSG=no commits ahead of ${base_ref}; nothing to PR\n"
  gitpr_issue_count=$((gitpr_issue_count + 1))
  [ "$gitpr_status" = "OK" ] && gitpr_status="WARN"
else
  echo "PR_READY=true"
fi

# --- Existing-PR probe ----------------------------------------------------
probe_existing_pr() {
  if [ -n "${GIT_PR_EXISTING_PR_FIXTURE:-}" ]; then
    cat "$GIT_PR_EXISTING_PR_FIXTURE"
    return
  fi
  gh pr view --json number,state 2>/dev/null || echo "null"
}
existing_pr=$(probe_existing_pr)
if echo "$existing_pr" | jq -e 'type == "object" and has("number")' >/dev/null 2>&1; then
  existing_num=$(echo "$existing_pr" | jq -r '.number')
  existing_state=$(echo "$existing_pr" | jq -r '.state')
  echo "EXISTING_PR=${existing_num}"
  echo "EXISTING_PR_STATE=${existing_state}"
else
  echo "EXISTING_PR=none"
fi

# --- Stacked-PR dependents scan ------------------------------------------
scan_dependents() {
  if [ -n "${GIT_PR_DEPENDENTS_FIXTURE:-}" ]; then
    cat "$GIT_PR_DEPENDENTS_FIXTURE"
    return
  fi
  [ -z "$current_branch" ] && { echo "[]"; return; }
  gh pr list --base "$current_branch" --state open --json number,title,headRefName 2>/dev/null || echo "[]"
}
dependents=$(scan_dependents)
dep_count=$(echo "$dependents" | jq 'length' 2>/dev/null || echo "0")
echo "DEPENDENT_COUNT=${dep_count}"
if [ "$dep_count" -gt 0 ] 2>/dev/null; then
  echo "STACK_PARENT=true"
  echo "$dependents" | jq -r '.[] | "DEPENDENT_PR=" + (.number|tostring) + " HEAD=" + .headRefName' 2>/dev/null
else
  echo "STACK_PARENT=false"
fi

# --- Closing-keyword audit ------------------------------------------------
# Audits a PR body for issues referenced by number but lacking a closing keyword.
# Body source: --body-file if given (offline), else fetched from the open PR.
audit_body() {
  if [ -n "$body_file" ] && [ -f "$body_file" ]; then
    cat "$body_file"
    return
  fi
  gh pr view --json body --jq .body 2>/dev/null || echo ""
}
pr_body=$(audit_body)
if [ -n "$pr_body" ]; then
  referenced=$(printf '%s' "$pr_body" | grep -oE '#[0-9]+' | sort -u)
  closing=$(printf '%s' "$pr_body" | grep -oiE '(closes|fixes|resolves)[[:space:]]+#[0-9]+' | grep -oE '#[0-9]+' | sort -u)
  missing=$(comm -23 <(echo "$referenced") <(echo "$closing") 2>/dev/null | grep -E '#[0-9]+' || true)
  ref_list=$(echo "$referenced" | grep -E '#' | tr '\n' ',' | sed 's/,$//')
  close_list=$(echo "$closing" | grep -E '#' | tr '\n' ',' | sed 's/,$//')
  miss_list=$(echo "$missing" | grep -E '#' | tr '\n' ',' | sed 's/,$//')
  echo "BODY_REFERENCED=${ref_list:-none}"
  echo "BODY_CLOSING=${close_list:-none}"
  echo "BODY_NOT_AUTOCLOSING=${miss_list:-none}"
  if [ -n "$miss_list" ]; then
    gitpr_issues_list="${gitpr_issues_list}  - SEVERITY=WARN TYPE=missing_closing_keyword MSG=referenced but not auto-closing: ${miss_list}\n"
    gitpr_issue_count=$((gitpr_issue_count + 1))
    [ "$gitpr_status" = "OK" ] && gitpr_status="WARN"
  fi
else
  echo "BODY_REFERENCED=none"
fi

echo "STATUS=${gitpr_status}"
echo "ISSUE_COUNT=${gitpr_issue_count}"
if [ -n "$gitpr_issues_list" ]; then
  echo "ISSUES:"
  echo -e "$gitpr_issues_list" | sed '/^$/d'
fi
echo "=== END GIT PR ==="

[ "$gitpr_status" = "ERROR" ] && exit 1
exit 0
