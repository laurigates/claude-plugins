#!/usr/bin/env bash
# reconcile.sh — close taskwarrior tasks whose linked GitHub issue/PR has
# closed or merged, so the queue does not silently accumulate stale trackers.
#
# task-status DETECTS this drift (drift: stale-open) but never acts on it.
# This script is the action: it snapshots pending tasks that reference a
# GitHub issue/PR — via a ghid/ghpr UDA, OR a ref in the description/annotation
# text — batch-checks upstream state via gh (few calls, cached per ref),
# classifies each task live/stale, and — with --apply — closes the stale set.
#
# Ref sources (per task), in precedence order:
#   * ghpr / ghid UDA        → same-repo PR / issue (the original behaviour).
#   * description + annotations text, in three UNAMBIGUOUS forms:
#       - github.com/<owner>/<repo>/(issues|pull)/<N>   (repo + kind known)
#       - <owner>/<repo>#<N>                            (repo known, kind resolved)
#       - #<N>                                          (CWD repo, kind resolved)
#     Shorthand like "prompt-editor#42" (no owner/ slash) deliberately does NOT
#     match, so such a task stays KEEP rather than risk a wrong-repo close.
#
# Cross-repo: a ref naming <owner>/<repo> is checked with `gh … -R owner/repo`,
# not the CWD default — so a task in project A referencing owner/B#N resolves
# against B. Bare #N (and UDAs) use the CWD-resolved repo, as before.
#
# Ambiguous repo under --all (issue #3387): a bare #N or ghid/ghpr UDA names no
# repo, and the CWD repo is only trustworthy for tasks of the CWD's own project.
# So under --all such a ref resolves only when the task's project equals the CWD
# project (scripts/resolve-project.sh: basename of the git toplevel) or is a
# dotted child of it (<cwd-project>.*). For any other task it is AMBIGUOUS: never
# sent to gh, the task is kept (verdict=live, upstream=AMBIGUOUS, counted in
# AMBIGUOUS_REPO), and it can never be closed. Run from ~/repos, task OLMap
# "#65" otherwise resolved against the cwd repo's PR 65 (MERGED) while OLMap's
# own PR 65 was OPEN. Single-project runs are unchanged.
#
# Link strength (issue #3126): only a ghid/ghpr UDA can produce a close verdict
# (pr-merged / pr-closed / issue-closed). A task linked ONLY by text refs whose
# items are all done gets verdict=review — reported (REVIEW_COUNT, method=keep)
# and never closed, under --apply and under any --only-verdicts list. Tasks often
# cite a merged PR as context for work that is still open; 7 of 8 text-ref
# pr-merged verdicts in one dry run were false positives. review is not counted
# in STALE_COUNT, so the SessionStart drift line counts UDA-backed verdicts only.
#
# Multi-ref safety: a task with several refs is stale ONLY when EVERY ref is
# resolved done. Any open ref → live; any unreadable ref → kept (uncertain);
# any pr-closed among them → the aggregate is pr-closed (ambiguous, never in the
# bounded --only-verdicts auto-apply set). This prevents closing a
# "monitor #142, #143, #144" task when only some of them have closed.
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
#                            narrows the apply set, never widens it. review is
#                            rejected even when listed (#3126).
#
# Output: structured KEY=VALUE block (.claude/rules/structured-script-output.md),
# one TASK line per linked task, then a summary. Always exit 0 on a clean run so
# the script stays parallel-safe in a Bash batch (failures surface in STATUS).
#
# Exit codes:
#   0 - clean run (dry-run or apply); see STATUS for OK/WARN/ERROR
#   1 - task binary missing
#   2 - unknown argument (fail fast: a swallowed flag must never silently
#       widen a bounded --only-verdicts apply — issue #2057)

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
    # Fail fast on anything unrecognised. A silent catch-all here turned a
    # bounded --only-verdicts apply into an unbounded one under caller/script
    # version skew (the flag was swallowed, every stale verdict got closed,
    # including pr-closed — the case the flag exists to protect). Issue #2057.
    *)
      echo "reconcile.sh: unknown argument: $1" >&2
      echo "usage: reconcile.sh [--apply] [--project=<name>|--project <name>] [--all] [--project-dir=<dir>] [--limit=<n>] [--only-verdicts=<csv>]" >&2
      exit 2
      ;;
  esac
  shift
