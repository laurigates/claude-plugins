#!/usr/bin/env bash
# Session Survey — read-only collector shared by session-spinup, session-wrap,
# session-end, and the spinup nudge hook. Emits structured KEY=VALUE sections
# (see .claude/rules/structured-script-output.md) so the LLM consumes a compact
# digest instead of re-running and re-parsing 5 raw surveys.
#
# READ-ONLY by contract: detection + survey + dedup + staleness only. All writes
# and judgment stay in the invoking skill.
#
# Usage:
#   bash session-survey.sh [--project <name>] [--project-dir <path>]
#       [--home-dir <path>] [--with-dedup] [--with-journal]
#       [--journal-path <dir>] [--journal-todo-heading <h>]
#       [--journal-todo-stop <h>] [--summary] [--verbose]
#
# Every section is exit-0 on empty (parallel-safe-queries.md). Each task carries
# its stable UUID so callers never operate on a volatile numeric ID (#1417).
set -uo pipefail

project=""
project_dir=""
home_dir=""
with_dedup=false
with_journal=false
with_commits=false
commit_count=20
journal_path=""
journal_todo_heading="## Todo"
journal_todo_stop=""
summary_mode=false

while [ $# -gt 0 ]; do
  case "$1" in
    --project) project="$2"; shift 2 ;;
    --project-dir) project_dir="$2"; shift 2 ;;
    --home-dir) home_dir="$2"; shift 2 ;;
    --with-dedup) with_dedup=true; shift ;;
    --with-journal) with_journal=true; shift ;;
    --with-commits) with_commits=true; shift ;;
    --commit-count) commit_count="$2"; shift 2 ;;
    --journal-path) journal_path="$2"; shift 2 ;;
    --journal-todo-heading) journal_todo_heading="$2"; shift 2 ;;
    --journal-todo-stop) journal_todo_stop="$2"; shift 2 ;;
    --summary) summary_mode=true; shift ;;
    --verbose) shift ;;
    *) shift ;;
  esac
done

: "${project_dir:=$(pwd)}"
: "${home_dir:=$HOME}"

# Test seams — override the binaries used so tests can stub them.
task_bin="${SESSION_SURVEY_TASK_BIN:-task}"
git_bin="${SESSION_SURVEY_GIT_BIN:-git}"
gh_bin="${SESSION_SURVEY_GH_BIN:-gh}"

have() { command -v "$1" >/dev/null 2>&1; }

# Portable timestamp → epoch. Handles taskwarrior compact form
# (YYYYMMDDTHHMMSSZ) and ISO-8601-with-separators (gh updatedAt). Full
# timestamps carry a time component, so the BSD bare-date midnight trap
# (shell-scripting.md) does not apply; both branches are still explicit.
epoch_of() {
  local ts="$1" norm stripped
  case "$ts" in
    [0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]T[0-9][0-9][0-9][0-9][0-9][0-9]Z)
      norm="${ts:0:4}-${ts:4:2}-${ts:6:2}T${ts:9:2}:${ts:11:2}:${ts:13:2}Z" ;;
    *) norm="$ts" ;;
  esac
  if date -d "$norm" +%s 2>/dev/null; then return 0; fi   # GNU
  stripped="${norm%Z}"
  date -j -u -f "%Y-%m-%dT%H:%M:%S" "$stripped" +%s 2>/dev/null  # BSD/macOS
}

now_epoch=$(date +%s)

days_since() {
  local ts="$1" e
  e=$(epoch_of "$ts") || return 1
  [ -n "$e" ] || return 1
  echo $(( (now_epoch - e) / 86400 ))
}

in_git=false
if have "$git_bin" && "$git_bin" -C "$project_dir" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  in_git=true
fi

# ---------------------------------------------------------------------------
# Project detection — mechanical layer only. --project wins; else the git
# repo-root basename; else ambiguous (the LLM applies its naming map / falls
# back to +ACTIVE or the git remote per the precedence table in the skill).
# ---------------------------------------------------------------------------
detection="ambiguous"
if [ -n "$project" ]; then
  detection="override"
elif [ "$in_git" = true ]; then
  repo_root=$("$git_bin" -C "$project_dir" rev-parse --show-toplevel 2>/dev/null || echo "")
  if [ -n "$repo_root" ]; then
    project=$(basename "$repo_root")
    detection="cwd-repo-basename"
  fi
