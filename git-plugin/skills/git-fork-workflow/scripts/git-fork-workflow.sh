#!/usr/bin/env bash
# git-fork-workflow data-gathering (issue #1552).
# DATA-ONLY: detects upstream remote, computes ahead/behind via git rev-list,
# and RECOMMENDS a sync strategy via a pure function. Performs NO mutations —
# all destructive execution (reset/rebase/force-push) stays RECOMMEND-only in
# the skill, for the model + user to run.
#
# Repo seam: operates on --project-dir (default cwd) via `git -C`. Tests point
# it at a planted fixture repo with local origin/* and upstream/* refs — fully
# offline, no network. GIT_FORK_NO_FETCH=1 skips live `git fetch`.
#
# Usage: bash git-fork-workflow.sh [--home-dir <path>] [--project-dir <path>]

set -uo pipefail

home_dir=""
project_dir=""

while [ $# -gt 0 ]; do
  case "$1" in
    --home-dir) home_dir="$2"; shift 2 ;;
    --project-dir) project_dir="$2"; shift 2 ;;
    *) shift ;;
  esac
done

: "${home_dir:=$HOME}"
: "${project_dir:=$(pwd)}"

repo_dir="$project_dir"

echo "=== GIT FORK WORKFLOW ==="

fork_issues_list=""
fork_issue_count=0
fork_status="OK"

if ! git -C "$repo_dir" rev-parse --git-dir >/dev/null 2>&1; then
  echo "GIT_REPO=false"
  echo "STATUS=ERROR"
  echo "ISSUE_COUNT=1"
  echo "ISSUES:"
  echo "  - SEVERITY=ERROR TYPE=not_a_repo MSG=${repo_dir} is not a git repository"
  echo "=== END GIT FORK WORKFLOW ==="
  exit 1
fi
echo "GIT_REPO=true"

# --- Upstream detection ---------------------------------------------------
upstream_url=$(git -C "$repo_dir" remote get-url upstream 2>/dev/null || echo "")
if [ -z "$upstream_url" ]; then
  echo "IS_FORK=false"
  echo "UPSTREAM=none"
  echo "STATUS=OK"
  echo "ISSUE_COUNT=0"
  echo "RECOMMENDED_STRATEGY=not-a-fork"
  echo "=== END GIT FORK WORKFLOW ==="
  exit 0
fi
echo "IS_FORK=true"
echo "UPSTREAM=${upstream_url}"

origin_url=$(git -C "$repo_dir" remote get-url origin 2>/dev/null || echo "")
echo "ORIGIN=${origin_url:-none}"

# Optional live fetch (skipped in tests).
if [ "${GIT_FORK_NO_FETCH:-}" != "1" ]; then
  git -C "$repo_dir" fetch origin >/dev/null 2>&1 || true
  git -C "$repo_dir" fetch upstream >/dev/null 2>&1 || true
  echo "FETCHED=true"
else
  echo "FETCHED=false"
fi

# --- Ahead/behind via rev-list -------------------------------------------
# `--left-right --count upstream/main...origin/main` → "<behind>\t<ahead>"
# left = commits on upstream not on fork (fork is behind by this many)
# right = commits on fork not on upstream (fork is ahead by this many)
counts=$(git -C "$repo_dir" rev-list --left-right --count upstream/main...origin/main 2>/dev/null || echo "")
if [ -z "$counts" ]; then
  echo "BEHIND=unknown"
  echo "AHEAD=unknown"
  fork_issues_list="${fork_issues_list}  - SEVERITY=WARN TYPE=missing_refs MSG=upstream/main or origin/main not found; fetch first\n"
  fork_issue_count=$((fork_issue_count + 1))
  [ "$fork_status" = "OK" ] && fork_status="WARN"
  echo "RECOMMENDED_STRATEGY=unknown"
  echo "STATUS=${fork_status}"
  echo "ISSUE_COUNT=${fork_issue_count}"
  echo "ISSUES:"
  echo -e "$fork_issues_list" | sed '/^$/d'
  echo "=== END GIT FORK WORKFLOW ==="
  exit 0
fi
behind=$(echo "$counts" | awk '{print $1}')
ahead=$(echo "$counts" | awk '{print $2}')
echo "BEHIND=${behind}"
echo "AHEAD=${ahead}"

# --- Pure strategy recommendation ----------------------------------------
# Args: behind ahead. Echoes exactly one strategy keyword. No side effects.
#   in-sync       : 0 behind, 0 ahead
#   fast-forward  : behind > 0, 0 ahead (fork clean, upstream moved)
#   rebase        : behind > 0 AND ahead > 0 (diverged, fork work worth keeping)
#   ahead-only    : 0 behind, ahead > 0 (fork ahead, nothing to pull)
recommend_strategy() {
  local s_behind="$1"
  local s_ahead="$2"
  if [ "$s_behind" -eq 0 ] 2>/dev/null && [ "$s_ahead" -eq 0 ] 2>/dev/null; then
    echo "in-sync"; return
  fi
  if [ "$s_ahead" -eq 0 ] 2>/dev/null; then
    echo "fast-forward"; return
  fi
  if [ "$s_behind" -eq 0 ] 2>/dev/null; then
    echo "ahead-only"; return
  fi
  echo "rebase"
}

strategy=$(recommend_strategy "$behind" "$ahead")
echo "RECOMMENDED_STRATEGY=${strategy}"

echo "STATUS=${fork_status}"
echo "ISSUE_COUNT=${fork_issue_count}"
if [ -n "$fork_issues_list" ]; then
  echo "ISSUES:"
  echo -e "$fork_issues_list" | sed '/^$/d'
fi
echo "=== END GIT FORK WORKFLOW ==="

[ "$fork_status" = "ERROR" ] && exit 1
exit 0
