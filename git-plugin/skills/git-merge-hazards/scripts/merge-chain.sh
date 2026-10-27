#!/usr/bin/env bash
# merge-chain.sh — merge an ordered list of PRs one at a time, deterministically.
#
# Usage:
#   merge-chain.sh --repo OWNER/REPO --prs 219,220,227 --review-ts 2026-10-27T08:00:00Z \
#                  [--method squash|merge|rebase] [--timeout SECONDS] [--fetch-dir PATH]
#
#   --repo       Repository the PRs belong to. Every gh call passes -R, which
#                also stops `gh pr merge --delete-branch` from touching a local
#                checkout.
#   --prs        Merge order, comma-separated. A leading '#' is accepted.
#   --review-ts  UTC time verification ended (YYYY-MM-DDTHH:MM:SSZ). Any
#                non-merge commit newer than this is unreviewed (the §6 guard).
#   --method     Merge method (default squash: update-branch adds a merge
#                commit, and a branch with a merge commit squashes).
#   --timeout    Per-PR wall-clock budget for CI to settle (default 1800).
#   --fetch-dir  A clone to `git fetch origin` after each merge.
#   MERGE_CHAIN_POLL_SECONDS  CI poll interval (default 20).
#
# Per PR, in order: read state and author; `gh pr update-branch`; wait until
# every check on the head completes and two consecutive reads agree; read
# mergeStateStatus; refuse any non-merge commit newer than --review-ts; merge
# with `--match-head-commit <full 40-char SHA>` (GitHub rejects a short SHA with
# "Could not coerce value to GitObjectID"); read the state back.
#
# Output: one `=== PR <n> ===` section per PR processed, whose STATUS= is
#   MERGED | SKIPPED | CONFLICT | CI_RED | GUARD_LATE_COMMIT | DENIED | ERROR
# then a `=== MERGE CHAIN ===` summary in the structured-script-output contract
# (STATUS=OK|WARN|ERROR, REASON=, ISSUE_COUNT=, ISSUES:), with REMAINING= naming
# the PRs still to merge, stopped PR first. SKIPPED continues the chain; every
# other non-MERGED status stops it, because later PRs may depend on that one.
# ERROR is the fail-closed catch-all: a read that failed, an unexpected state,
# or an unclassified merge error. An unreadable result never means "clean".
#
# Authorship: the merge happens inside this script, where the PreToolUse
# external-pr-merge-guard hook cannot see the PR number, so the script applies
# the same rule itself (git-plugin:external-pr-trust): merge only PRs authored
# by the authenticated user or a bot. Release-please and Renovate PRs are
# skipped; they have their own merge flows.
#
# Exit: 0 when STATUS is OK or WARN, 1 on ERROR, 2 on a usage error.

set -uo pipefail

MC_REPO=""
MC_PRS=""
MC_REVIEW_TS=""
MC_METHOD="squash"
MC_TIMEOUT=1800
MC_FETCH_DIR=""
MC_POLL="${MERGE_CHAIN_POLL_SECONDS:-20}"
MC_MIN_EMPTY_POLLS=3   # reads with zero checks before "this repo has no CI"
MC_MAX_UPDATES=3       # BEHIND again after CI settled: re-update at most this often

PERMISSION_RE='HTTP 40[13]|[Pp]ermission|not authori[sz]ed|[Rr]esource not accessible|must have (admin|write|push)|[Dd]enied'
HEAD_MOVED_RE='[Hh]ead branch was modified|[Hh]ead (commit|sha)|expected head|match-head'

usage_error() {
  echo "=== MERGE CHAIN ==="
  echo "STATUS=ERROR"
  echo "REASON=usage: $1"
  echo "ISSUE_COUNT=1"
  echo "ISSUES:"
  echo "  - SEVERITY=ERROR TYPE=usage MSG=$1"
  echo "=== END MERGE CHAIN ==="
  exit 2
}

