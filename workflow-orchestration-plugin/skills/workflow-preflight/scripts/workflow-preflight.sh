#!/usr/bin/env bash
# Workflow Preflight
# Deterministic pre-work validation: fetch remote, compute ahead/behind counts,
# look up an existing PR / issue / branch for the target, detect merge conflicts
# via merge-tree dry-run, inspect uncommitted + stash state, and apply the fixed
# recommendation decision tree over those booleans.
#
# The judgment-bearing step ("Continue on existing PR or start fresh?" — an
# AskUserQuestion handoff) stays in the skill; this script only emits the
# deterministic state the skill needs to decide.
#
# Usage: bash workflow-preflight.sh --home-dir <path> --project-dir <path> \
#          [--issue <number>]
#
# Fixture seam (offline testing): every network/gh probe is injectable so the
# test suite runs against a planted git repo + canned gh JSON with no network.
#   WORKFLOW_PREFLIGHT_NO_FETCH=1   skip `git fetch` (no network)
#   WORKFLOW_PREFLIGHT_FIXTURE=DIR  read canned gh JSON from DIR instead of gh:
#                                     DIR/issue.json     <- gh issue view ...
#                                     DIR/pr-search.json <- gh pr list --search ...
#                                   Absence of a file == empty result for that probe.

set -uo pipefail

home_dir=""
project_dir=""
preflight_issue=""

while [ $# -gt 0 ]; do
  case "$1" in
    --home-dir) home_dir="$2"; shift 2 ;;
    --project-dir) project_dir="$2"; shift 2 ;;
    --issue) preflight_issue="$2"; shift 2 ;;
    *) shift ;;
  esac
done

: "${home_dir:=$HOME}"
: "${project_dir:=$(pwd)}"

preflight_fixture="${WORKFLOW_PREFLIGHT_FIXTURE:-}"
preflight_no_fetch="${WORKFLOW_PREFLIGHT_NO_FETCH:-}"

echo "=== WORKFLOW PREFLIGHT ==="

issue_count=0
check_status="OK"
issues_list=""

add_issue() {
  # $1 severity, $2 type, $3 message
  issues_list="${issues_list}  - SEVERITY=${1} TYPE=${2} MSG=${3}\n"
  issue_count=$((issue_count + 1))
  if [ "$1" = "ERROR" ]; then
    check_status="ERROR"
  elif [ "$1" = "WARN" ] && [ "$check_status" = "OK" ]; then
    check_status="WARN"
  fi
}

# jq drives the gh JSON parsing; without it the existing-work lookup is unsafe.
if ! command -v jq >/dev/null 2>&1; then
  echo "JQ_AVAILABLE=false"
  echo "STATUS=ERROR"
  echo "ISSUE_COUNT=1"
  echo "ISSUES:"
  echo "  - SEVERITY=ERROR TYPE=missing_tool MSG=jq is required but not installed"
  echo "=== END WORKFLOW PREFLIGHT ==="
  exit 1
fi
echo "JQ_AVAILABLE=true"

# Resolve the git working tree from the project dir. Everything downstream runs
# through `git -C "$project_dir"` so a moved cwd cannot leak operations.
git_dir="$(git -C "$project_dir" rev-parse --show-toplevel 2>/dev/null || true)"
if [ -z "$git_dir" ]; then
  echo "GIT_REPO=false"
  echo "STATUS=ERROR"
  echo "ISSUE_COUNT=1"
  echo "ISSUES:"
  echo "  - SEVERITY=ERROR TYPE=not_a_repo MSG=${project_dir} is not inside a git repository"
  echo "=== END WORKFLOW PREFLIGHT ==="
  exit 1
fi
echo "GIT_REPO=true"
git_cmd() { git -C "$git_dir" "$@"; }

current_branch="$(git_cmd branch --show-current 2>/dev/null || true)"
echo "CURRENT_BRANCH=${current_branch:-DETACHED}"

# --- Step 1: Fetch latest remote state (injectable seam) ---------------------
if [ -n "$preflight_no_fetch" ]; then
  echo "FETCH=SKIPPED"