done

# verdict_allowed <verdict> — is this stale verdict in the apply allowlist?
# An empty allowlist means every stale verdict is closeable (back-compat).
verdict_allowed() {
  # review (text-ref-only link) never enters a close path, listed or not (#3126).
  [ "$1" = "review" ] && return 1
  [ -z "$rc_only_verdicts" ] && return 0
  case ",${rc_only_verdicts}," in
    *",$1,"*) return 0 ;;
    *) return 1 ;;
  esac
}

echo "=== TASK RECONCILE ==="

# Resolve the script's own dir before the cd below: a relative BASH_SOURCE
# (`bash scripts/reconcile.sh`) stops resolving once the cwd moves.
RC_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)"

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

# --- CWD project (for --all ambiguous-repo detection, #3387) ---------------
# Under --all a repo-less ref (bare #N, ghid/ghpr UDA) is only resolved for
# tasks of the CWD's project. Resolved with the plugin's shared ladder; if the
# resolver is missing, cwd_project stays empty and every such ref is ambiguous.
# Resolve from $PWD (where gh looks), not $rc_dir: after the cd above, a relative
# --project-dir no longer names the same directory.
cwd_project=""
if [ "$rc_all" = true ]; then
  rc_resolve="${RC_SCRIPT_DIR}/../../../scripts/resolve-project.sh"
  if [ -f "$rc_resolve" ]; then
    cwd_project=$(bash "$rc_resolve" --project-dir "$PWD" 2>/dev/null \
      | grep -m1 '^PROJECT=' | cut -d= -f2- || true)
  fi
fi

# repo_less_trusted <task-project> — may a repo-less ref resolve against the CWD
# repo for this task? Always outside --all; under --all only for the CWD project
# or a dotted child of it.
repo_less_trusted() {
  [ "$rc_all" != true ] && return 0
  [ -z "$cwd_project" ] && return 1
  case "$1" in
    "$cwd_project"|"$cwd_project".*) return 0 ;;
    *) return 1 ;;
  esac
}

# --- Build the project filter ---------------------------------------------
proj_filter=()
if [ "$rc_all" != true ] && [ -n "$rc_project" ]; then
  proj_filter=("project:${rc_project}")
fi
echo "SCOPE=${rc_project:-ALL}"
[ "$rc_all" = true ] && echo "CWD_PROJECT=${cwd_project}"
echo "MODE=$([ "$rc_apply" = true ] && echo apply || echo dry-run)"
echo "ONLY_VERDICTS=${rc_only_verdicts}"

