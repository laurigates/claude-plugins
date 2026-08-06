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
#       [--journal-todo-stop <h>] [--with-blueprint] [--recent-days <n>]
#       [--summary] [--verbose]
#
# Every section is exit-0 on empty (parallel-safe-queries.md). Each task carries
# its stable UUID so callers never operate on a volatile numeric ID (#1417).
#
# Ordering contract (#2276): every no-network section is emitted BEFORE the
# GitHub-backed ones, and each GitHub call runs in parallel under its own
# watchdog. A hard kill at the hook's timeout therefore truncates the digest
# rather than producing nothing at all.
set -uo pipefail

project=""
project_dir=""
home_dir=""
with_dedup=false
with_journal=false
with_commits=false
with_blueprint=false
commit_count=20
journal_path=""
journal_todo_heading="## Todo"
journal_todo_stop=""
summary_mode=false
recent_days="${SESSION_SURVEY_RECENT_DAYS:-2}"

while [ $# -gt 0 ]; do
  case "$1" in
    --project) project="$2"; shift 2 ;;
    --project-dir) project_dir="$2"; shift 2 ;;
    --home-dir) home_dir="$2"; shift 2 ;;
    --with-dedup) with_dedup=true; shift ;;
    --with-journal) with_journal=true; shift ;;
    --with-commits) with_commits=true; shift ;;
    --with-blueprint) with_blueprint=true; shift ;;
    --commit-count) commit_count="$2"; shift 2 ;;
    --recent-days) recent_days="$2"; shift 2 ;;
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
# Per-call network budget in seconds. One hung `gh` must not eat the whole
# SessionStart hook timeout (#2276).
gh_budget="${SESSION_SURVEY_GH_TIMEOUT:-4}"

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
#
# The basename is a GUESS (#2271): a chezmoi source dir, a worktree, a monorepo
# subdir, or a repo cloned under another name all yield a slug that matches no
# task. TASK_SCOPE / PROJECT_CONFIDENCE below make that uncertainty visible
# instead of letting a wrong slug report a confident OPEN_TASKS=0.
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
recent_task_count=0

# Git state
git_branch=""
if [ "$in_git" = true ]; then
  git_branch=$("$git_bin" -C "$project_dir" branch --show-current 2>/dev/null || echo "")
  [ -n "$("$git_bin" -C "$project_dir" status --porcelain 2>/dev/null | head -1)" ] && dirty=true
  # awk, not `grep -c '' || echo 0`: on a branch with no upstream `git log`
  # fails, grep -c prints 0 AND exits 1, so the `|| echo 0` ALSO ran and
  # UNPUSHED became the two-line value "0\n0" — breaking the KEY=VALUE
  # contract and making the -gt test below an unconditional false.
  unpushed=$("$git_bin" -C "$project_dir" log '@{u}..HEAD' --oneline 2>/dev/null | awk 'END{print NR+0}')
  [ -n "$unpushed" ] || unpushed=0
fi

# The git remote's repo name — a second, cheap (local, no network) candidate
# for the taskwarrior project slug, consulted only when the basename matches
# nothing (#2271).
project_remote_name=""
if [ "$in_git" = true ]; then
  remote_url=$("$git_bin" -C "$project_dir" remote get-url origin 2>/dev/null \
    || "$git_bin" -C "$project_dir" remote -v 2>/dev/null | awk 'NR==1{print $2}')
  if [ -n "${remote_url:-}" ]; then
    project_remote_name="${remote_url%.git}"
    project_remote_name="${project_remote_name##*/}"
    project_remote_name="${project_remote_name##*:}"
  fi
fi