else
  if git_cmd fetch origin --prune >/dev/null 2>&1; then
    echo "FETCH=OK"
  else
    echo "FETCH=FAILED"
    add_issue WARN fetch_failed "git fetch origin failed; ahead/behind may be stale"
  fi
fi

# --- Resolve the upstream base branch (main or master) -----------------------
base_ref=""
for candidate in origin/main origin/master; do
  if git_cmd rev-parse --verify --quiet "$candidate" >/dev/null 2>&1; then
    base_ref="$candidate"
    break
  fi
done
echo "BASE_REF=${base_ref:-NONE}"

# --- Step 3: ahead/behind counts vs base ------------------------------------
ahead=0
behind=0
if [ -n "$base_ref" ]; then
  counts="$(git_cmd rev-list --left-right --count "${base_ref}...HEAD" 2>/dev/null || true)"
  if [ -n "$counts" ]; then
    behind="$(printf '%s\n' "$counts" | awk '{print $1}')"
    ahead="$(printf '%s\n' "$counts" | awk '{print $2}')"
  fi
fi
echo "COMMITS_AHEAD=${ahead:-0}"
echo "COMMITS_BEHIND=${behind:-0}"
if [ "${behind:-0}" -gt 0 ] 2>/dev/null; then
  add_issue WARN behind_remote "HEAD is ${behind} commits behind ${base_ref}; rebase recommended"
fi

# --- Uncommitted + stash state ----------------------------------------------
porcelain="$(git_cmd status --porcelain 2>/dev/null || true)"
if [ -n "$porcelain" ]; then
  uncommitted_count="$(printf '%s\n' "$porcelain" | grep -c .)"
  echo "UNCOMMITTED_CHANGES=true"
  echo "UNCOMMITTED_COUNT=${uncommitted_count}"
  add_issue WARN dirty_tree "${uncommitted_count} uncommitted changes; commit or stash before branching"
else
  echo "UNCOMMITTED_CHANGES=false"
  echo "UNCOMMITTED_COUNT=0"
fi

stash_list="$(git_cmd stash list 2>/dev/null || true)"
if [ -n "$stash_list" ]; then
  stash_count="$(printf '%s\n' "$stash_list" | grep -c .)"
else
  stash_count=0
fi
echo "STASH_COUNT=${stash_count}"

# --- Step 4: merge-tree dry-run conflict detection --------------------------
conflicts_detected=false
if [ -n "$base_ref" ]; then
  merge_base="$(git_cmd merge-base HEAD "$base_ref" 2>/dev/null || true)"
  if [ -n "$merge_base" ]; then
    merge_out="$(git_cmd merge-tree "$merge_base" HEAD "$base_ref" 2>/dev/null || true)"
    # merge-tree (the trivial three-arg form) emits "changed in both" + "<<<<<<<"
    # conflict markers when a path conflicts.
    if printf '%s\n' "$merge_out" | grep -q '^<<<<<<<\|changed in both'; then
      conflicts_detected=true
    fi
  fi
fi
echo "CONFLICTS_DETECTED=${conflicts_detected}"
if [ "$conflicts_detected" = true ]; then
  add_issue WARN conflicts "Merge conflicts with ${base_ref} detected; resolve before proceeding"
fi

# --- Step 2: existing-work lookup (issue + PR + branch) ---------------------
existing_pr_state="NONE"
existing_pr_number=""
existing_pr_branch=""
issue_state="NONE"
matching_branches=""

# gh probes go through the fixture seam: when WORKFLOW_PREFLIGHT_FIXTURE is set,
# read canned JSON from files; otherwise call gh live.
fixture_or_gh() {
  # $1 = fixture filename, rest = gh argv
  local fname="$1"; shift
  if [ -n "$preflight_fixture" ]; then
    if [ -f "${preflight_fixture}/${fname}" ]; then
      cat "${preflight_fixture}/${fname}"
    else
      printf ''
    fi
    return 0
  fi
  command -v gh >/dev/null 2>&1 || { printf ''; return 0; }
  gh "$@" 2>/dev/null || printf ''
}

