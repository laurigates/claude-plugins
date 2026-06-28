#!/usr/bin/env bash
# reconcile.sh — close taskwarrior tasks whose linked GitHub issue/PR has
# closed or merged, so the queue does not silently accumulate stale trackers.
#
# task-status DETECTS this drift (drift: stale-open) but never acts on it.
# This script is the action: it snapshots pending tasks carrying ghid/ghpr,
# batch-checks upstream state via gh (few calls, cached per number), classifies
# each task live/stale, and — with --apply — closes the stale set.
#
# Close routing (the load-bearing nuance):
#   * Leaf stale tasks (no dependents)  → bulk `task import` round-trip
#     (one pass; set status=completed + end + reconcile annotation).
#   * Stale tasks that BLOCK others     → per-task `task done`
#     (fires taskwarrior's dependency auto-unblock, which `task import` does
#     NOT — import bypasses native hooks and the unblock pass).
#
# Default is DRY-RUN: classify and print, mutate nothing. Pass --apply to close.
#
# Flags:
#   --apply                  Perform the close (default: dry-run, no mutation)
#   --project=<name>         Scope to one project (default: resolved by caller)
#   --all                    Cross-project scope (no project filter)
#   --project-dir=<dir>      Directory for gh/git probes (default: cwd)
#   --limit=<n>              Max linked tasks to inspect (default 200)
#   --only-verdicts=<csv>    Restrict the APPLY set to these verdicts
#                            (e.g. pr-merged,issue-closed). Stale tasks whose
#                            verdict is not listed (notably pr-closed) stay
#                            reported (method=keep) but are never closed. Unset
#                            = every stale verdict is closeable (back-compat).
#                            UNKNOWN upstream is never stale, so this only ever
#                            narrows the apply set, never widens it.
#
# Output: structured KEY=VALUE block (.claude/rules/structured-script-output.md),
# one TASK line per linked task, then a summary. Always exit 0 on a clean run so
# the script stays parallel-safe in a Bash batch (failures surface in STATUS).
#
# Exit codes:
#   0 - clean run (dry-run or apply); see STATUS for OK/WARN/ERROR
#   1 - task binary missing

set -uo pipefail

rc_apply=false
rc_project=""
rc_all=false
rc_dir="$PWD"
rc_limit=200
rc_only_verdicts=""

while [ $# -gt 0 ]; do
  case "$1" in
    --apply) rc_apply=true ;;
    --project=*) rc_project="${1#*=}" ;;
    --project) shift; rc_project="${1:-}" ;;
    --all) rc_all=true ;;
    --project-dir=*) rc_dir="${1#*=}" ;;
    --project-dir) shift; rc_dir="${1:-$PWD}" ;;
    --limit=*) rc_limit="${1#*=}" ;;
    --limit) shift; rc_limit="${1:-200}" ;;
    --only-verdicts=*) rc_only_verdicts="${1#*=}" ;;
    --only-verdicts) shift; rc_only_verdicts="${1:-}" ;;
    *) ;;
  esac
  shift
done

# verdict_allowed <verdict> — is this stale verdict in the apply allowlist?
# An empty allowlist means every stale verdict is closeable (back-compat).
verdict_allowed() {
  [ -z "$rc_only_verdicts" ] && return 0
  case ",${rc_only_verdicts}," in
    *",$1,"*) return 0 ;;
    *) return 1 ;;
  esac
}

echo "=== TASK RECONCILE ==="

# gh resolves the default repo from the working directory, so operate there.
cd "$rc_dir" 2>/dev/null || true

if ! command -v task >/dev/null 2>&1; then
  echo "TASK_AVAILABLE=false"
  echo "STATUS=ERROR"
  echo "ISSUE_COUNT=1"
  echo "=== END TASK RECONCILE ==="
  exit 1
fi

gh_ok=false
if command -v gh >/dev/null 2>&1 && gh auth status >/dev/null 2>&1; then
  gh_ok=true
fi
echo "GH_AVAILABLE=${gh_ok}"

if [ "$gh_ok" != true ]; then
  echo "STATUS=WARN"
  echo "ISSUE_COUNT=1"
  echo "ISSUES:"
  echo "  - SEVERITY=WARN TYPE=gh_unavailable MSG=reconcile needs an authenticated gh; run gh auth login"
  echo "=== END TASK RECONCILE ==="
  exit 0
fi

# --- Build the project filter ---------------------------------------------
proj_filter=()
if [ "$rc_all" != true ] && [ -n "$rc_project" ]; then
  proj_filter=("project:${rc_project}")
