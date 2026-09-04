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
# Ordering contract (#2276): in BOTH --summary and full mode, every no-network
# key is emitted BEFORE the GitHub-backed ones, and each GitHub call runs in
# parallel under its own watchdog. A hard kill at the hook's timeout therefore
# truncates the digest rather than producing nothing at all.
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

# Numeric knobs are validated, never swallowed. A non-numeric --recent-days
# made every window test false (a silent RECENT_TASK_COUNT=0 in the very change
# that exists to stop producing silent zeros); a non-numeric gh budget made the
# watchdog's `sleep` fail instantly and kill every gh call (a silent
# GH_READY=false). Both now fall back to the documented default and say so.
recent_days_invalid=""
case "$recent_days" in
  ''|*[!0-9]*) recent_days_invalid="$recent_days"; recent_days=2 ;;
esac
gh_budget_invalid=""

# Test seams — override the binaries used so tests can stub them.
task_bin="${SESSION_SURVEY_TASK_BIN:-task}"
git_bin="${SESSION_SURVEY_GIT_BIN:-git}"
gh_bin="${SESSION_SURVEY_GH_BIN:-gh}"
# Per-call network budget in seconds. One hung `gh` must not eat the whole
# SessionStart hook timeout (#2276).
#
# 8s, not 4s (#2425). A `gh pr list --author @me` resolves the `@me` handle
# before it can run the query, so the budget covers TWO round-trips; 4s was
# tight enough on a slow link or a degraded API that a healthy environment
# silently lost the dedup guard. The calls are backgrounded and parallel, so
# a higher ceiling costs wall-clock time only when something is actually slow,
# and the SessionStart hook's own timeout (15s) still bounds the whole run.
gh_budget="${SESSION_SURVEY_GH_TIMEOUT:-8}"
case "$gh_budget" in
  ''|*[!0-9]*) gh_budget_invalid="$gh_budget"; gh_budget=8 ;;
esac

have() { command -v "$1" >/dev/null 2>&1; }

# Row separator for the taskwarrior projections below. NOT a tab: TAB is an IFS
# *whitespace* character, so `IFS=$'\t' read` collapses a run of tabs into one
# delimiter and an EMPTY field silently shifts every later column left. That is
# not hypothetical here — a task with no annotations reported its `ghid` as
# TASK_n_ANNOT (and emitted no TASK_n_GHID at all), and a task with no project
# shifted its description into RECENT_TASK_n_PROJECT. US (0x1F) is not IFS
# whitespace, so empty fields are preserved. jq's join() stringifies booleans,
# numbers, and null for us.
US=$'\037'

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
# Project detection — mechanical layer only. --project wins; else a slug the
# repo DECLARES in .claude/session.json; else the git repo-root basename; else
# ambiguous (the LLM applies its naming map / falls back to +ACTIVE or the git
# remote per the precedence table in the skill).
#
# The basename is a GUESS (#2271): a chezmoi source dir, a worktree, a monorepo
# subdir, or a repo cloned under another name all yield a slug that matches no
# task. TASK_SCOPE / PROJECT_CONFIDENCE below make that uncertainty visible
# instead of letting a wrong slug report a confident OPEN_TASKS=0.
# ---------------------------------------------------------------------------