# ---------------------------------------------------------------------------
# GitHub calls — launched HERE (in parallel, each individually bounded) so the
# network overlaps the ~180ms of local work below, and reaped after every
# local section has already been printed.
#
# There is deliberately no `gh auth status` probe: it was a full network
# round-trip spent deciding whether to make network round-trips (#2276).
# GH_READY is derived from the first real call's exit status instead, which
# preserves the "not queried" vs "genuine zero" distinction the probe existed
# for (drift-detection-triggering.md: never act on uncertainty).
# ---------------------------------------------------------------------------
gh_dir=""
gh_pids=()
if have "$gh_bin"; then
  gh_dir="$(mktemp -d 2>/dev/null)" || gh_dir=""
  # Guard the sandbox dir: an empty value would make every path below resolve
  # relative to the CWD (check-git-sandbox-guards.sh, issue #1692).
  if [ -z "$gh_dir" ] || [ ! -d "$gh_dir" ]; then
    gh_dir=""
  else
    trap 'rm -rf "$gh_dir"' EXIT
  fi
fi

# Launch one gh call in the background under its OWN watchdog, so a single hang
# cannot consume the whole budget. `timeout(1)` is deliberately not used: it is
# GNU coreutils and absent from stock macOS (shell-scripting.md).
gh_job() {
  local job_name="$1"; shift
  [ -n "$gh_dir" ] || return 0
  (
    ( cd "$project_dir" && "$gh_bin" "$@" ) >"$gh_dir/$job_name.json" 2>/dev/null &
    gh_inner=$!
    ( sleep "$gh_budget"; kill "$gh_inner" 2>/dev/null ) >/dev/null 2>&1 &
    gh_watch=$!
    wait "$gh_inner"; gh_rc=$?
    kill "$gh_watch" 2>/dev/null
    printf '%s' "$gh_rc" > "$gh_dir/$job_name.rc"
  ) >/dev/null 2>&1 &
  gh_pids+=("$!")
}

gh_rc_of() {
  [ -n "$gh_dir" ] || { printf '%s' "missing"; return 0; }
  [ -f "$gh_dir/$1.rc" ] || { printf '%s' "missing"; return 0; }
  cat "$gh_dir/$1.rc" 2>/dev/null || printf '%s' "missing"
}

# Emits the job's JSON when it succeeded; empty otherwise. Return status is the
# call's success, which is what GH_READY keys on.
gh_read() {
  [ "$(gh_rc_of "$1")" = "0" ] || return 1
  cat "$gh_dir/$1.json" 2>/dev/null
}

if [ -n "$gh_dir" ]; then
  # --summary emits no PR data (THREADS omits pr_count), so summary mode makes
  # only the call whose output it actually prints.
  if [ "$summary_mode" = false ]; then
    gh_job author_prs pr list --author @me --state open \
      --json number,title,url,state,updatedAt
    if [ -n "$git_branch" ]; then
      gh_job head_prs pr list --head "$git_branch" \
        --json number,title,url,state,updatedAt
    fi
  fi
  if [ "$with_dedup" = true ]; then
    gh_job issues issue list --assignee @me --state open \
      --json number,title,url,updatedAt
  fi
fi

# ---------------------------------------------------------------------------
# Taskwarrior — ONE all-projects snapshot, scoped in jq (#2271 + #2232).
#
# A single `(status:pending or +ACTIVE)` export serves all four consumers: the
# project-scoped count, the +ACTIVE-elsewhere footnote, the alternate-slug
# candidates, and the recent-task fallback. Scoping in jq (rather than a
# `project:` filter) is what lets the collector SEE that the detected slug
# matched nothing while other tasks exist — the signal both issues need.
#
# Assumes Taskwarrior 3.x, where a started (+ACTIVE) task is always
# status:pending, so this snapshot is a superset of the old `+ACTIVE export`.
# ---------------------------------------------------------------------------
task_available=false
all_tasks_json="[]"
if have "$task_bin"; then
  task_available=true
  all_tasks_json=$("$task_bin" '(status:pending or +ACTIVE)' export 2>/dev/null || echo "[]")
  [ -n "$all_tasks_json" ] || all_tasks_json="[]"
fi