fi
echo "SCOPE=${rc_project:-ALL}"
echo "MODE=$([ "$rc_apply" = true ] && echo apply || echo dry-run)"
echo "ONLY_VERDICTS=${rc_only_verdicts}"

# --- Snapshot linked pending tasks (parallel-safe export | jq) -------------
linked_json=$(task "${proj_filter[@]}" status:pending export 2>/dev/null \
  | jq -c "[.[] | select(.ghid != null or .ghpr != null)] | .[:${rc_limit}]" 2>/dev/null || echo "[]")
linked_count=$(printf '%s' "$linked_json" | jq 'length' 2>/dev/null || echo 0)
echo "TOTAL_LINKED=${linked_count}"

if [ "$linked_count" -eq 0 ]; then
  echo "STALE_COUNT=0"
  echo "STATUS=OK"
  echo "ISSUE_COUNT=0"
  echo "=== END TASK RECONCILE ==="
  exit 0
fi

# Tasks that block others — closing these via bulk import would skip the
# dependency auto-unblock, so they route to per-task `task done`.
blocking_uuids=$(task "${proj_filter[@]}" status:pending +BLOCKING export 2>/dev/null \
  | jq -r '.[].uuid' 2>/dev/null || true)

is_blocking() {
  printf '%s\n' "$blocking_uuids" | grep -qx "$1"
}

# --- Cache upstream state per number --------------------------------------
declare -A issue_state
declare -A pr_state

issue_state_for() {
  local n="$1"
  if [ -n "${issue_state[$n]:-}" ]; then printf '%s' "${issue_state[$n]}"; return; fi
  local s
  s=$(gh issue view "$n" --json state --jq '.state' 2>/dev/null || echo "UNKNOWN")
  [ -z "$s" ] && s="UNKNOWN"
  issue_state[$n]="$s"
  printf '%s' "$s"
}

pr_state_for() {
  local n="$1"
  if [ -n "${pr_state[$n]:-}" ]; then printf '%s' "${pr_state[$n]}"; return; fi
  local s
  s=$(gh pr view "$n" --json state --jq '.state' 2>/dev/null || echo "UNKNOWN")
  [ -z "$s" ] && s="UNKNOWN"
  pr_state[$n]="$s"
  printf '%s' "$s"
}

# --- Classify each task ----------------------------------------------------
bulk_uuids=()
declare -A reason_for
done_uuids=()
stale_count=0
live_count=0
unknown_count=0

task_count=$(printf '%s' "$linked_json" | jq 'length')
i=0
while [ "$i" -lt "$task_count" ]; do
  row=$(printf '%s' "$linked_json" | jq -c ".[$i]")
  t_id=$(printf '%s' "$row" | jq -r '.id')
  t_uuid=$(printf '%s' "$row" | jq -r '.uuid')
  t_ghid=$(printf '%s' "$row" | jq -r '.ghid // empty')
  t_ghpr=$(printf '%s' "$row" | jq -r '.ghpr // empty')
  # Project as a single token (taskwarrior projects are dotted slugs, no spaces)
  # so the per-project breakdown in scheduled-reconcile.sh can group TASK lines.
  t_project=$(printf '%s' "$row" | jq -r '.project // empty' | tr -d ' ')

  verdict="live"
  reason=""
  upstream="-"

  # PR signal takes authority over issue when both are present: a merged PR
  # means the work landed; an open PR means keep the task even if a linked
  # issue closed (the work lives in the PR).
  if [ -n "$t_ghpr" ]; then
    upstream=$(pr_state_for "$t_ghpr")
    case "$upstream" in
      MERGED) verdict="pr-merged"; reason="PR #${t_ghpr} merged" ;;
      CLOSED) verdict="pr-closed"; reason="PR #${t_ghpr} closed unmerged" ;;
      OPEN) verdict="live" ;;
      *) verdict="live"; unknown_count=$((unknown_count + 1)) ;;
    esac
  elif [ -n "$t_ghid" ]; then
    upstream=$(issue_state_for "$t_ghid")
    case "$upstream" in
      CLOSED) verdict="issue-closed"; reason="issue #${t_ghid} closed" ;;
      OPEN) verdict="live" ;;
      *) verdict="live"; unknown_count=$((unknown_count + 1)) ;;
    esac
  fi

  method="keep"
  if [ "$verdict" != "live" ]; then
    stale_count=$((stale_count + 1))
    if verdict_allowed "$verdict"; then
      # In the apply allowlist (or no allowlist) — route to the close path.
      if is_blocking "$t_uuid"; then
        method="done"
        done_uuids+=("$t_uuid")
      else
        method="bulk"
        bulk_uuids+=("$t_uuid")
      fi
      reason_for[$t_uuid]="$reason"
    else
      # Stale but outside the allowlist (e.g. pr-closed under
      # --only-verdicts=pr-merged,issue-closed): report it, never close it.
      method="keep"
    fi
  else
    live_count=$((live_count + 1))
  fi

  echo "TASK id=${t_id} project=${t_project:--} uuid=${t_uuid} ghid=${t_ghid:--} ghpr=${t_ghpr:--} upstream=${upstream} verdict=${verdict} method=${method}"
  i=$((i + 1))