fi

# ---------------------------------------------------------------------------
# Counts (filled below; surfaced in both summary and full mode).
# ---------------------------------------------------------------------------
dirty=false
unpushed=0
open_tasks=0
active_tasks=0
assigned_issues=0
drift_issues=0
journal_todos=0
pr_count=0

# Git state
git_branch=""
if [ "$in_git" = true ]; then
  git_branch=$("$git_bin" -C "$project_dir" branch --show-current 2>/dev/null || echo "")
  [ -n "$("$git_bin" -C "$project_dir" status --porcelain 2>/dev/null | head -1)" ] && dirty=true
  unpushed=$("$git_bin" -C "$project_dir" log '@{u}..HEAD' --oneline 2>/dev/null | grep -c '' || echo 0)
fi

# Taskwarrior queries (export → exit-0 on empty)
task_available=false
project_tasks_json="[]"
active_all_json="[]"
if have "$task_bin"; then
  task_available=true
  if [ -n "$project" ]; then
    project_tasks_json=$("$task_bin" project:"$project" '(status:pending or +ACTIVE)' export 2>/dev/null || echo "[]")
    [ -n "$project_tasks_json" ] || project_tasks_json="[]"
  fi
  active_all_json=$("$task_bin" +ACTIVE export 2>/dev/null || echo "[]")
  [ -n "$active_all_json" ] || active_all_json="[]"
fi

if have jq; then
  open_tasks=$(printf '%s' "$project_tasks_json" | jq 'length' 2>/dev/null || echo 0)
  active_tasks=$(printf '%s' "$project_tasks_json" | jq '[.[] | select((.tags // []) | index("ACTIVE"))] | length' 2>/dev/null || echo 0)
fi

# GitHub auth gate (PRs + assigned issues both need it)
gh_ready=false
if have "$gh_bin" && "$gh_bin" auth status >/dev/null 2>&1; then
  gh_ready=true
fi

prs_json="[]"
if [ "$gh_ready" = true ] && [ -n "$git_branch" ]; then
  prs_json=$( (cd "$project_dir" && "$gh_bin" pr list --head "$git_branch" \
    --json number,title,url,state,updatedAt 2>/dev/null) || echo "[]")
  [ -n "$prs_json" ] || prs_json="[]"
  have jq && pr_count=$(printf '%s' "$prs_json" | jq 'length' 2>/dev/null || echo 0)
fi