scope_of() {
  printf '%s' "$all_tasks_json" \
    | jq -c --arg p "$1" '[.[] | select((.project // "") == $p)]' 2>/dev/null || echo "[]"
}

tasks_all=0
project_tasks_json="[]"
active_all_json="[]"
task_scope="project"
project_confidence="high"
project_resolved=""

if [ "$task_available" = false ]; then
  task_scope="none"
  project_confidence="low"
elif ! have jq; then
  # No jq means no scoping at all — never report a confident zero.
  task_scope="unknown"
  project_confidence="low"
else
  tasks_all=$(printf '%s' "$all_tasks_json" | jq 'length' 2>/dev/null || echo 0)
  [ -n "$tasks_all" ] || tasks_all=0
  if [ -n "$project" ]; then
    project_tasks_json=$(scope_of "$project")
    [ -n "$project_tasks_json" ] || project_tasks_json="[]"
    open_tasks=$(printf '%s' "$project_tasks_json" | jq 'length' 2>/dev/null || echo 0)
  fi
  [ -n "$open_tasks" ] || open_tasks=0

  # The scoped query matched nothing while tasks exist elsewhere: the detected
  # slug is suspect. An explicit --project is user-asserted, so it keeps its
  # confident zero.
  if [ "${open_tasks:-0}" -eq 0 ] && [ "${tasks_all:-0}" -gt 0 ] && [ "$detection" != "override" ]; then
    alt_json="[]"
    alt_n=0
    if [ -n "$project_remote_name" ] && [ "$project_remote_name" != "$project" ]; then
      alt_json=$(scope_of "$project_remote_name")
      [ -n "$alt_json" ] || alt_json="[]"
      alt_n=$(printf '%s' "$alt_json" | jq 'length' 2>/dev/null || echo 0)
      [ -n "$alt_n" ] || alt_n=0
    fi
    if [ "${alt_n:-0}" -gt 0 ]; then
      # (1) #2271: the git remote's repo name resolved it.
      task_scope="remote-name"
      project_resolved="$project_remote_name"
      project_tasks_json="$alt_json"
      open_tasks="$alt_n"
    else
      # (2) #2232: no single slug wins (portfolio checkout, renamed dir, …).
      # Widen, and make the widening visible rather than reporting a clean 0.
      task_scope="all-projects-fallback"
    fi
    project_confidence="low"
  fi

  active_all_json=$(printf '%s' "$all_tasks_json" \
    | jq -c '[.[] | select((.tags // []) | index("ACTIVE"))]' 2>/dev/null || echo "[]")
  [ -n "$active_all_json" ] || active_all_json="[]"
  active_tasks=$(printf '%s' "$project_tasks_json" \
    | jq '[.[] | select((.tags // []) | index("ACTIVE"))] | length' 2>/dev/null || echo 0)
  [ -n "$active_tasks" ] || active_tasks=0
fi