# A repo-declared slug (#2304). Explicit beats guessing, so this outranks every
# derived signal and — like --project — earns a confident zero. No jq means no
# safe parse, so the derived signals take over rather than a hand-rolled one.
#
# UNTRUSTED INPUT. Unlike --project (supplied by the invoking skill), this file
# is REPO CONTENT: it arrives with a clone, so a hostile or merely broken repo
# controls it. The value is emitted as `PROJECT=` in a KEY=VALUE digest
# (structured-script-output.md), and consumers read that digest line-wise —
# `session-spinup-nudge.sh` does `grep -m1 "^KEY="` — so a value carrying a
# NEWLINE would inject whole fabricated rows (`{"project":"x\nOPEN_TASKS=999"}`
# makes the nudge read 999 open tasks from a line the collector never counted),
# and a non-string `.project` (array/object/number) renders multi-line too.
#
# So: `.project` must be a plain single-line STRING, or the declaration is
# REJECTED — never flattened. Rejecting degrades to the derived signals along
# exactly the path malformed JSON already takes, which keeps the failure mode
# (and its test) singular; flattening would instead emit a garbage slug that
# matches no task and earns a CONFIDENT zero, the very thing #2304 exists to
# stop.
declared_project_of() {  # $1 = directory that may hold .claude/session.json
  local f="$1/.claude/session.json" v
  [ -f "$f" ] || return 1
  have jq || return 1
  v=$(jq -r 'if type == "object" and (.project | type) == "string"
             then (.project // empty) else empty end' "$f" 2>/dev/null) || return 1
  [ -n "$v" ] || return 1
  # Any control character (newline, CR, tab, US, …) can break a row or a
  # column; a taskwarrior project slug never contains one.
  case "$v" in *[[:cntrl:]]*) return 1 ;; esac
  printf '%s' "$v"
}

detection="ambiguous"
repo_root=""
if [ "$in_git" = true ]; then
  repo_root=$("$git_bin" -C "$project_dir" rev-parse --show-toplevel 2>/dev/null || echo "")
fi

if [ -n "$project" ]; then
  detection="override"
else
  # Most specific declaration first: a monorepo subdir may name its own slug.
  declared_project=""
  for decl_dir in "$project_dir" "$repo_root"; do
    [ -n "$decl_dir" ] || continue
    declared_project=$(declared_project_of "$decl_dir") && break
    declared_project=""
  done
  if [ -n "$declared_project" ]; then
    project="$declared_project"
    detection="declared"
  elif [ -n "$repo_root" ]; then
    project=$(basename "$repo_root")
    detection="cwd-repo-basename"
  fi
fi

# ---------------------------------------------------------------------------
# Ancestor repo ROOTS, NEAREST FIRST (#2304). In a portfolio where a nested
# repo's work is filed under the PARENT workspace's slug (the house rule is one
# short slug per long-running area, reused consistently — so eleven sibling
# packs share one backlog), the nested basename matches no task and the survey
# reports an EMPTY answer, which is exactly what "nothing to do here" looks
# like. Walking up finds the slug that actually holds the work.
#
# The walk is bounded three ways so it cannot run away: it never leaves
# $home_dir (or, when that is unset, stops at the filesystem root), every step
# is a strict parent via `dirname`, and a hard iteration cap backstops both.
#
# Emits PATHS rather than basenames because two consumers need it: the
# taskwarrior ladder wants the slug (`ancestor_repo_slugs` below), and the GIT
# workspace-root resolution (#2441) wants the root itself — both to ask git
# whether that outer repo is a DIFFERENT repository and to read state from it.
#
# Defined here rather than beside the taskwarrior ladder because the #2441
# resolution below must run BEFORE the git state read and before the `gh` calls
# are launched, and both of those come first in this file.
# ---------------------------------------------------------------------------
ancestor_repo_roots() {  # $1 = dir to walk up from, $2 = boundary ("" = root)
  local start="$1" boundary="$2" dir root next steps=0
  [ -n "$start" ] || return 0
  have "$git_bin" || return 0
  dir=$(dirname "$start")
  while [ "$steps" -lt 32 ]; do
    steps=$((steps + 1))
    case "$dir" in ""|"."|"/") break ;; esac
    if [ -n "$boundary" ]; then
      # Strictly BELOW the boundary: $HOME itself is not a project workspace,
      # and a dotfiles repo checked out there must not swallow every slug.
      case "$dir" in "$boundary"/*) : ;; *) break ;; esac
    fi
    root=$("$git_bin" -C "$dir" rev-parse --show-toplevel 2>/dev/null || echo "")
    if [ -n "$root" ] && [ "$root" != "$start" ]; then
      # git's own discovery walks upward, so re-apply the boundary to what it
      # found — the walk must not escape $HOME by proxy.
      if [ -n "$boundary" ]; then
        case "$root" in "$boundary"/*) : ;; *) break ;; esac
      fi
      printf '%s\n' "$root"
      next=$(dirname "$root")
    else
      next=$(dirname "$dir")
    fi
    [ "$next" != "$dir" ] || break
    dir="$next"
  done
  return 0
}

# The taskwarrior ladder's view of the same walk: one candidate SLUG per line.
ancestor_repo_slugs() {  # $1 = dir to walk up from, $2 = boundary ("" = root)
  local r
  while IFS= read -r r; do
    [ -n "$r" ] || continue
    basename "$r"
  done < <(ancestor_repo_roots "$1" "$2")
  return 0
}

# A repo's ABSOLUTE common git dir — the discriminator between "a different
# repository contains this one" and "this is a linked worktree of the very repo
# above it" (#2441). Every worktree of one repo shares a common dir; a nested
# clone or a submodule does not. `--git-common-dir` may answer relative to the
# queried directory, so it is resolved before comparing.
git_common_dir_of() {  # $1 = a directory inside a repo
  local d
  have "$git_bin" || return 1
  d=$("$git_bin" -C "$1" rev-parse --git-common-dir 2>/dev/null) || return 1
  [ -n "$d" ] || return 1
  case "$d" in /*) : ;; *) d="$1/$d" ;; esac
  ( cd "$d" 2>/dev/null && pwd -P ) || printf '%s\n' "$d"
}

# Does the OUTER repo know about the inner one? (#2441) A containment the outer
# repo IGNORES via a `.gitignore` (`/*/*` in a portfolio root) or TRACKS (a
# submodule, a committed subtree) is a DECLARED layout: the inner checkout is
# where the work belongs and its git state is the session's, so re-resolving
# out of it would report the wrong repo for every pack in a portfolio. The
# reported case is neither: the nested fork was plain untracked content
# (`?? ComfyUI/`) inside the workspace repo.
#
# The ignore SOURCE decides, not the mere fact of being ignored. `.gitignore`
# is repo content — a layout the repo asserts to everyone who clones it.
# `.git/info/exclude` and a global `core.excludesFile` are private to one
# checkout, and the usual reason a line lands there is to stop an accidental
# nested clone showing up in `git status` — exactly the state this signal
# exists to report. Honouring those would let silencing the symptom silence
# the resolution too. `check-ignore -v` names the source; a path under `.git/`,
# or an absolute/`~` path (a global or system excludes file), is not a
# declaration.
#
# `check-ignore -v` prints `<source>:<line>:<pattern>\t<path>`, so a source path
# containing `:` splits short. Verified both ways: a RELATIVE source under a
# colon-bearing directory (`x:/.gitignore` → `x`) falls through to the declared
# branch, so the checkout is left where it is — the conservative direction now
# that the verdict re-resolves rather than merely flags; an ABSOLUTE one
# (`/home/u:x/.gitignore` → `/home/u`) still matches `/*` and reads undeclared,
# which is the correct verdict for a global excludes file. Untested against a
# real repo; a `:` in a gitignore path is pathological either way.
outer_repo_declares() {  # $1 = outer repo root, $2 = inner repo root
  local why src
  why=$("$git_bin" -C "$1" check-ignore -v -- "$2" 2>/dev/null) || why=""
  if [ -n "$why" ]; then
    src="${why%%:*}"
    case "$src" in
      .git/*|/*|"~"*) : ;;
      *) return 0 ;;
    esac
  fi
  "$git_bin" -C "$1" ls-files --error-unmatch -- "$2" >/dev/null 2>&1 && return 0
  return 1
}

# A directory name is filesystem content, so it is sanitised before it becomes
# a KEY=VALUE row. Stricter than the gh-stderr snippet's class (which keeps
# TAB/LF because a following `head -1` bounds it): here every control byte goes
# — DEL included — since nothing downstream re-bounds the value.
sanitize_name() {  # $1 = a directory path; prints its bounded basename
  basename "$1" | tr -d '\000-\037\177' | cut -c1-200
}

# Physical paths on both sides, so the boundary test is a plain prefix compare
# even when $TMPDIR / $HOME reach the tree through a symlink.
walk_start="${repo_root:-$project_dir}"
walk_start=$(cd "$walk_start" 2>/dev/null && pwd -P) || walk_start="${repo_root:-$project_dir}"
[ -n "$walk_start" ] || walk_start="${repo_root:-$project_dir}"
home_boundary=""
if [ -n "$home_dir" ]; then
  home_boundary=$(cd "$home_dir" 2>/dev/null && pwd -P) || home_boundary="$home_dir"
  [ -n "$home_boundary" ] || home_boundary="$home_dir"
fi

# ---------------------------------------------------------------------------
# Which repository do GIT and PRS describe? (#2441)
#
# Both sections read the repo at $project_dir — GIT directly, PRS because every
# `gh` call is launched with that cwd, so `gh` resolves the repo from the same
# checkout's remote. When the cwd lands inside a NESTED checkout (the reported
# shape: an untracked upstream fork living inside the workspace repo), those two
# sections describe a DIFFERENT repository's branch, dirt and PRs, and the
# digest said nothing.
#
# So GIT and PRS are RESOLVED FROM THE WORKSPACE ROOT rather than merely
# flagged: the issue's own preferred remedy, and the one that keeps the digest's
# sections describing one repository instead of asking the consumer to reconcile
# them. The walk is the #2304 ancestor walk, reused rather than duplicated.
#
# Two containments are deliberately NOT re-resolved, because in both the
# checkout at the cwd IS the session's repo and stepping out of it would report
# the wrong one:
#
#   - a linked worktree, which lives inside its own main checkout and shares its
#     common dir (every worktree-isolated agent is this shape);
#   - a declared containment — the outer repo ignores it via `.gitignore` or
#     tracks it — which is how a portfolio root holds its packs.
#
#   none            not in a git repo at all (IN_GIT=false / GH_READY=false)
#   repo            the checkout at PROJECT_DIR is the repo described
#   workspace-root  an undeclared outer repo contains this checkout, so GIT and
#                   PRS describe THAT repo (GIT_ROOT=), not the nested one
#                   (GIT_NESTED_REPO=)
#
# The taskwarrior half is untouched: PROJECT / TASK_SCOPE / PROJECT_CONFIDENCE
# keep their own ladder and their own vocabulary.
# ---------------------------------------------------------------------------
git_scope="repo"
git_confidence="high"
git_nested_repo=""
git_root=""
# The directory GIT reads and `gh` runs in. Defaults to the cwd's checkout.
git_state_dir="$project_dir"

if [ "$in_git" != true ]; then
  git_scope="none"
  git_confidence="low"
else
  # The taskwarrior walk stops at $HOME because a dotfiles repo checked out
  # THERE must not swallow every slug. That reasoning is about slug adoption,
  # not about nesting: a workspace living outside $HOME (the reported case was
  # /mnt/sabrent/comfyui-workspace) is nested exactly as much as one inside it,
  # and the boundary would silently make the check a no-op there. So the bound
  # applies only where it means something — when the checkout is under $HOME.
  # The walk stops at the FIRST outer repo either way, and the 32-step cap
  # still backstops it.
  git_walk_boundary="$home_boundary"
  if [ -n "$home_boundary" ]; then
    case "$walk_start" in "$home_boundary"/*) : ;; *) git_walk_boundary="" ;; esac
  fi

  git_outer_root=""
  own_common=$(git_common_dir_of "$walk_start" 2>/dev/null) || own_common=""
  while IFS= read -r outer_root; do
    [ -n "$outer_root" ] || continue
    outer_common=$(git_common_dir_of "$outer_root" 2>/dev/null) || outer_common=""
    # Cannot ask, so do not move the answer. `--git-common-dir` predates git 2.5
    # and a damaged repo can fail it; both probes run the same binary, so a git
    # that cannot answer for the outer repo cannot answer for this checkout
    # either and every candidate is skipped — no re-resolution, the checkout is
    # left where it is. That degradation is conservative now that the verdict
    # RE-RESOLVES rather than merely flags; under the earlier flag-only design
    # the same silence was a missed caveat. Pinned by AP8c.
    [ -n "$outer_common" ] || continue
    # A linked worktree lives inside its own main checkout and shares its
    # common dir. That is not a nested repository, and re-resolving would make
    # every worktree-isolated agent report its main checkout's state. `continue`
    # rather than `break`: the main checkout is the SAME repo, so a container of
    # IT is still a container of this session's repo and is worth finding.
    [ "$outer_common" != "$own_common" ] || continue
    # A declared containment (ignored or tracked) SETTLES it: the outer repo
    # asserts this checkout is a legitimate member of its layout, so the
    # checkout is the session's repo and there is nothing to resolve.
    #
    # End the walk rather than skipping a rung. `continue` here would let a
    # FURTHER-OUT repo that happens not to declare the checkout become the
    # target — reported live on `outer/mid/sub` where `mid` tracks `sub/`:
    # `mid` declared it, the walk continued, and `outer` (which declares
    # nothing) was resolved to, so the digest carried `outer`'s branch for a
    # session sitting two levels in. That is #2441's own failure aimed outward.
    if outer_repo_declares "$outer_root" "$walk_start"; then
      git_outer_root=""
      break
    fi
    git_outer_root="$outer_root"
    break
  done < <(ancestor_repo_roots "$walk_start" "$git_walk_boundary")

  if [ -n "$git_outer_root" ]; then
    git_scope="workspace-root"
    # `low`, not `high`: re-resolving is a judgement that the session's work
    # belongs to the workspace rather than the nested checkout. It is the right
    # default — the reported session had been working under ComfyUI/output and
    # wanted the workspace's state — but a session genuinely working IN the
    # nested fork is served the outer repo, so the rows stay a caveat.
    git_confidence="low"
    git_nested_repo=$(sanitize_name "$walk_start")
    git_root=$(sanitize_name "$git_outer_root")
    git_state_dir="$git_outer_root"
  fi
fi

# ---------------------------------------------------------------------------
# Counts (filled below; surfaced in both summary and full mode).
# ---------------------------------------------------------------------------
dirty=false
unpushed=0
behind=0
open_tasks=0
active_tasks=0
assigned_issues=0
drift_issues=0
journal_todos=0
pr_count=0
recent_task_count=0

# Git state. Read from $git_state_dir, which is $project_dir except on the
# `workspace-root` rung, where an undeclared outer repo contains this checkout
# and the digest describes THAT repo instead (#2441).
git_branch=""
if [ "$in_git" = true ]; then
  git_branch=$("$git_bin" -C "$git_state_dir" branch --show-current 2>/dev/null || echo "")
  [ -n "$("$git_bin" -C "$git_state_dir" status --porcelain 2>/dev/null | head -1)" ] && dirty=true
  # awk, not `grep -c '' || echo 0`: on a branch with no upstream `git log`
  # fails, grep -c prints 0 AND exits 1, so the `|| echo 0` ALSO ran and
  # UNPUSHED became the two-line value "0\n0" — breaking the KEY=VALUE
  # contract and making the -gt test below an unconditional false.
  unpushed=$("$git_bin" -C "$git_state_dir" log '@{u}..HEAD' --oneline 2>/dev/null | awk 'END{print NR+0}')
  [ -n "$unpushed" ] || unpushed=0
  # How far HEAD TRAILS upstream (#2500). Without it the digest reported every
  # direction except behind, so a checkout three commits stale read as settled
  # and every finding measured against it was measured against a stale basis.
  # `@{upstream}` rather than a hardcoded origin/main: it resolves per branch
  # and simply fails (exit non-zero, nothing on stdout, stderr suppressed) on a
  # branch with no upstream or a detached HEAD — the same posture UNPUSHED
  # takes. Piped into awk for the same reason UNPUSHED is, NOT `|| echo 0`: a
  # fallback after a command that can both print and fail yields a TWO-LINE
  # value and breaks the KEY=VALUE contract (the #2286 trap).
  behind=$("$git_bin" -C "$git_state_dir" rev-list --count 'HEAD..@{upstream}' 2>/dev/null \
    | awk '{n=$1} END{print n+0}')
  [ -n "$behind" ] || behind=0
fi

# The git remote's repo name — a second, cheap (local, no network) candidate
# for the taskwarrior project slug, consulted only when the basename matches
# nothing (#2271). Read from $project_dir, NOT $git_state_dir: this is an
# alternate spelling of the DETECTED slug, which the taskwarrior ladder derives
# from the cwd's own checkout, so the #2441 workspace-root resolution must not
# reach it.
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
#
# A bare `GH_READY=false` is undiagnosable, though — a transient 5xx, an expired
# token, a repo with no GitHub remote, and a budget kill all want DIFFERENT
# responses (#2425). Each call's rc and stderr are therefore kept and collapsed
# into one `GH_FAIL_REASON=` alongside the `false`.
# ---------------------------------------------------------------------------
gh_dir=""
gh_pids=()
# Job names actually launched. A job that was never launched has no rc and no
# stderr, so it must not be classified as a failure (#2425) — summary mode, for
# instance, deliberately skips the PR calls.
gh_launched=()
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
#
# Stderr is CAPTURED, not discarded (#2425): it is the only thing that tells a
# transient 5xx apart from an expired token or a repo with no GitHub remote,
# and `GH_READY=false` alone left the consumer unable to pick a remedy.
gh_job() {
  local job_name="$1"; shift
  [ -n "$gh_dir" ] || return 0
  gh_launched+=("$job_name")
  (
    ( cd "$git_state_dir" && "$gh_bin" "$@" ) \
      >"$gh_dir/$job_name.json" 2>"$gh_dir/$job_name.err" &
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

# First stderr line of a failed job, sanitised for the KEY=VALUE contract: a
# control character would break the row (structured-script-output.md), and an
# unbounded value would swamp the digest.
gh_err_head() {
  local f
  [ -n "$gh_dir" ] || return 0
  f="$gh_dir/$1.err"
  [ -s "$f" ] || return 0
  head -1 "$f" 2>/dev/null | tr -d '\000-\010\013-\037' | cut -c1-200
}

# Classify ONE failed gh invocation into an actionable reason. Order matters:
# gh's "no GitHub remote" message ALSO says `gh auth login`, so the remote test
# must run before the auth test or every remote-less repo reads as `auth`.
# Matching uses a here-string, never a pipe — a `grep -q` that closes the pipe
# early makes `pipefail` report the pipeline non-zero (the #1744 SIGPIPE race).
gh_classify() {
  local job="$1" rc err
  rc="$(gh_rc_of "$job")"
  case "$rc" in
    missing) printf '%s' "no-cli"; return 0 ;;
    # 128+SIGTERM / 128+SIGKILL — the watchdog cut the call off.
    137|143) printf '%s' "timeout"; return 0 ;;
  esac
  err="$(gh_err_head "$job")"
  if grep -Eqi 'none of the git remotes|no git remotes|not a git repository|no remotes? (found|configured)' <<<"$err"; then
    printf '%s' "no-remote"
  elif grep -Eqi 'not logged in|auth login|authentication token|missing required scopes|bad credentials|HTTP 40[13]|GH_TOKEN|GITHUB_TOKEN' <<<"$err"; then
    printf '%s' "auth"
  elif grep -Eqi 'HTTP [45][0-9][0-9]|GraphQL|error connecting|connection refused|could not resolve host|dial tcp|timeout|TLS|certificate' <<<"$err"; then
    printf '%s' "api-error"
  else
    printf '%s' "unknown"
  fi
}

# Precedence when several jobs failed differently: the reason whose remedy is
# most specific wins. `auth` first because re-running is futile; `unknown` last.
gh_reason_rank() {
  case "$1" in
    auth) printf '%s' 1 ;;
    no-remote) printf '%s' 2 ;;
    no-cli) printf '%s' 3 ;;
    timeout) printf '%s' 4 ;;
    api-error) printf '%s' 5 ;;
    *) printf '%s' 6 ;;
  esac
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
  # The summary PRINTS GH_READY and ASSIGNED_ISSUES, so it must actually ask —
  # otherwise both keys are a fabricated zero in a mode nobody gated them on.
  if [ "$with_dedup" = true ] || [ "$summary_mode" = true ]; then
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

# Scope the snapshot to a project the way `task project:<p>` would: taskwarrior
# projects are a DOT-SEPARATED HIERARCHY and `project:bluepad32` matches
# `bluepad32` AND every `bluepad32.<sub>`. Exact equality here silently dropped
# every subproject task from the scope — which, in the fallback shape, meant a
# task modified outside --recent-days vanished from the digest entirely.
# `bluepad32-extra` is NOT a subproject: only a literal `.` separates levels.
scope_of() {
  printf '%s' "$all_tasks_json" \
    | jq -c --arg p "$1" '[.[]
        | (.project // "") as $tp
        | select($tp == $p or ($tp | startswith($p + ".")))]' 2>/dev/null || echo "[]"
}

# The same hierarchy predicate in shell, for the cross-project +ACTIVE footnote:
# a subproject task counted inside the scope must not ALSO be reported as
# "+ACTIVE elsewhere".
in_project_scope() {  # $1 = a task's project, $2 = the scope project
  [ -n "$2" ] || return 1
  [ "$1" = "$2" ] && return 0
  [ "${1#"$2".}" != "$1" ]
}

tasks_all=0
project_tasks_json="[]"
active_all_json="[]"
task_scope="project"
project_confidence="high"
project_resolved=""
project_ambiguous=""
project_ambiguous_tasks=0
# Which rung named it: `ancestor` (#2304) or `separator-variant` (#2355). The
# consumer's phrasing differs — "the workspace above holds N" vs "a slug spelled
# with other separators holds N" — so the slug alone is not enough.
project_ambiguous_reason=""
# The prefix-sibling split (#2323). Integers so consumers can do arithmetic on
# them unconditionally, exactly like OPEN_TASKS — the "was this even queried"
# question is answered by TASK_SCOPE (`none`/`unknown`), not by a sentinel here.
project_exact_tasks=0
prefix_siblings=""
prefix_sibling_tasks=0

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
  # slug is suspect. An explicit --project — or a slug the repo DECLARED — is
  # user-asserted, so it keeps its confident zero and is never rewritten. It
  # still gets the ancestor probe, because a zero that hides a real backlog is
  # the failure this whole ladder exists to prevent (#2304).
  if [ "${open_tasks:-0}" -eq 0 ] && [ "${tasks_all:-0}" -gt 0 ]; then
    asserted=false
    case "$detection" in override|declared) asserted=true ;; esac

    alt_json="[]"
    alt_n=0
    if [ "$asserted" = false ] && [ -n "$project_remote_name" ] \
       && [ "$project_remote_name" != "$project" ]; then
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
      project_confidence="low"
    else
      # (2) #2304: the nearest ANCESTOR repo whose slug holds tasks — the
      # nested-pack-under-a-workspace shape. Probed even for a user-asserted
      # slug: the adoption is suppressed there, the ambiguity signal is not.
      anc_slug=""
      anc_json="[]"
      anc_n=0
      while IFS= read -r anc_cand; do
        [ -n "$anc_cand" ] || continue
        [ "$anc_cand" != "$project" ] || continue
        cand_json=$(scope_of "$anc_cand")
        [ -n "$cand_json" ] || cand_json="[]"
        cand_n=$(printf '%s' "$cand_json" | jq 'length' 2>/dev/null || echo 0)
        [ -n "$cand_n" ] || cand_n=0
        if [ "$cand_n" -gt 0 ] 2>/dev/null; then
          anc_slug="$anc_cand"
          anc_json="$cand_json"
          anc_n="$cand_n"
          break
        fi
      done < <(ancestor_repo_slugs "$walk_start" "$home_boundary")

      if [ "${anc_n:-0}" -gt 0 ] && [ "$detection" = "cwd-repo-basename" ]; then
        detection="cwd-repo-basename-ancestor"
        task_scope="ancestor-name"
        project="$anc_slug"
        project_resolved="$anc_slug"
        project_tasks_json="$anc_json"
        open_tasks="$anc_n"
        project_confidence="low"
      else
        if [ "${anc_n:-0}" -gt 0 ]; then
          # (3) A zero we are not allowed to adopt away must never look
          # authoritative: name the ancestor slug that does hold the work, so
          # session-end can say "0 here, N under <slug>" instead of skipping.
          project_ambiguous="$anc_slug"
          project_ambiguous_tasks="$anc_n"
          project_ambiguous_reason="ancestor"
        else
          # (3b) #2355: a REAL slug differing from the detected one only by
          # SEPARATOR CHARACTER (or case). The reported shape: the repo is
          # `fvh-cost-attribution` (basename AND git remote name agree) while
          # the taskwarrior project holding the backlog is
          # `fvh.cost-attribution`. It is no ancestor of the cwd, so (3) cannot
          # see it, and it is not a prefix of the detected slug, so the
          # prefix-sibling split below cannot either — yet the two names differ
          # by one character class, which is enough to say so.
          #
          # The fold REPLACES each separator with one canonical character
          # rather than deleting it, so `ab` and `a-b` stay distinct. Ranked
          # only behind the ancestor: a containing workspace is a stronger
          # claim than a name collision. Candidates come from the ONE snapshot
          # already in hand — no second `task ... export`
          # (parallel-safe-queries.md).
          sep_slug=""
          sep_n=0
          if [ -n "$project" ]; then
            while IFS= read -r sep_cand; do
              [ -n "$sep_cand" ] || continue
              # A slug is store content; a control character in one would break
              # a KEY=VALUE row. Real taskwarrior slugs never contain one.
              case "$sep_cand" in *[[:cntrl:]]*) continue ;; esac
              cand_json=$(scope_of "$sep_cand")
              [ -n "$cand_json" ] || cand_json="[]"
              cand_n=$(printf '%s' "$cand_json" | jq 'length' 2>/dev/null || echo 0)
              [ -n "$cand_n" ] || cand_n=0
              if [ "$cand_n" -gt 0 ] 2>/dev/null; then
                sep_slug="$sep_cand"
                sep_n="$cand_n"
                break
              fi
            done < <(printf '%s' "$all_tasks_json" | jq -r --arg p "$project" '
              def norm: ascii_downcase | gsub("[._-]"; "-");
              ($p | norm) as $np
              | [ .[] | (.project // "")
                  | select(. != "" and . != $p and (norm == $np)) ]
              | unique | .[]' 2>/dev/null)
          fi
          if [ "${sep_n:-0}" -gt 0 ]; then
            project_ambiguous="$sep_slug"
            project_ambiguous_tasks="$sep_n"
            project_ambiguous_reason="separator-variant"
          fi
        fi
        if [ "$asserted" = false ]; then
          # (4) #2232: no single slug wins (portfolio checkout, renamed dir, …).
          # Widen, and make the widening visible rather than reporting a clean 0.
          task_scope="all-projects-fallback"
          project_confidence="low"
        fi
      fi
    fi
  fi

  active_all_json=$(printf '%s' "$all_tasks_json" \
    | jq -c '[.[] | select((.tags // []) | index("ACTIVE"))]' 2>/dev/null || echo "[]")
  [ -n "$active_all_json" ] || active_all_json="[]"
  active_tasks=$(printf '%s' "$project_tasks_json" \
    | jq '[.[] | select((.tags // []) | index("ACTIVE"))] | length' 2>/dev/null || echo 0)
  [ -n "$active_tasks" ] || active_tasks=0

  # -------------------------------------------------------------------------
  # Prefix-sibling split (#2323).
  #
  # `scope_of` is a HIERARCHY match — the slug itself plus its `.`-separated
  # children — which is NARROWER than the taskwarrior CLI's `project:<p>`
  # filter. That one is a PREFIX match, so `task project:comfyui list` also
  # returns every `comfyui-nodes` task. Verifying a slug that way confirms
  # nothing: the wrong slug reports a full backlog, and follow-ups then land in
  # a near-empty sibling nobody reads. PROJECT_CONFIDENCE alone cannot see this
  # — it answers "is the DETECTED slug trustworthy?", not "do these tasks
  # actually carry it?" — and a prefix hit makes the two look like one question.
  #
  # Three numbers keep the split legible instead of collapsing it:
  #   OPEN_TASKS                   this scope: the slug + its `.` subprojects
  #   PROJECT_EXACT_TASKS          the slug ALONE, `.project == <slug>`
  #   PROJECT_PREFIX_SIBLING_TASKS what a CLI prefix filter would ALSO sweep in
  #   PROJECT_PREFIX_SIBLINGS      and the slugs it would sweep in from
  #
  # Computed against the slug OPEN_TASKS was actually counted under — the
  # remote-name / ancestor-name rungs above may have resolved away from the
  # detected basename.
  scope_slug="${project_resolved:-$project}"
  if [ -n "$scope_slug" ]; then
    project_exact_tasks=$(printf '%s' "$all_tasks_json" \
      | jq --arg p "$scope_slug" '[.[] | select((.project // "") == $p)] | length' \
        2>/dev/null || echo 0)
    [ -n "$project_exact_tasks" ] || project_exact_tasks=0

    # A slug that STARTS WITH the scope slug but is neither it nor one of its
    # `.` children: precisely the set the CLI prefix filter over-collects.
    # Slugs are store content, so they get the same row/column sanitiser every
    # other projected field gets; the list is capped so one pathological store
    # cannot produce an unbounded KEY=VALUE line.
    sibling_row=$(printf '%s' "$all_tasks_json" | jq -r --arg p "$scope_slug" --arg us "$US" '
      [ .[] | (.project // "")
        | select(. != "" and startswith($p) and . != $p and (startswith($p + ".") | not)) ]
      | [ (length | tostring),
          ( unique | .[0:8] | map(gsub("[\t\r\n,]";" ")) | join(",") )
        ] | join($us)' 2>/dev/null || echo "")
    if [ -n "$sibling_row" ]; then
      IFS="$US" read -r prefix_sibling_tasks prefix_siblings <<< "$sibling_row"
    fi
    case "${prefix_sibling_tasks:-}" in ''|*[!0-9]*) prefix_sibling_tasks=0 ;; esac

    # The sibling set holds MORE tasks than the detected scope: the prefix hit,
    # not the slug, is what the backlog is under. Say so rather than letting a
    # misfiled backlog read as a verified one. Deliberately applies to an
    # asserted slug too (--project / a repo declaration): assertion fixes the
    # slug's IDENTITY, it cannot assert what the store holds — and the reported
    # case was a slug asserted in CLAUDE.md on exactly this evidence. Nothing is
    # adopted or rewritten here; only the flag drops and the siblings are named.
    if [ "$prefix_sibling_tasks" -gt "${open_tasks:-0}" ] 2>/dev/null; then
      project_confidence="low"
    fi
  fi
fi

# Recent-task fallback — only in all-projects-fallback, so the normal path
# gains no noise.
#
# This runs in the SessionStart hook path (#2276), over the WHOLE all-projects
# store, so it must not fork per task. Two properties keep it flat:
#   1. The window test is a STRING compare against a cutoff stamp computed ONCE.
#      Taskwarrior's compact stamp (YYYYMMDDTHHMMSSZ) is lexicographically
#      ordered, so this is exact — and days_since() (which forks `date`) is
#      called only for the <=10 rows actually emitted.
#   2. The feeding jq is already `sort_by(.modified) | reverse`, so the first
#      out-of-window row ends the scan (`break`, not `continue`).
# The cutoff is `now - (recent_days + 1) days`, exclusive: identical to the
# floor-division `days_since <= recent_days` test it replaces.
recent_uuids=()
recent_projects=()
recent_descs=()
recent_ages=()
recent_truncated=false
if [ "$task_scope" = "all-projects-fallback" ] && have jq; then
  cutoff_epoch=$(( now_epoch - (recent_days + 1) * 86400 ))
  cutoff_stamp=$(date -u -d "@$cutoff_epoch" +%Y%m%dT%H%M%SZ 2>/dev/null \
    || date -u -r "$cutoff_epoch" +%Y%m%dT%H%M%SZ 2>/dev/null || echo "")
  while IFS="$US" read -r r_uuid r_proj r_desc r_mod; do
    [ -n "$r_uuid" ] || continue
    case "$r_mod" in
      [0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]T[0-9][0-9][0-9][0-9][0-9][0-9]Z)
        # Comparable stamp: a row at or before the cutoff ends the scan.
        if [ -n "$cutoff_stamp" ]; then
          [ "$r_mod" '>' "$cutoff_stamp" ] || break
        else
          r_age=$(days_since "$r_mod" 2>/dev/null || echo "")
          [ -n "$r_age" ] || continue
          [ "$r_age" -le "$recent_days" ] 2>/dev/null || break
        fi
        ;;
      # A stamp we cannot order (empty / foreign format) is skipped, never
      # treated as the end of the window.
      *) continue ;;
    esac
    recent_task_count=$((recent_task_count + 1))
    if [ "$recent_task_count" -le 10 ]; then
      # The ONLY days_since() (and therefore `date`) call in this loop, and it
      # runs at most 10 times regardless of store size.
      r_age=$(days_since "$r_mod" 2>/dev/null || echo "")
      recent_uuids+=("$r_uuid")
      recent_projects+=("$r_proj")
      recent_descs+=("$r_desc")
      recent_ages+=("$r_age")
    else
      recent_truncated=true
    fi
  done < <(printf '%s' "$all_tasks_json" | jq -r --arg us "$US" '
    sort_by(.modified // .entry // "") | reverse | .[]
    | [ .uuid,
        (.project // ""),
        (.description | gsub("[\t\r\n\u001f]";" ")),
        (.modified // .entry // "")
      ] | join($us)' 2>/dev/null)
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

  # Reason code (#2425). Emitted only alongside GH_READY=false — a partial
  # failure that still yielded data is not an unqueried GitHub. With no job
  # launched at all the cause is the gh CLI itself, not any one call.
  if [ "$gh_ready" = false ]; then
    if [ "${#gh_launched[@]}" -eq 0 ]; then
      gh_fail_reason="no-cli"
    else
      local reason rank best_rank=99
      for job in "${gh_launched[@]}"; do
        reason="$(gh_classify "$job")"
        rank="$(gh_reason_rank "$reason")"
        if [ "$rank" -lt "$best_rank" ] 2>/dev/null; then
          best_rank="$rank"
          gh_fail_reason="$reason"
          # The snippet is what makes an opaque classification actionable, so
          # it rides along only where the reason alone says nothing useful.
          case "$reason" in
            api-error|unknown) gh_fail_detail="$(gh_err_head "$job")" ;;
            *) gh_fail_detail="" ;;
          esac
        fi
      done
    fi
    [ -n "$gh_fail_reason" ] || gh_fail_reason="unknown"
  fi

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

  # The assigned-issue count is available whenever the issues query itself
  # succeeded — it does not depend on the dedup pass below.
  if [ "$issues_ok" = 0 ] && have jq; then
    assigned_issues=$(printf '%s' "$assigned_json" | jq 'length' 2>/dev/null || echo 0)
    [ -n "$assigned_issues" ] || assigned_issues=0
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
# Why GitHub was not queried (#2425): timeout | auth | no-remote | api-error |
# no-cli | unknown. Present only when GH_READY=false. GH_FAIL_DETAIL carries the
# first stderr line for the two classifications the reason alone cannot act on.
gh_fail_reason=""
gh_fail_detail=""
prs_json="[]"
drift_json="[]"

compute_threads() {
  threads=0
  [ "$dirty" = true ] && threads=$((threads + 1))
  [ "${unpushed:-0}" -gt 0 ] 2>/dev/null && threads=$((threads + 1))
  [ "${open_tasks:-0}" -gt 0 ] 2>/dev/null && threads=$((threads + open_tasks))
  [ "${recent_task_count:-0}" -gt 0 ] 2>/dev/null && threads=$((threads + recent_task_count))
  [ "${drift_issues:-0}" -gt 0 ] 2>/dev/null && threads=$((threads + drift_issues))
  [ "${journal_todos:-0}" -gt 0 ] 2>/dev/null && threads=$((threads + journal_todos))
  return 0
}

# ---------------------------------------------------------------------------
# Summary mode — coarse counts only, for the SessionStart nudge hook.
#
# Same ordering contract as the full digest (#2276): every no-network key is
# written BEFORE the GitHub wait, so a hard kill at the hook's timeout
# truncates this block rather than producing nothing at all.
# ---------------------------------------------------------------------------
if [ "$summary_mode" = true ]; then
  echo "=== SESSION SURVEY SUMMARY ==="
  echo "PROJECT=${project}"
  echo "DETECTION=${detection}"
  echo "TASK_SCOPE=${task_scope}"
  echo "PROJECT_CONFIDENCE=${project_confidence}"
  [ -n "$project_resolved" ] && echo "PROJECT_RESOLVED=${project_resolved}"
  [ -n "$project_ambiguous" ] && echo "PROJECT_AMBIGUOUS=${project_ambiguous}"
  [ -n "$project_ambiguous" ] && echo "PROJECT_AMBIGUOUS_TASKS=${project_ambiguous_tasks}"
  [ -n "$project_ambiguous" ] && echo "PROJECT_AMBIGUOUS_REASON=${project_ambiguous_reason}"
  [ -n "$prefix_siblings" ] && echo "PROJECT_PREFIX_SIBLINGS=${prefix_siblings}"
  [ -n "$prefix_siblings" ] && echo "PROJECT_PREFIX_SIBLING_TASKS=${prefix_sibling_tasks}"
  echo "DIRTY=${dirty}"
  echo "UNPUSHED=${unpushed}"
  echo "BEHIND=${behind}"
  echo "GIT_SCOPE=${git_scope}"
  echo "GIT_CONFIDENCE=${git_confidence}"
  [ -n "$git_root" ] && echo "GIT_ROOT=${git_root}"
  [ -n "$git_nested_repo" ] && echo "GIT_NESTED_REPO=${git_nested_repo}"
  echo "OPEN_TASKS=${open_tasks}"
  echo "PROJECT_EXACT_TASKS=${project_exact_tasks}"
  echo "RECENT_TASK_COUNT=${recent_task_count}"
  [ -n "$recent_days_invalid" ] && echo "RECENT_DAYS_INVALID=${recent_days_invalid}"
  [ -n "$gh_budget_invalid" ] && echo "GH_BUDGET_INVALID=${gh_budget_invalid}"
  # Network last.
  reap_github
  compute_threads
  echo "GH_READY=${gh_ready}"
  [ -n "$gh_fail_reason" ] && echo "GH_FAIL_REASON=${gh_fail_reason}"
  [ -n "$gh_fail_detail" ] && echo "GH_FAIL_DETAIL=${gh_fail_detail}"
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
# A CAVEAT, not an error (#2500): BEHIND>0 says "anything measured here was
# measured against a stale basis", the way PROJECT_CONFIDENCE=low does — it
# never flips STATUS, and it is emitted unconditionally so the section shape
# does not depend on the repo state.
echo "BEHIND=${behind}"
# WHICH repository the rows above describe (#2441). `repo` is the checkout at
# PROJECT_DIR. `workspace-root` means an undeclared outer repo contains that
# checkout, so the rows describe the OUTER repo — GIT_ROOT= names it and
# GIT_NESTED_REPO= names the nested checkout that was stepped out of. A caveat,
# not an error: STATUS stays OK, exactly as it does for BEHIND (#2500) and
# PROJECT_CONFIDENCE=low.
echo "GIT_SCOPE=${git_scope}"
echo "GIT_CONFIDENCE=${git_confidence}"
# Both present only on the `workspace-root` rung.
[ -n "$git_root" ] && echo "GIT_ROOT=${git_root}"
[ -n "$git_nested_repo" ] && echo "GIT_NESTED_REPO=${git_nested_repo}"
echo "STATUS=OK"
echo "=== END GIT ==="

echo "=== TASKWARRIOR ==="
echo "TASK_AVAILABLE=${task_available}"
echo "OPEN_TASKS=${open_tasks}"
# The slug ALONE, without its `.` subprojects — OPEN_TASKS' exact-equality half.
echo "PROJECT_EXACT_TASKS=${project_exact_tasks}"
echo "ACTIVE_TASKS=${active_tasks}"
echo "TASK_SCOPE=${task_scope}"
echo "PROJECT_CONFIDENCE=${project_confidence}"
echo "TASKS_ALL_PROJECTS=${tasks_all}"
[ -n "$project_remote_name" ] && echo "PROJECT_REMOTE_NAME=${project_remote_name}"
[ -n "$project_resolved" ] && echo "PROJECT_RESOLVED=${project_resolved}"
# The honest zero's escape hatch: 0 here, but N under this other slug — an
# ancestor workspace (#2304) or a separator/case variant of the detected name
# (#2355). PROJECT_AMBIGUOUS_REASON says which, so the consumer can phrase it.
[ -n "$project_ambiguous" ] && echo "PROJECT_AMBIGUOUS=${project_ambiguous}"
[ -n "$project_ambiguous" ] && echo "PROJECT_AMBIGUOUS_TASKS=${project_ambiguous_tasks}"
[ -n "$project_ambiguous" ] && echo "PROJECT_AMBIGUOUS_REASON=${project_ambiguous_reason}"
# The CLI-prefix over-collection (#2323): slugs a `task project:<slug>` filter
# would ALSO have swept in, and how many tasks they hold. Present only when the
# store actually has such siblings.
[ -n "$prefix_siblings" ] && echo "PROJECT_PREFIX_SIBLINGS=${prefix_siblings}"
[ -n "$prefix_siblings" ] && echo "PROJECT_PREFIX_SIBLING_TASKS=${prefix_sibling_tasks}"
echo "RECENT_TASK_COUNT=${recent_task_count}"
echo "RECENT_DAYS=${recent_days}"
[ -n "$recent_days_invalid" ] && echo "RECENT_DAYS_INVALID=${recent_days_invalid}"
if have jq && [ "$open_tasks" -gt 0 ] 2>/dev/null; then
  idx=0
  while IFS="$US" read -r uuid desc active modified annot ghid; do
    idx=$((idx + 1))
    sd=$(days_since "$modified" 2>/dev/null || echo "")
    echo "TASK_${idx}_UUID=${uuid}"
    echo "TASK_${idx}_ACTIVE=${active}"
    echo "TASK_${idx}_DESC=${desc}"
    [ -n "$sd" ] && echo "TASK_${idx}_STALE_DAYS=${sd}"
    [ -n "$annot" ] && [ "$annot" != "null" ] && echo "TASK_${idx}_ANNOT=${annot}"
    [ -n "$ghid" ] && [ "$ghid" != "null" ] && echo "TASK_${idx}_GHID=${ghid}"
  done < <(printf '%s' "$project_tasks_json" | jq -r --arg us "$US" '
    .[] | [ .uuid,
            (.description | gsub("[\t\r\n\u001f]";" ")),
            (((.tags // []) | index("ACTIVE")) != null),
            (.modified // ""),
            ((.annotations // []) | map(.description) | join(" | ") | gsub("[\t\r\n\u001f]";" ")),
            (.ghid // "")
          ] | join($us)' 2>/dev/null)
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
  # Reads $project_dir, not $git_state_dir: the #2441 workspace-root resolution
  # was scoped to GIT and PRS, so on that rung COMMITS still lists the nested
  # checkout's log while GIT describes the outer repo. Tracked, not fixed here.
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
  # Reads $project_dir, not $git_state_dir — same scoping as COMMITS above, and
  # the same consequence on the `workspace-root` rung: the tracker read is the
  # nested checkout's while GIT describes the outer repo (#2441 was scoped to
  # GIT and PRS). Tracked, not fixed here.
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
  # "Elsewhere" means outside the scope the counts above used — so a subproject
  # (bluepad32.own under bluepad32) and a remote-resolved slug are both already
  # in scope and must not be double-reported here.
  scope_project="${project_resolved:-$project}"
  while IFS="$US" read -r uuid eproj edesc; do
    [ -n "$uuid" ] || continue
    in_project_scope "$eproj" "$scope_project" && continue
    elsewhere_count=$((elsewhere_count + 1))
    echo "STALE_${elsewhere_count}_UUID=${uuid}"
    echo "STALE_${elsewhere_count}_PROJECT=${eproj}"
    echo "STALE_${elsewhere_count}_DESC=${edesc}"
  done < <(printf '%s' "$active_all_json" | jq -r --arg us "$US" \
    '.[] | [ .uuid, (.project // ""), (.description | gsub("[\t\r\n\u001f]";" ")) ] | join($us)' 2>/dev/null)
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
[ -n "$gh_fail_reason" ] && echo "GH_FAIL_REASON=${gh_fail_reason}"
[ -n "$gh_fail_detail" ] && echo "GH_FAIL_DETAIL=${gh_fail_detail}"
[ "$gh_timeout" = true ] && echo "GH_TIMEOUT=true"
echo "GH_BUDGET=${gh_budget}"
[ -n "$gh_budget_invalid" ] && echo "GH_BUDGET_INVALID=${gh_budget_invalid}"
# `gh` runs with $git_state_dir as its cwd — the same directory the GIT section
# reads — so it resolves the repo from that checkout's remote and the PR rows
# describe the same repository GIT_SCOPE names (#2441). A call that never landed
# is its own `none` rung, for the same reason TASK_SCOPE=none exists: an
# unqueried zero is not a zero.
if [ "$gh_ready" != true ]; then
  prs_scope="none"
  prs_confidence="low"
else
  prs_scope="$git_scope"
  prs_confidence="$git_confidence"
fi
echo "PRS_SCOPE=${prs_scope}"
echo "PRS_CONFIDENCE=${prs_confidence}"
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
  [ -n "$gh_fail_reason" ] && echo "GH_FAIL_REASON=${gh_fail_reason}"
  [ -n "$gh_fail_detail" ] && echo "GH_FAIL_DETAIL=${gh_fail_detail}"
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