if [ -n "$preflight_issue" ]; then
  echo "TARGET_ISSUE=${preflight_issue}"

  issue_json="$(fixture_or_gh issue.json issue view "$preflight_issue" --json number,title,state,labels)"
  if [ -n "$issue_json" ]; then
    issue_state="$(printf '%s' "$issue_json" | jq -r '.state // "NONE"' 2>/dev/null || echo NONE)"
  fi
  echo "ISSUE_STATE=${issue_state}"

  pr_json="$(fixture_or_gh pr-search.json pr list --search "fixes #${preflight_issue} OR closes #${preflight_issue} OR resolves #${preflight_issue}" --json number,title,state,headRefName)"
  if [ -n "$pr_json" ]; then
    # First MERGED match wins; otherwise first OPEN match.
    existing_pr_state="$(printf '%s' "$pr_json" | jq -r '
      ([.[] | select(.state == "MERGED")] | first) as $m
      | ([.[] | select(.state == "OPEN")] | first) as $o
      | if $m then "MERGED" elif $o then "OPEN" else "NONE" end' 2>/dev/null || echo NONE)"
    existing_pr_number="$(printf '%s' "$pr_json" | jq -r '
      ([.[] | select(.state == "MERGED")] | first) as $m
      | ([.[] | select(.state == "OPEN")] | first) as $o
      | ($m // $o // {}) | .number // ""' 2>/dev/null || echo "")"
    existing_pr_branch="$(printf '%s' "$pr_json" | jq -r '
      ([.[] | select(.state == "MERGED")] | first) as $m
      | ([.[] | select(.state == "OPEN")] | first) as $o
      | ($m // $o // {}) | .headRefName // ""' 2>/dev/null || echo "")"
  fi

  matching_branches="$(git_cmd branch -a --list "*issue-${preflight_issue}*" --list "*fix/${preflight_issue}*" --list "*feat/${preflight_issue}*" 2>/dev/null | sed 's/^[* ] *//' | grep -c . || echo 0)"
else
  echo "TARGET_ISSUE=NONE"
  echo "ISSUE_STATE=NONE"
  matching_branches=0
fi

echo "EXISTING_PR_STATE=${existing_pr_state}"
echo "EXISTING_PR_NUMBER=${existing_pr_number}"
echo "EXISTING_PR_BRANCH=${existing_pr_branch}"
echo "MATCHING_BRANCHES=${matching_branches}"

if [ "$existing_pr_state" = "MERGED" ]; then
  add_issue WARN already_addressed "Issue already addressed by merged PR #${existing_pr_number}; stop before duplicating"
elif [ "$existing_pr_state" = "OPEN" ]; then
  add_issue WARN existing_pr "Open PR #${existing_pr_number} (${existing_pr_branch}) already addresses this; review before duplicating"
fi

# --- Fixed recommendation decision tree over the booleans -------------------
# Precedence: merged PR > conflicts > open PR > behind/dirty > clean.
recommendation=""
if [ "$existing_pr_state" = "MERGED" ]; then
  recommendation="STOP: merged PR #${existing_pr_number} already addresses this issue"
elif [ "$conflicts_detected" = true ]; then
  recommendation="Resolve conflicts with ${base_ref} before proceeding"
elif [ "$existing_pr_state" = "OPEN" ]; then
  recommendation="Open PR #${existing_pr_number} exists - continue on that branch or start fresh (ask user)"
elif [ "${behind:-0}" -gt 0 ] 2>/dev/null; then
  recommendation="Rebase onto ${base_ref} before starting work (${behind} behind)"
elif [ -n "$porcelain" ]; then
  recommendation="Commit or stash uncommitted changes before branching"
else
  recommendation="Ready to proceed"
fi
echo "RECOMMENDATION=${recommendation}"

echo "STATUS=${check_status}"
echo "ISSUE_COUNT=${issue_count}"
if [ -n "$issues_list" ]; then
  echo "ISSUES:"
  echo -e "$issues_list" | sed '/^$/d'
fi
echo "=== END WORKFLOW PREFLIGHT ==="

[ "$check_status" = "ERROR" ] && exit 1
exit 0