done

echo "STALE_COUNT=${stale_count}"
echo "LIVE_COUNT=${live_count}"
echo "BULK_COUNT=${#bulk_uuids[@]}"
echo "DONE_COUNT=${#done_uuids[@]}"
[ "$unknown_count" -gt 0 ] && echo "UNKNOWN_UPSTREAM=${unknown_count}"

# --- Dry-run stops here ----------------------------------------------------
if [ "$rc_apply" != true ]; then
  echo "APPLIED=false"
  echo "STATUS=OK"
  echo "ISSUE_COUNT=${stale_count}"
  echo "=== END TASK RECONCILE ==="
  exit 0
fi

if [ "$stale_count" -eq 0 ]; then
  echo "APPLIED=true"
  echo "CLOSED_COUNT=0"
  echo "STATUS=OK"
  echo "ISSUE_COUNT=0"
  echo "=== END TASK RECONCILE ==="
  exit 0
fi

now_tw=$(date -u +%Y%m%dT%H%M%SZ)
closed=0
apply_failures=0

# Per-task `task done` for blocking tasks (fires dependency auto-unblock).
for u in "${done_uuids[@]}"; do
  task "$u" annotate "reconcile: ${reason_for[$u]}" </dev/null >/dev/null 2>&1 || true
  # "done" is quoted so shellcheck does not read it as a loop terminator (SC1010).
  if task rc.confirmation=no "$u" "done" </dev/null >/dev/null 2>&1; then
    closed=$((closed + 1))
  else
    apply_failures=$((apply_failures + 1))
  fi
done

# Bulk JSON round-trip for leaf tasks (no dependents). Preserves uuid/entry;
# sets status/end and appends the reconcile annotation in one import. NOTE:
# `task import` does NOT fire native (~/.task/hooks) on-modify hooks — that is
# acceptable for a close, and is why blocking tasks above use `task done`.
if [ "${#bulk_uuids[@]}" -gt 0 ]; then
  reasons_json="{}"
  for u in "${bulk_uuids[@]}"; do
    reasons_json=$(printf '%s' "$reasons_json" | jq --arg u "$u" --arg r "${reason_for[$u]}" '. + {($u): $r}')
  done
  uuid_list=$(printf '%s\n' "${bulk_uuids[@]}" | jq -R . | jq -cs .)

  import_payload=$(task "${proj_filter[@]}" status:pending export 2>/dev/null | jq -c \
    --argjson uuids "$uuid_list" \
    --argjson reasons "$reasons_json" \
    --arg now "$now_tw" '
      [ .[]
        | select(.uuid as $u | $uuids | index($u))
        | .status = "completed"
        | .end = $now
        | .annotations = ((.annotations // []) + [{entry: $now, description: ("reconcile: " + ($reasons[.uuid] // "linked item closed"))}])
      ]')

  imported=$(printf '%s' "$import_payload" | jq 'length' 2>/dev/null || echo 0)
  if printf '%s' "$import_payload" | task import >/dev/null 2>&1; then
    closed=$((closed + imported))
  else
    apply_failures=$((apply_failures + imported))
  fi
fi

echo "APPLIED=true"
echo "CLOSED_COUNT=${closed}"
if [ "$apply_failures" -gt 0 ]; then
  echo "STATUS=WARN"
  echo "ISSUE_COUNT=${apply_failures}"
  echo "ISSUES:"
  echo "  - SEVERITY=WARN TYPE=close_failed MSG=${apply_failures} task(s) failed to close; re-run dry-run to inspect"
else
  echo "STATUS=OK"
  echo "ISSUE_COUNT=0"
fi
echo "=== END TASK RECONCILE ==="
exit 0