# --- Ref extraction --------------------------------------------------------
# `refs`: from a task object, emit a deduped array of {repo,kind,num} refs.
# repo="" means "use the CWD-resolved default repo"; kind is pr|issue|unknown.
# Precedence: a ghpr/ghid UDA wins (same-repo); otherwise scan description +
# annotation text for the three unambiguous forms, removing each matched span
# before the next (looser) pattern so an owner/repo#N is not also counted as a
# bare #N. group_by folds duplicate (repo,num) refs, preferring a known kind.
read -r -d '' REF_JQ <<'JQ' || true
def refs:
  . as $t
  | (([$t.description // ""] + [ ($t.annotations // [])[].description // "" ]) | join("\n")) as $txt
  | if $t.ghpr != null then [ {repo:"", kind:"pr", num:($t.ghpr|tostring|sub("\\..*$";""))} ]
    elif $t.ghid != null then [ {repo:"", kind:"issue", num:($t.ghid|tostring|sub("\\..*$";""))} ]
    else
      ( [ $txt | match("github\\.com/([A-Za-z0-9._-]+/[A-Za-z0-9._-]+)/(issues|pull)/([0-9]+)"; "g")
          | {repo:.captures[0].string, kind:(if .captures[1].string=="pull" then "pr" else "issue" end), num:.captures[2].string} ] ) as $urls
      | ( $txt | gsub("github\\.com/[A-Za-z0-9._-]+/[A-Za-z0-9._-]+/(issues|pull)/[0-9]+"; " ") ) as $t2
      | ( [ $t2 | match("([A-Za-z0-9._-]+/[A-Za-z0-9._-]+)#([0-9]+)"; "g")
          | {repo:.captures[0].string, kind:"unknown", num:.captures[1].string} ] ) as $slash
      | ( $t2 | gsub("[A-Za-z0-9._-]+/[A-Za-z0-9._-]+#[0-9]+"; " ") ) as $t3
      | ( [ $t3 | match("(?<![A-Za-z0-9_/-])#([0-9]+)"; "g") | {repo:"", kind:"unknown", num:.captures[0].string} ] ) as $bare
      | ($urls + $slash + $bare)
      | group_by(.repo + "#" + .num)
      | map( { repo: .[0].repo, num: .[0].num,
               kind: ( if any(.[]; .kind=="pr") then "pr"
                       elif any(.[]; .kind=="issue") then "issue"
                       else "unknown" end ) } )
    end;
JQ

# --- Snapshot linked pending tasks (parallel-safe export | jq) -------------
# Select any task carrying a ghid/ghpr UDA OR a description/annotation ref.
linked_json=$(task "${proj_filter[@]}" status:pending export 2>/dev/null \
  | jq -c "${REF_JQ} [ .[] | select((refs | length) > 0) ] | .[:${rc_limit}]" 2>/dev/null || echo "[]")
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
  grep -qx "$1" <<<"$blocking_uuids"
}

# --- Cache upstream state per ref -----------------------------------------
# Keyed by "repo|kind|num" (repo "" = CWD default). Value is a normalized
# token: PR:MERGED / PR:CLOSED / PR:OPEN / ISSUE:CLOSED / ISSUE:OPEN / UNKNOWN.
declare -A ref_cache

ref_state() {
  local repo="$1" kind="$2" num="$3"
  local key="${repo}|${kind}|${num}"
  if [ -n "${ref_cache[$key]:-}" ]; then printf '%s' "${ref_cache[$key]}"; return; fi
  local rflag=() s out="UNKNOWN"
  [ -n "$repo" ] && rflag=(-R "$repo")
  case "$kind" in
    pr)
      s=$(gh pr view "$num" "${rflag[@]}" --json state --jq '.state' 2>/dev/null)
      [ -n "$s" ] && out="PR:${s}" ;;
    issue)
      s=$(gh issue view "$num" "${rflag[@]}" --json state --jq '.state' 2>/dev/null)
      [ -n "$s" ] && out="ISSUE:${s}" ;;
    *)
      # Unknown kind (bare #N or owner/repo#N): try PR first (a merged PR is the
      # common "done" signal), fall back to issue. A number that is an issue
      # makes `gh pr view` error → empty → we resolve it via the issue API.
      s=$(gh pr view "$num" "${rflag[@]}" --json state --jq '.state' 2>/dev/null)
      if [ -n "$s" ]; then out="PR:${s}"
      else
        s=$(gh issue view "$num" "${rflag[@]}" --json state --jq '.state' 2>/dev/null)
        [ -n "$s" ] && out="ISSUE:${s}"
      fi ;;
  esac
  ref_cache[$key]="$out"
  printf '%s' "$out"
}