# Recent-task fallback — only in all-projects-fallback, so the normal path
# gains no noise. Recency is computed with the same days_since() helper the
# rest of the digest uses (it already handles taskwarrior's compact stamp),
# not an inline jq date parse.
recent_uuids=()
recent_projects=()
recent_descs=()
recent_ages=()
recent_truncated=false
if [ "$task_scope" = "all-projects-fallback" ] && have jq; then
  while IFS=$'\t' read -r r_uuid r_proj r_desc r_mod; do
    [ -n "$r_uuid" ] || continue
    r_age=$(days_since "$r_mod" 2>/dev/null || echo "")
    [ -n "$r_age" ] || continue
    [ "$r_age" -le "$recent_days" ] 2>/dev/null || continue
    recent_task_count=$((recent_task_count + 1))
    if [ "$recent_task_count" -le 10 ]; then
      recent_uuids+=("$r_uuid")
      recent_projects+=("$r_proj")
      recent_descs+=("$r_desc")
      recent_ages+=("$r_age")
    else
      recent_truncated=true
    fi
  done < <(printf '%s' "$all_tasks_json" | jq -r '
    sort_by(.modified // .entry // "") | reverse | .[]
    | [ .uuid,
        (.project // ""),
        (.description | gsub("\t";" ")),
        (.modified // .entry // "")
      ] | @tsv' 2>/dev/null)
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

# ---------------------------------------------------------------------------
# Reap the GitHub calls. In summary mode this is the only wait; in full mode
# every local section has already been printed by the time we get here.
# ---------------------------------------------------------------------------
reap_github() {
  [ "${#gh_pids[@]}" -gt 0 ] && wait "${gh_pids[@]}" 2>/dev/null

  author_prs=$(gh_read author_prs); author_ok=$?
  head_prs=$(gh_read head_prs) || head_prs=""
  assigned_json=$(gh_read issues); issues_ok=$?

  # GH_READY: gh is present AND at least one real query returned 0. A timeout,
  # an auth failure, or "no git remotes found" all read as "not queried" —
  # never as a clean zero.
  if [ "$author_ok" = 0 ] || [ "$issues_ok" = 0 ]; then
    gh_ready=true
  fi
  [ -n "$author_prs" ] || author_prs="[]"
  [ -n "$head_prs" ] || head_prs="[]"
  [ -n "$assigned_json" ] || assigned_json="[]"

  # Diagnostic only — GH_READY stays a boolean (consumers branch on `false`).
  local job
  for job in author_prs head_prs issues; do
    case "$(gh_rc_of "$job")" in
      137|143) gh_timeout=true ;;
    esac
  done

  # Open PRs to surface as loose threads. Base this on the repo's actual open
  # PRs (--author @me), NOT the locally-checked-out branch: refspec pushes
  # (git push origin HEAD:refs/heads/<branch>) from parallel worktree agents
  # leave no local branch, so a branch-keyed lookup silently misses them
  # (#1915). The --head lookup is unioned in to also catch PRs authored by
  # others on the branch we happen to have checked out.
  if [ "$gh_ready" = true ]; then
    if have jq; then
      prs_json=$(printf '%s\n%s' "$author_prs" "$head_prs" \
        | jq -s 'add | unique_by(.number)' 2>/dev/null || echo "[]")
      [ -n "$prs_json" ] || prs_json="[]"
      pr_count=$(printf '%s' "$prs_json" | jq 'length' 2>/dev/null || echo 0)
    else
      prs_json="$author_prs"
    fi
  fi

  # GitHub drift (spinup): assigned-open issues minus those tracked in
  # taskwarrior. Dedup reads the WIDEST task set we trust — in the
  # all-projects fallback the project-scoped set is empty, and treating every
  # assigned issue as untracked there would be a fresh false signal.
  if [ "$with_dedup" = true ] && [ "$gh_ready" = true ] && have jq; then
    local dedup_tasks_json="$project_tasks_json"
    case "$task_scope" in
      all-projects-fallback|unknown) dedup_tasks_json="$all_tasks_json" ;;
    esac
    assigned_issues=$(printf '%s' "$assigned_json" | jq 'length' 2>/dev/null || echo 0)
    # Tracked issue numbers: ghid UDA + any #N / issues/N in description/annotations.
    # scan() with a capture group yields arrays, so take [0] of each match.
    tracked_json=$(printf '%s' "$dedup_tasks_json" | jq -c '
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
}

gh_ready=false
gh_timeout=false
prs_json="[]"
drift_json="[]"

if [ "$summary_mode" = true ]; then
  reap_github
fi

threads=0
[ "$dirty" = true ] && threads=$((threads + 1))
[ "${unpushed:-0}" -gt 0 ] 2>/dev/null && threads=$((threads + 1))
[ "${open_tasks:-0}" -gt 0 ] 2>/dev/null && threads=$((threads + open_tasks))
[ "${recent_task_count:-0}" -gt 0 ] 2>/dev/null && threads=$((threads + recent_task_count))
[ "${drift_issues:-0}" -gt 0 ] 2>/dev/null && threads=$((threads + drift_issues))
[ "${journal_todos:-0}" -gt 0 ] 2>/dev/null && threads=$((threads + journal_todos))

# ---------------------------------------------------------------------------
# Summary mode — coarse counts only, for the SessionStart nudge hook.
# ---------------------------------------------------------------------------
if [ "$summary_mode" = true ]; then
  echo "=== SESSION SURVEY SUMMARY ==="
  echo "PROJECT=${project}"
  echo "DETECTION=${detection}"
  echo "TASK_SCOPE=${task_scope}"
  echo "PROJECT_CONFIDENCE=${project_confidence}"
  [ -n "$project_resolved" ] && echo "PROJECT_RESOLVED=${project_resolved}"
  echo "DIRTY=${dirty}"
  echo "UNPUSHED=${unpushed}"
  echo "OPEN_TASKS=${open_tasks}"
  echo "RECENT_TASK_COUNT=${recent_task_count}"
  echo "GH_READY=${gh_ready}"
  echo "ASSIGNED_ISSUES=${assigned_issues}"
  echo "THREADS=${threads}"
  echo "STATUS=OK"
  echo "ISSUE_COUNT=0"
  echo "=== END SESSION SURVEY SUMMARY ==="
  exit 0
fi

# ---------------------------------------------------------------------------
# Full digest. No-network sections first (#2276) — each echo is its own
# write(2), so a hard kill truncates rather than erasing the digest.
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

echo "=== TASKWARRIOR ==="
echo "TASK_AVAILABLE=${task_available}"
echo "OPEN_TASKS=${open_tasks}"
echo "ACTIVE_TASKS=${active_tasks}"
echo "TASK_SCOPE=${task_scope}"
echo "PROJECT_CONFIDENCE=${project_confidence}"
echo "TASKS_ALL_PROJECTS=${tasks_all}"
[ -n "$project_remote_name" ] && echo "PROJECT_REMOTE_NAME=${project_remote_name}"
[ -n "$project_resolved" ] && echo "PROJECT_RESOLVED=${project_resolved}"
echo "RECENT_TASK_COUNT=${recent_task_count}"
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
if [ "${#recent_uuids[@]}" -gt 0 ]; then
  ridx=0
  while [ "$ridx" -lt "${#recent_uuids[@]}" ]; do
    n=$((ridx + 1))
    echo "RECENT_TASK_${n}_UUID=${recent_uuids[$ridx]}"
    echo "RECENT_TASK_${n}_PROJECT=${recent_projects[$ridx]}"
    echo "RECENT_TASK_${n}_DESC=${recent_descs[$ridx]}"
    echo "RECENT_TASK_${n}_AGE_DAYS=${recent_ages[$ridx]}"
    ridx=$((ridx + 1))
  done
fi
[ "$recent_truncated" = true ] && echo "RECENT_TASK_TRUNCATED=true"
echo "STATUS=OK"
echo "=== END TASKWARRIOR ==="

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

# Blueprint tracker state (spinup briefing + session-end drain qualify).
# Skills pass --with-blueprint unconditionally; detection lives here so
# consumers get a parse-stable section (MANIFEST=false + zeroed counts when
# the repo isn't blueprint-enabled) instead of a conditionally-absent one.
if [ "$with_blueprint" = true ]; then
  echo "=== BLUEPRINT ==="
  bp_manifest="$project_dir/docs/blueprint/manifest.json"
  bp_tracker="$project_dir/docs/blueprint/feature-tracker.json"
  bp_manifest_present=false
  bp_tracker_present=false
  ready_count=0
  blocked_count=0
  inflight_count=0
  inflight_wos=""
  closed_bpid_count=0
  undrained_count=0
  undrained_wos=""
  [ -f "$bp_manifest" ] && bp_manifest_present=true
  [ -f "$bp_tracker" ] && bp_tracker_present=true

  closed_bpid_json="[]"
  if [ "$bp_manifest_present" = true ] && have "$task_bin"; then
    # A separate call by design: this queries COMPLETED tasks, which are
    # outside the pending snapshot above. No project: filter — the
    # tracker-pending intersection below is the real scoper. The || guard is
    # required: an undeclared bpid UDA makes task error on the filter instead
    # of returning [].
    closed_bpid_json=$("$task_bin" bpid.any: status:completed export 2>/dev/null || echo "[]")
    [ -n "$closed_bpid_json" ] || closed_bpid_json="[]"
  fi

  if [ "$bp_manifest_present" = true ] && have jq; then
    closed_bpid_count=$(printf '%s' "$closed_bpid_json" | jq '[.[] | select(.bpid != null)] | length' 2>/dev/null || echo 0)
    if [ "$bp_tracker_present" = true ]; then
      # Feature counts via explicit-path union — NOT recursive `.. | objects`,
      # which over-counts because phases[] carry their own `status`.
      ready_count=$(jq '[(.features // []), [.phases[]?.features[]?]] | add | map(select(.status == "not_started")) | length' "$bp_tracker" 2>/dev/null || echo 0)
      blocked_count=$(jq '[(.features // []), [.phases[]?.features[]?]] | add | map(select(.status == "blocked")) | length' "$bp_tracker" 2>/dev/null || echo 0)
      inflight_count=$(jq '(.tasks.in_progress // []) | length' "$bp_tracker" 2>/dev/null || echo 0)
      inflight_wos=$(jq -r '(.tasks.in_progress // []) | map(.id // empty) | join(",")' "$bp_tracker" 2>/dev/null || echo "")
      # Undrained: closed-bpid WO ids ∩ tracker tasks.pending[].id — the
      # session-end drain-pass qualify signal.
      undrained_json=$(printf '%s' "$closed_bpid_json" | jq -c --slurpfile t "$bp_tracker" '
        ([ .[] | .bpid // empty ] | unique) as $closed
        | (($t[0].tasks.pending // []) | map(.id)) as $pending
        | [ $closed[] | select(. as $w | $pending | index($w)) ]' 2>/dev/null || echo "[]")
      [ -n "$undrained_json" ] || undrained_json="[]"
      undrained_count=$(printf '%s' "$undrained_json" | jq 'length' 2>/dev/null || echo 0)
      undrained_wos=$(printf '%s' "$undrained_json" | jq -r 'join(",")' 2>/dev/null || echo "")
    fi
  fi

  echo "MANIFEST=${bp_manifest_present}"
  echo "TRACKER=${bp_tracker_present}"
  echo "READY_COUNT=${ready_count}"
  echo "BLOCKED_COUNT=${blocked_count}"
  echo "INFLIGHT_COUNT=${inflight_count}"
  [ "${inflight_count:-0}" -gt 0 ] 2>/dev/null && echo "INFLIGHT_WOS=${inflight_wos}"
  echo "CLOSED_BPID_COUNT=${closed_bpid_count}"
  echo "UNDRAINED_COUNT=${undrained_count}"
  [ "${undrained_count:-0}" -gt 0 ] 2>/dev/null && echo "UNDRAINED_WOS=${undrained_wos}"
  echo "STATUS=OK"
  echo "=== END BLUEPRINT ==="
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

# ---------------------------------------------------------------------------
# Network-backed sections last (#2276). Everything above is already on stdout.
# ---------------------------------------------------------------------------
reap_github

echo "=== PRS ==="
echo "GH_READY=${gh_ready}"
[ "$gh_timeout" = true ] && echo "GH_TIMEOUT=true"
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

if [ "$with_dedup" = true ]; then
  echo "=== GITHUB_DRIFT ==="
  echo "GH_READY=${gh_ready}"
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