# GitHub drift (spinup): assigned-open issues minus those tracked in taskwarrior
drift_json="[]"
if [ "$with_dedup" = true ] && [ "$gh_ready" = true ] && have jq; then
  assigned_json=$( (cd "$project_dir" && "$gh_bin" issue list --assignee @me --state open \
    --json number,title,url,updatedAt 2>/dev/null) || echo "[]")
  [ -n "$assigned_json" ] || assigned_json="[]"
  assigned_issues=$(printf '%s' "$assigned_json" | jq 'length' 2>/dev/null || echo 0)
  # Tracked issue numbers: ghid UDA + any #N / issues/N in description/annotations.
  # scan() with a capture group yields arrays, so take [0] of each match.
  tracked_json=$(printf '%s' "$project_tasks_json" | jq -c '
    [ .[]
      | ( (.ghid // empty),
          ( ([.description] + [ (.annotations // [])[].description ])
            | join(" ")
            | scan("(?:#|issues/)([0-9]+)")[0] )
        )
    ] | map(tonumber) | unique' 2>/dev/null || echo "[]")
  [ -n "$tracked_json" ] || tracked_json="[]"
  drift_json=$(printf '%s' "$assigned_json" | jq -c --argjson tracked "$tracked_json" \
    '[ .[] | select(.number as $n | ($tracked | index($n)) | not) ]' 2>/dev/null || echo "[]")
  [ -n "$drift_json" ] || drift_json="[]"
  drift_issues=$(printf '%s' "$drift_json" | jq 'length' 2>/dev/null || echo 0)
fi

# Journal todos (spinup): first existing dated note in the last 7 days
journal_lines=""
if [ "$with_journal" = true ] && [ -n "$journal_path" ]; then
  jp="${journal_path/#\~/$home_dir}"
  for offset in 0 1 2 3 4 5 6 7; do
    if day=$(date -v-"${offset}"d +%Y-%m-%d 2>/dev/null); then :; else
      day=$(date -d "-${offset} day" +%Y-%m-%d 2>/dev/null || echo "")
    fi
    [ -n "$day" ] || continue
    note="$jp/$day.md"
    [ -f "$note" ] || continue
    journal_lines=$(awk -v todo="$journal_todo_heading" -v stop="$journal_todo_stop" '
      $0 == todo { in_todo = 1; next }
      in_todo && stop != "" && index($0, stop) == 1 { in_todo = 0 }
      in_todo && /^## / { in_todo = 0 }
      in_todo && /^- \[ \]/ { print }
    ' "$note")
    journal_note="$day"
    break
  done
  [ -n "$journal_lines" ] && journal_todos=$(printf '%s\n' "$journal_lines" | grep -c '' || echo 0)
fi

threads=0
[ "$dirty" = true ] && threads=$((threads + 1))
[ "${unpushed:-0}" -gt 0 ] 2>/dev/null && threads=$((threads + 1))
[ "${open_tasks:-0}" -gt 0 ] 2>/dev/null && threads=$((threads + open_tasks))
[ "${drift_issues:-0}" -gt 0 ] 2>/dev/null && threads=$((threads + drift_issues))
[ "${journal_todos:-0}" -gt 0 ] 2>/dev/null && threads=$((threads + journal_todos))

# ---------------------------------------------------------------------------
# Summary mode — coarse counts only, for the SessionStart nudge hook.
# ---------------------------------------------------------------------------
if [ "$summary_mode" = true ]; then
  echo "=== SESSION SURVEY SUMMARY ==="
  echo "PROJECT=${project}"
  echo "DETECTION=${detection}"
  echo "DIRTY=${dirty}"
  echo "UNPUSHED=${unpushed}"
  echo "OPEN_TASKS=${open_tasks}"
  echo "ASSIGNED_ISSUES=${assigned_issues}"
  echo "THREADS=${threads}"
  echo "STATUS=OK"
  echo "ISSUE_COUNT=0"
  echo "=== END SESSION SURVEY SUMMARY ==="
  exit 0
fi

# ---------------------------------------------------------------------------
# Full digest.
# ---------------------------------------------------------------------------
echo "=== PROJECT ==="
echo "PROJECT=${project}"
echo "DETECTION=${detection}"
echo "PROJECT_DIR=${project_dir}"
echo "STATUS=OK"
echo "=== END PROJECT ==="

echo "=== GIT ==="
echo "IN_GIT=${in_git}"
echo "BRANCH=${git_branch}"
echo "DIRTY=${dirty}"
echo "UNPUSHED=${unpushed}"
echo "STATUS=OK"
echo "=== END GIT ==="

echo "=== PRS ==="
echo "PR_COUNT=${pr_count}"
if have jq && [ "$pr_count" -gt 0 ] 2>/dev/null; then
  idx=0
  while IFS=$'\t' read -r num title url pstate upd; do
    idx=$((idx + 1))
    sd=$(days_since "$upd" 2>/dev/null || echo "")
    echo "PR_${idx}_NUMBER=${num}"
    echo "PR_${idx}_STATE=${pstate}"
    echo "PR_${idx}_TITLE=${title}"
    echo "PR_${idx}_URL=${url}"
    [ -n "$sd" ] && echo "PR_${idx}_STALE_DAYS=${sd}"
  done < <(printf '%s' "$prs_json" | jq -r '.[] | [(.number|tostring), .title, .url, .state, .updatedAt] | @tsv' 2>/dev/null)
fi
echo "STATUS=OK"
echo "=== END PRS ==="

echo "=== TASKWARRIOR ==="
echo "TASK_AVAILABLE=${task_available}"
echo "OPEN_TASKS=${open_tasks}"
echo "ACTIVE_TASKS=${active_tasks}"
if have jq && [ "$open_tasks" -gt 0 ] 2>/dev/null; then
  idx=0
  while IFS=$'\t' read -r uuid desc active modified annot ghid; do
    idx=$((idx + 1))
    sd=$(days_since "$modified" 2>/dev/null || echo "")
    echo "TASK_${idx}_UUID=${uuid}"
    echo "TASK_${idx}_ACTIVE=${active}"
    echo "TASK_${idx}_DESC=${desc}"
    [ -n "$sd" ] && echo "TASK_${idx}_STALE_DAYS=${sd}"
    [ -n "$annot" ] && [ "$annot" != "null" ] && echo "TASK_${idx}_ANNOT=${annot}"
    [ -n "$ghid" ] && [ "$ghid" != "null" ] && echo "TASK_${idx}_GHID=${ghid}"
  done < <(printf '%s' "$project_tasks_json" | jq -r '
    .[] | [ .uuid,
            (.description | gsub("\t";" ")),
            (((.tags // []) | index("ACTIVE")) != null),
            (.modified // ""),
            ((.annotations // []) | map(.description) | join(" | ") | gsub("\t";" ")),
            (.ghid // "")
          ] | @tsv' 2>/dev/null)
fi
echo "STATUS=OK"
echo "=== END TASKWARRIOR ==="

if [ "$with_dedup" = true ]; then
  echo "=== GITHUB_DRIFT ==="
  echo "ASSIGNED_ISSUES=${assigned_issues}"
  echo "DRIFT_COUNT=${drift_issues}"
  if have jq && [ "$drift_issues" -gt 0 ] 2>/dev/null; then
    idx=0
    while IFS=$'\t' read -r num title url upd; do
      idx=$((idx + 1))
      sd=$(days_since "$upd" 2>/dev/null || echo "")
      echo "ISSUE_${idx}_NUMBER=${num}"
      echo "ISSUE_${idx}_TITLE=${title}"
      echo "ISSUE_${idx}_URL=${url}"
      [ -n "$sd" ] && echo "ISSUE_${idx}_AGE_DAYS=${sd}"
    done < <(printf '%s' "$drift_json" | jq -r '.[] | [(.number|tostring), (.title|gsub("\t";" ")), .url, .updatedAt] | @tsv' 2>/dev/null)
  fi
  echo "STATUS=OK"
  echo "=== END GITHUB_DRIFT ==="
fi

if [ "$with_journal" = true ]; then
  echo "=== JOURNAL ==="
  echo "JOURNAL_NOTE=${journal_note:-}"
  echo "TODO_COUNT=${journal_todos}"
  if [ -n "$journal_lines" ]; then
    idx=0
    while IFS= read -r line; do
      [ -n "$line" ] || continue
      idx=$((idx + 1))
      cleaned=${line#- \[ \] }
      echo "TODO_${idx}=${cleaned}"
    done <<< "$journal_lines"
  fi
  echo "STATUS=OK"
  echo "=== END JOURNAL ==="
fi

if [ "$with_commits" = true ]; then
  echo "=== COMMITS ==="
  c_count=0
  if [ "$in_git" = true ]; then
    while IFS= read -r line; do
      [ -n "$line" ] || continue
      c_count=$((c_count + 1))
      echo "COMMIT_${c_count}=${line}"
    done < <("$git_bin" -C "$project_dir" log --oneline --max-count="$commit_count" 2>/dev/null)
  fi
  echo "COMMIT_COUNT=${c_count}"
  echo "STATUS=OK"
  echo "=== END COMMITS ==="
fi

# Cross-project +ACTIVE tasks (the "stale +ACTIVE elsewhere" footnote)
echo "=== STALE_ACTIVE_ELSEWHERE ==="
elsewhere_count=0
if have jq; then
  while IFS=$'\t' read -r uuid eproj edesc; do
    [ -n "$uuid" ] || continue
    [ "$eproj" = "$project" ] && continue
    elsewhere_count=$((elsewhere_count + 1))
    echo "STALE_${elsewhere_count}_UUID=${uuid}"
    echo "STALE_${elsewhere_count}_PROJECT=${eproj}"
    echo "STALE_${elsewhere_count}_DESC=${edesc}"
  done < <(printf '%s' "$active_all_json" | jq -r '.[] | [ .uuid, (.project // ""), (.description | gsub("\t";" ")) ] | @tsv' 2>/dev/null)
fi
echo "ELSEWHERE_COUNT=${elsewhere_count}"
echo "STATUS=OK"
echo "=== END STALE_ACTIVE_ELSEWHERE ==="