while [ $# -gt 0 ]; do
  case "$1" in
    -h|--help) sed -n '2,45p' "$0"; exit 0 ;;
    --repo|--prs|--review-ts|--method|--timeout|--fetch-dir)
      [ $# -ge 2 ] || usage_error "$1 needs a value" ;;
    *) usage_error "unknown argument $1" ;;
  esac
  case "$1" in
    --repo) MC_REPO="$2" ;;
    --prs) MC_PRS="$2" ;;
    --review-ts) MC_REVIEW_TS="$2" ;;
    --method) MC_METHOD="$2" ;;
    --timeout) MC_TIMEOUT="$2" ;;
    --fetch-dir) MC_FETCH_DIR="$2" ;;
  esac
  shift 2
done

[[ "$MC_REPO" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]] || usage_error "--repo OWNER/REPO is required"
[[ "$MC_REVIEW_TS" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$ ]] ||
  usage_error "--review-ts must be a UTC timestamp like 2026-10-27T08:00:00Z"
[[ "$MC_METHOD" =~ ^(squash|merge|rebase)$ ]] || usage_error "--method must be squash, merge or rebase"
[[ "$MC_TIMEOUT" =~ ^[0-9]+$ ]] || usage_error "--timeout must be a whole number of seconds"
[[ "$MC_POLL" =~ ^[0-9]+$ ]] || usage_error "MERGE_CHAIN_POLL_SECONDS must be a whole number"

MC_PR_LIST=()
mc_raw=()
[ -n "${MC_PRS// /}" ] && IFS=',' read -r -a mc_raw <<<"${MC_PRS// /}"
for mc_p in ${mc_raw[@]+"${mc_raw[@]}"}; do
  mc_p="${mc_p#\#}"
  [ -z "$mc_p" ] && continue
  [[ "$mc_p" =~ ^[0-9]+$ ]] || usage_error "--prs entry '$mc_p' is not a PR number"
  MC_PR_LIST+=("$mc_p")
done
[ "${#MC_PR_LIST[@]}" -gt 0 ] || usage_error "--prs needs at least one PR number"
command -v jq >/dev/null 2>&1 || usage_error "jq is required"
command -v gh >/dev/null 2>&1 || usage_error "gh is required"

oneline() { tr '\n\r' '  ' | tr -s ' ' | sed 's/^ *//; s/ *$//' | cut -c1-160; }

# Per-PR result, set by process_pr.
PR_STATUS=""
PR_REASON=""
PR_HEAD=""
PR_MERGE_COMMIT=""

result() { PR_STATUS="$1"; PR_REASON="${2:-}"; }

view() { gh pr view "$1" -R "$MC_REPO" --json "$2" 2>/dev/null; }