# --- Classify each task ----------------------------------------------------
bulk_uuids=()
declare -A reason_for
done_uuids=()
stale_count=0
live_count=0
unknown_count=0
ambiguous_count=0
review_count=0

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

  refs_json=$(printf '%s' "$row" | jq -c "${REF_JQ} refs" 2>/dev/null || echo "[]")
  nrefs=$(printf '%s' "$refs_json" | jq 'length' 2>/dev/null || echo 0)

  # Resolve every ref, then aggregate. A multi-ref task is stale ONLY when every
  # ref resolved done; any open ref → live; any unreadable ref → keep.
  components=()   # per-ref stale verdicts (pr-merged/pr-closed/issue-closed)
  reasons=()
  bare_states=()  # per-ref bare state (MERGED/CLOSED/OPEN/UNKNOWN/AMBIGUOUS) for upstream=
  has_open=false
  has_unknown=false
  has_ambiguous=false
  r=0
  while [ "$r" -lt "$nrefs" ]; do
    rr=$(printf '%s' "$refs_json" | jq -c ".[$r]")
    r_repo=$(printf '%s' "$rr" | jq -r '.repo')
    r_kind=$(printf '%s' "$rr" | jq -r '.kind')
    r_num=$(printf '%s' "$rr" | jq -r '.num')
    if [ -z "$r_repo" ] && ! repo_less_trusted "$t_project"; then
      # No repo named and the task is outside the CWD project (--all): the CWD
      # repo is the wrong place to look, so do not ask gh at all (#3387).
      st="AMBIGUOUS"
    else
      st=$(ref_state "$r_repo" "$r_kind" "$r_num")
    fi
    bare_states+=("${st##*:}")
    ref_label="${r_repo}#${r_num}"
    case "$st" in
      PR:MERGED)    components+=("pr-merged");    reasons+=("PR ${ref_label} merged") ;;
      PR:CLOSED)    components+=("pr-closed");    reasons+=("PR ${ref_label} closed unmerged") ;;
      ISSUE:CLOSED) components+=("issue-closed"); reasons+=("issue ${ref_label} closed") ;;
      PR:OPEN|ISSUE:OPEN) has_open=true ;;
      AMBIGUOUS)    has_ambiguous=true ;;
      *)            has_unknown=true ;;
    esac
    r=$((r + 1))
  done

  verdict="live"
  reason=""
  upstream="-"
  [ "${#bare_states[@]}" -gt 0 ] && upstream=$(IFS=,; printf '%s' "${bare_states[*]}")

  if [ "$nrefs" -eq 0 ] || [ "$has_open" = true ]; then
    verdict="live"
  elif [ "$has_ambiguous" = true ]; then
    # A ref's repo is unknown under --all — never close on a guessed repo.
    verdict="live"
    ambiguous_count=$((ambiguous_count + 1))
  elif [ "$has_unknown" = true ]; then
    # A ref could not be confirmed done — never close on uncertainty.
    verdict="live"
    unknown_count=$((unknown_count + 1))
  else
    # Every ref resolved stale. Aggregate: an ambiguous pr-closed dominates
    # (kept out of the bounded auto-apply set); else pr-merged if any PR merged;
    # else issue-closed.
    if grep -qx 'pr-closed' <<<"$(printf '%s\n' "${components[@]}")"; then verdict="pr-closed"
    elif grep -qx 'pr-merged' <<<"$(printf '%s\n' "${components[@]}")"; then verdict="pr-merged"
    else verdict="issue-closed"; fi
    # A text ref alone is weak evidence: the task may cite the item as context
    # for open work. Without a ghid/ghpr UDA, report for review; never close.
    if [ -z "$t_ghid" ] && [ -z "$t_ghpr" ]; then verdict="review"; fi
    if [ "${#reasons[@]}" -eq 1 ]; then
      reason="${reasons[0]}"
    else
      reason=$(printf '%s; ' "${reasons[@]}"); reason="${reason%; }"
    fi
  fi

  method="keep"
  if [ "$verdict" = "review" ]; then
    # Reported only: never routed to a close path, never counted as stale.
    review_count=$((review_count + 1))
  elif [ "$verdict" != "live" ]; then
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

  echo "TASK id=${t_id} project=${t_project:--} uuid=${t_uuid} ghid=${t_ghid:--} ghpr=${t_ghpr:--} refs=${nrefs} upstream=${upstream} verdict=${verdict} method=${method}"
  i=$((i + 1))
done

echo "STALE_COUNT=${stale_count}"
echo "LIVE_COUNT=${live_count}"
echo "REVIEW_COUNT=${review_count}"
echo "BULK_COUNT=${#bulk_uuids[@]}"
echo "DONE_COUNT=${#done_uuids[@]}"
[ "$unknown_count" -gt 0 ] && echo "UNKNOWN_UPSTREAM=${unknown_count}"
[ "$ambiguous_count" -gt 0 ] && echo "AMBIGUOUS_REPO=${ambiguous_count}"

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
