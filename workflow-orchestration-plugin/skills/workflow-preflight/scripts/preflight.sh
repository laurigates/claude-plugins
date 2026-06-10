#!/usr/bin/env bash
# Preflight state gatherer for /workflow:preflight (ADR-0016 extraction, #1558).
#
# Collects the deterministic git/gh state the skill used to gather inline —
# remote freshness, ahead/behind counts, uncommitted + stash state, merge
# conflict detection, existing-PR/issue/branch lookup — and emits it as a
# structured KEY=VALUE block (see .claude/rules/structured-script-output.md).
#
# The skill keeps every judgment step: deciding whether an open PR means
# "continue here or start fresh" (an AskUserQuestion handoff), and authoring
# the final summary. This script only reports facts and a fixed
# recommendation derived from those facts.
#
# Usage:
#   bash preflight.sh [--project-dir <path>] [--base <ref>] [--issue <n>]
#                     [--branch <name>] [--no-fetch]
#
# Exit codes: 0 when state was gathered (STATUS=OK or WARN), 1 on ERROR
# (not a git repository). Network/gh failures degrade gracefully — they never
# fail the run.

set -uo pipefail

project_dir=""
base_ref=""
issue_num=""
branch_name=""
do_fetch=true

while [ $# -gt 0 ]; do
  case "$1" in
    --project-dir) project_dir="$2"; shift 2 ;;
    --base) base_ref="$2"; shift 2 ;;
    --issue) issue_num="$2"; shift 2 ;;
    --branch) branch_name="$2"; shift 2 ;;
    --no-fetch) do_fetch=false; shift ;;
    *) shift ;;
  esac
done

: "${project_dir:=$(pwd)}"

git_in() { git -C "$project_dir" "$@"; }

echo "=== PREFLIGHT ==="

# --- Repository guard -------------------------------------------------------
repo_root=$(git_in rev-parse --show-toplevel 2>/dev/null || true)
if [ -z "$repo_root" ]; then
  echo "STATUS=ERROR"
  echo "ISSUE_COUNT=1"
  echo "ISSUES:"
  echo "  - SEVERITY=ERROR TYPE=not_a_repo MSG=${project_dir} is not inside a git repository"
  echo "=== END PREFLIGHT ==="
  exit 1
fi
echo "REPO_ROOT=${repo_root}"

current_branch=$(git_in branch --show-current 2>/dev/null || true)
echo "CURRENT_BRANCH=${current_branch:-DETACHED}"

# --- Step 1: fetch latest remote state --------------------------------------
fetch_state="skipped"
if [ "$do_fetch" = true ]; then
  if git_in remote get-url origin >/dev/null 2>&1; then
    if git_in fetch origin --prune >/dev/null 2>&1; then
      fetch_state="ok"
    else
      fetch_state="failed"
    fi
  else
    fetch_state="no-remote"
  fi
fi
echo "FETCH=${fetch_state}"

# --- Resolve the base ref to compare against --------------------------------
if [ -z "$base_ref" ]; then
  for candidate in origin/main origin/master main master; do
    if git_in rev-parse --verify --quiet "$candidate" >/dev/null 2>&1; then
      base_ref="$candidate"
      break
    fi
  done
fi

base_resolved=false
if [ -n "$base_ref" ] && git_in rev-parse --verify --quiet "$base_ref" >/dev/null 2>&1; then
  base_resolved=true
fi
echo "BASE_REF=${base_ref:-none}"
echo "BASE_RESOLVED=${base_resolved}"

# --- Step 3: branch divergence (ahead / behind) -----------------------------
ahead=0
behind=0
if [ "$base_resolved" = true ]; then
  # left = behind (in base, not HEAD); right = ahead (in HEAD, not base)
  counts=$(git_in rev-list --left-right --count "${base_ref}...HEAD" 2>/dev/null || echo "0	0")
  behind=$(printf '%s\n' "$counts" | awk '{print $1+0}')
  ahead=$(printf '%s\n' "$counts" | awk '{print $2+0}')
fi
echo "AHEAD=${ahead}"
echo "BEHIND=${behind}"

# --- Uncommitted + stash state ----------------------------------------------
uncommitted=$(git_in status --porcelain 2>/dev/null | grep -c . || true)
uncommitted=${uncommitted:-0}
echo "UNCOMMITTED=${uncommitted}"

stash_count=$(git_in stash list 2>/dev/null | grep -c . || true)
stash_count=${stash_count:-0}
echo "STASH_COUNT=${stash_count}"