# Wait until the PR's checks have all completed on a stable head. Sets
# PR_HEAD and MC_MS (mergeStateStatus) on success; calls result() and returns 1
# when the PR must stop here.
wait_for_ci() {
  local n="$1" deadline polls=0 prev="" j state head ms total pending failed sig
  deadline=$((SECONDS + MC_TIMEOUT))
  while :; do
    polls=$((polls + 1))
    j=$(view "$n" state,headRefOid,mergeStateStatus,statusCheckRollup) ||
      { result ERROR "read_failed: gh pr view (checks) failed"; return 1; }
    state=$(jq -r '.state // ""' <<<"$j") || { result ERROR "read_failed: unparseable checks JSON"; return 1; }
    if [ "$state" = "MERGED" ]; then result SKIPPED "already_merged: merged while waiting for CI"; return 1; fi
    if [ "$state" != "OPEN" ]; then result SKIPPED "closed: state became $state while waiting for CI"; return 1; fi
    head=$(jq -r '.headRefOid // ""' <<<"$j")
    ms=$(jq -r '.mergeStateStatus // ""' <<<"$j")
    # CheckRun carries status/conclusion; StatusContext carries state.
    total=$(jq '[.statusCheckRollup // [] | .[]] | length' <<<"$j") || { result ERROR "read_failed: unparseable checks JSON"; return 1; }
    pending=$(jq '[.statusCheckRollup // [] | .[]
        | select(if .__typename == "StatusContext" or (has("state") and (has("status") | not))
                 then (.state == "PENDING" or .state == "EXPECTED")
                 else (.status != "COMPLETED") end)] | length' <<<"$j")
    failed=$(jq -r '[.statusCheckRollup // [] | .[]
        | select(if .__typename == "StatusContext" or (has("state") and (has("status") | not))
                 then (.state == "FAILURE" or .state == "ERROR")
                 else (.status == "COMPLETED" and ((.conclusion // "") | IN("FAILURE","CANCELLED","TIMED_OUT","ACTION_REQUIRED","STARTUP_FAILURE","STALE")))
                 end)
        | (.name // .context // "?")] | join(", ")' <<<"$j")
    if [ -n "$failed" ]; then result CI_RED "check_failed: $failed"; return 1; fi
    if [ "$ms" = "DIRTY" ]; then result CONFLICT "dirty: mergeStateStatus=DIRTY, the branch conflicts with its base"; return 1; fi
    if [ "$pending" -eq 0 ] && [ "$ms" != "UNKNOWN" ] && { [ "$total" -gt 0 ] || [ "$polls" -ge "$MC_MIN_EMPTY_POLLS" ]; }; then
      sig="$head|$total|$ms"
      if [ "$sig" = "$prev" ]; then PR_HEAD="$head"; MC_MS="$ms"; return 0; fi
      prev="$sig"
    else
      prev=""
    fi
    if [ "$SECONDS" -ge "$deadline" ]; then
      result CI_RED "ci_timeout: $pending of $total checks still pending after ${MC_TIMEOUT}s (mergeStateStatus=$ms)"
      return 1
    fi
    sleep "$MC_POLL"
  done
}

process_pr() {
  local n="$1" j state draft login is_bot head_ref out rc updates=0 late head mstate
  PR_STATUS="" PR_REASON="" PR_HEAD="" PR_MERGE_COMMIT=""

  # 1. State and author.
  j=$(view "$n" state,isDraft,author,headRefName,headRefOid) ||
    { result ERROR "read_failed: gh pr view $n failed"; return; }
  state=$(jq -r '.state // ""' <<<"$j") || { result ERROR "read_failed: unparseable PR JSON"; return; }
  draft=$(jq -r '.isDraft // false' <<<"$j")
  login=$(jq -r '.author.login // ""' <<<"$j")
  is_bot=$(jq -r '.author.is_bot // false' <<<"$j")
  head_ref=$(jq -r '.headRefName // ""' <<<"$j")
  PR_HEAD=$(jq -r '.headRefOid // ""' <<<"$j")
  case "$state" in
    MERGED) result SKIPPED "already_merged: nothing to do"; return ;;
    CLOSED) result SKIPPED "closed: PR is closed, not merging it"; return ;;
    OPEN) ;;
    *) result ERROR "read_failed: unexpected PR state '$state'"; return ;;
  esac
  if [ "$draft" = "true" ]; then result SKIPPED "draft: PR is a draft"; return; fi
  if [[ "$head_ref" == release-please--* || "$login" == *release-please* ]]; then
    result SKIPPED "release_please: release PRs merge through their own flow"; return
  fi
  if [[ "$head_ref" == renovate/* || "$login" == *renovate* ]]; then
    result SKIPPED "renovate: dependency PRs merge through their own flow"; return
  fi
  if ! { [ -n "$login" ] && { [ "$login" = "$MC_SELF" ] || [ "$is_bot" = "true" ] ||
        [[ "$login" == *"[bot]" || "$login" == app/* ]]; }; }; then
    result SKIPPED "non_self_author: author '${login:-unknown}' is neither $MC_SELF nor a bot; review it, do not chain-merge it"
    return
  fi

  while :; do
    # 2. Bring the branch up to date with its base (no-op when already current).
    out=$(gh pr update-branch "$n" -R "$MC_REPO" 2>&1); rc=$?
    if [ "$rc" -ne 0 ]; then
      if grep -qi 'conflict' <<<"$out"; then result CONFLICT "update_branch_conflict: $(oneline <<<"$out")"
      elif grep -qE "$PERMISSION_RE" <<<"$out"; then result DENIED "update_branch_denied: $(oneline <<<"$out")"
      else result ERROR "update_branch_failed: $(oneline <<<"$out")"; fi
      return
    fi

    # 3. Wait for CI on the new head, then read mergeStateStatus.
    MC_MS=""
    wait_for_ci "$n" || return
    case "$MC_MS" in
      CLEAN|HAS_HOOKS) break ;;
      BEHIND)
        updates=$((updates + 1))
        if [ "$updates" -ge "$MC_MAX_UPDATES" ]; then
          result CI_RED "still_behind: base moved during CI $updates times"; return
        fi ;;
      UNSTABLE) result CI_RED "unstable: a non-required status is not passing (see SKILL.md §4)"; return ;;
      BLOCKED) result DENIED "blocked_by_protection: checks are green but branch protection refuses the merge (required review?)"; return ;;
      DRAFT) result SKIPPED "draft: PR is a draft"; return ;;
      *) result ERROR "unexpected_merge_state: mergeStateStatus=$MC_MS"; return ;;
    esac
  done

  # 4. The §6 guard: no non-merge commit newer than the review, and the head
  #    must be the one CI just settled on. Fail closed on any read error.
  j=$(view "$n" commits,headRefOid) || { result ERROR "read_failed: gh pr view $n --json commits failed"; return; }
  late=$(jq -r --arg t "$MC_REVIEW_TS" '[.commits[] | select(.committedDate > $t)
      | select((.messageHeadline | startswith("Merge")) | not)
      | "\(.oid[0:8]) \(.messageHeadline)"] | join("; ")' <<<"$j") ||
    { result ERROR "read_failed: could not evaluate the commit list"; return; }
  head=$(jq -r '.headRefOid // ""' <<<"$j")
  if [ -n "$late" ]; then result GUARD_LATE_COMMIT "late_commits: $late"; return; fi
  if ! [[ "$head" =~ ^[0-9a-f]{40}$ ]]; then result ERROR "bad_head_sha: '$head' is not a full 40-character SHA"; return; fi
  if [ "$head" != "$PR_HEAD" ]; then
    result GUARD_LATE_COMMIT "head_moved: head changed from ${PR_HEAD:0:8} to ${head:0:8} after CI settled"; return
  fi

  # 5. Merge pinned to that head, then read the state back.
  out=$(gh pr merge "$n" -R "$MC_REPO" "--$MC_METHOD" --delete-branch --match-head-commit "$head" 2>&1); rc=$?
  if [ "$rc" -ne 0 ]; then
    if grep -qE "$HEAD_MOVED_RE" <<<"$out"; then result GUARD_LATE_COMMIT "head_moved: $(oneline <<<"$out")"
    elif grep -qE "$PERMISSION_RE" <<<"$out"; then result DENIED "merge_denied: $(oneline <<<"$out")"
    elif grep -qi 'conflict' <<<"$out"; then result CONFLICT "merge_conflict: $(oneline <<<"$out")"
    else result ERROR "merge_failed: $(oneline <<<"$out")"; fi
    return
  fi
  local tries=0
  while [ "$tries" -lt 5 ]; do
    tries=$((tries + 1))
    j=$(view "$n" state,mergeCommit) || { sleep "$MC_POLL"; continue; }
    mstate=$(jq -r '.state // ""' <<<"$j")
    if [ "$mstate" = "MERGED" ]; then
      PR_MERGE_COMMIT=$(jq -r '.mergeCommit.oid // ""' <<<"$j")
      result MERGED ""
      # 6. Refresh the local clone for whoever resolves the next conflict.
      if [ -n "$MC_FETCH_DIR" ]; then
        if git -C "$MC_FETCH_DIR" fetch -q origin >/dev/null 2>&1; then MC_FETCH=ok; else MC_FETCH=failed; fi
      fi
      return
    fi
    sleep "$MC_POLL"
  done
  result ERROR "not_merged_after_merge: gh pr merge exited 0 but the PR is not MERGED (merge queue or auto-merge?)"
}

# ---- main -----------------------------------------------------------------

MC_SELF=$(gh api user --jq .login 2>/dev/null) || MC_SELF=""
MC_MERGED=()
MC_SKIPPED=()
MC_ROWS=()
MC_STOPPED_AT=""
MC_REMAINING=""

if [ -z "$MC_SELF" ]; then
  MC_STOPPED_AT="${MC_PR_LIST[0]}"
  MC_ROWS+=("ERROR|ERROR|${MC_PR_LIST[0]}|self_unknown: gh api user failed, so authorship cannot be checked")
  MC_REMAINING=$(IFS=,; echo "${MC_PR_LIST[*]}")
else
  for i in "${!MC_PR_LIST[@]}"; do
    n="${MC_PR_LIST[$i]}"
    MC_FETCH=""
    process_pr "$n"
    echo "=== PR $n ==="
    echo "PR=$n"
    [ -n "$PR_HEAD" ] && echo "HEAD_SHA=$PR_HEAD"
    echo "STATUS=$PR_STATUS"
    [ -n "$PR_REASON" ] && echo "REASON=$(oneline <<<"$PR_REASON" | cut -c1-200)"
    [ -n "$PR_MERGE_COMMIT" ] && echo "MERGE_COMMIT=$PR_MERGE_COMMIT"
    [ -n "$MC_FETCH" ] && echo "FETCH=$MC_FETCH"
    echo "=== END PR $n ==="
    case "$PR_STATUS" in
      MERGED) MC_MERGED+=("$n") ;;
      SKIPPED) MC_SKIPPED+=("$n"); MC_ROWS+=("WARN|SKIPPED|$n|$PR_REASON") ;;
      *)
        MC_ROWS+=("ERROR|$PR_STATUS|$n|$PR_REASON")
        MC_STOPPED_AT="$n"
        MC_REMAINING=$(IFS=,; echo "${MC_PR_LIST[*]:$i}")
        break ;;
    esac
  done
fi

# Summary. ERROR rows sort first so REASON= names the stop, not a skip.
mc_errors=() mc_warns=()
for r in ${MC_ROWS[@]+"${MC_ROWS[@]}"}; do
  case "$r" in ERROR\|*) mc_errors+=("$r") ;; *) mc_warns+=("$r") ;; esac
done
mc_sorted=(${mc_errors[@]+"${mc_errors[@]}"} ${mc_warns[@]+"${mc_warns[@]}"})
if [ "${#mc_errors[@]}" -gt 0 ]; then mc_status=ERROR
elif [ "${#mc_warns[@]}" -gt 0 ]; then mc_status=WARN
else mc_status=OK; fi

echo "=== MERGE CHAIN ==="
echo "REPO=$MC_REPO"
echo "REVIEW_TS=$MC_REVIEW_TS"
echo "SELF=$MC_SELF"
echo "MERGED=$(IFS=,; echo "${MC_MERGED[*]+"${MC_MERGED[*]}"}")"
echo "SKIPPED=$(IFS=,; echo "${MC_SKIPPED[*]+"${MC_SKIPPED[*]}"}")"
echo "STOPPED_AT=$MC_STOPPED_AT"
echo "REMAINING=$MC_REMAINING"
echo "STATUS=$mc_status"
if [ "$mc_status" != OK ]; then
  IFS='|' read -r _ mc_type mc_n mc_msg <<<"${mc_sorted[0]}"
  mc_reason="$mc_type: #$mc_n $(oneline <<<"$mc_msg" | cut -c1-150)"
  [ "${#mc_sorted[@]}" -gt 1 ] && mc_reason="$mc_reason (+$((${#mc_sorted[@]} - 1)) more)"
  echo "REASON=$mc_reason"
fi
echo "ISSUE_COUNT=${#mc_sorted[@]}"
if [ "${#mc_sorted[@]}" -gt 0 ]; then
  echo "ISSUES:"
  for r in "${mc_sorted[@]}"; do
    IFS='|' read -r mc_sev mc_type mc_n mc_msg <<<"$r"
    echo "  - SEVERITY=$mc_sev TYPE=$mc_type PR=$mc_n MSG=$(oneline <<<"$mc_msg")"
  done
fi
echo "=== END MERGE CHAIN ==="

[ "$mc_status" = ERROR ] && exit 1
exit 0