# --- Step 4: dry-run merge conflict detection -------------------------------
conflicts="none"
conflict_files=""
if [ "$base_resolved" = true ]; then
  # git 2.38+ : --write-tree exits non-zero on conflict; --name-only lists the
  # conflicted paths after the tree-OID line. Fall back to the legacy 3-arg
  # form (parsing conflict markers) when --write-tree is unavailable.
  mt_out=$(git_in merge-tree --write-tree --name-only "$base_ref" HEAD 2>/dev/null)
  mt_rc=$?
  if [ "$mt_rc" -gt 1 ]; then
    # --write-tree unsupported (usage error rc=128) — legacy fallback
    merge_base=$(git_in merge-base HEAD "$base_ref" 2>/dev/null || true)
    if [ -n "$merge_base" ] && git_in merge-tree "$merge_base" HEAD "$base_ref" 2>/dev/null | grep -q '^<<<<<<<'; then
      conflicts="detected"
    fi
  elif [ "$mt_rc" -eq 1 ]; then
    conflicts="detected"
    # Drop the first line (the written tree OID); the rest are conflicted paths.
    conflict_files=$(printf '%s\n' "$mt_out" | tail -n +2 | paste -sd, - 2>/dev/null || true)
  fi
fi
echo "CONFLICTS=${conflicts}"
[ -n "$conflict_files" ] && echo "CONFLICT_FILES=${conflict_files}"

# --- Step 2: existing work lookup (gh + git), graceful degradation -----------
gh_available=false
if command -v gh >/dev/null 2>&1 && gh auth status >/dev/null 2>&1; then
  gh_available=true
fi
echo "GH_AVAILABLE=${gh_available}"

issue_state="none"
existing_prs="none"
branch_matches="none"

if [ -n "$issue_num" ]; then
  echo "ISSUE=${issue_num}"
  if [ "$gh_available" = true ]; then
    issue_state=$(gh issue view "$issue_num" --json state --jq '.state' 2>/dev/null || echo "unknown")
    : "${issue_state:=unknown}"

    # PRs that reference the issue via closing keywords.
    prs=$(gh pr list --state all \
      --search "fixes #${issue_num} OR closes #${issue_num} OR resolves #${issue_num}" \
      --json number,state,headRefName \
      --jq '[.[] | "#\(.number):\(.state):\(.headRefName)"] | join(";")' 2>/dev/null || true)
    [ -n "$prs" ] && existing_prs="$prs"
  else
    issue_state="unknown"
  fi

  # Local + remote branches referencing the issue (no network needed).
  matches=$(git_in branch -a --list "*issue-${issue_num}*" "*issue/${issue_num}*" \
    "*fix/${issue_num}*" "*fix/${issue_num}-*" "*feat/${issue_num}*" "*feat/${issue_num}-*" 2>/dev/null \
    | sed 's/^[* ]*//' | grep -v '^$' | paste -sd, - 2>/dev/null || true)
  [ -n "$matches" ] && branch_matches="$matches"
else
  echo "ISSUE=none"
fi
echo "ISSUE_STATE=${issue_state}"
echo "EXISTING_PRS=${existing_prs}"
echo "BRANCH_MATCHES=${branch_matches}"

[ -n "$branch_name" ] && echo "TARGET_BRANCH=${branch_name}"

# --- Step 5: fixed recommendation decision tree -----------------------------
# First match wins, ordered by what blocks starting work most decisively.
# The skill still surfaces every relevant note; this is the headline.
has_merged_pr=false
has_open_pr=false
if [ "$existing_prs" != "none" ]; then
  printf '%s\n' "$existing_prs" | grep -q ':MERGED:' && has_merged_pr=true
  printf '%s\n' "$existing_prs" | grep -q ':OPEN:' && has_open_pr=true
fi

issue_count=0
recommendation="ready"
if [ "$has_merged_pr" = true ]; then
  recommendation="already-addressed"
  issue_count=$((issue_count + 1))
elif [ "$has_open_pr" = true ]; then
  recommendation="existing-pr"
  issue_count=$((issue_count + 1))
elif [ "$conflicts" = "detected" ]; then
  recommendation="resolve-conflicts"
  issue_count=$((issue_count + 1))
elif [ "$uncommitted" -gt 0 ]; then
  recommendation="commit-or-stash"
  issue_count=$((issue_count + 1))
elif [ "$behind" -gt 0 ]; then
  recommendation="rebase"
  issue_count=$((issue_count + 1))
fi
echo "RECOMMENDATION=${recommendation}"

if [ "$issue_count" -gt 0 ]; then
  echo "STATUS=WARN"
else
  echo "STATUS=OK"
fi
echo "ISSUE_COUNT=${issue_count}"
echo "=== END PREFLIGHT ==="
exit 0
