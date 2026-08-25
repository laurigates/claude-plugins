#!/usr/bin/env bash
# SessionStart hook — offers session-plugin:session-spinup when a fresh
# session opens with open threads worth surfacing: pending/+ACTIVE taskwarrior
# tasks for the cwd's project, uncommitted changes, unpushed commits, or open
# GitHub issues assigned to the user in the cwd repo.
#
# Detection is delegated to the shared collector (scripts/session-survey.sh)
# in --summary mode, so the hook and the skill agree on what an "open thread"
# is — single source of truth. Injects context (additionalContext) instead of
# blocking — a SessionStart nudge should inform, not force a turn.
#
# Fires only on source=startup|resume (silent on clear/compact — those are
# mid-session continuations), at most once per session_id.
set -euo pipefail

input=$(cat)

source_kind=$(jq -r '.source // empty' <<<"$input" 2>/dev/null || echo "")
case "$source_kind" in
    startup|resume) ;;
    *) exit 0 ;;
esac

session_id=$(jq -r '.session_id // empty' <<<"$input" 2>/dev/null || echo "")
cwd=$(jq -r '.cwd // empty' <<<"$input" 2>/dev/null || echo "")

[ -z "$session_id" ] && exit 0
[ -z "$cwd" ] && exit 0
[ ! -d "$cwd" ] && exit 0

# At most one nudge per session
state_dir="${HOME}/.cache/claude-session-spinup-nudge"
mkdir -p "$state_dir"
state_file="$state_dir/$session_id"
[ -f "$state_file" ] && exit 0

# Run the shared collector. The SESSION_NUDGE_* seams (used by the hook test)
# map onto the collector's SESSION_SURVEY_* seams so both stay stubable.
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
collector="$script_dir/../scripts/session-survey.sh"
[ -f "$collector" ] || exit 0

summary=$(SESSION_SURVEY_TASK_BIN="${SESSION_NUDGE_TASK_BIN:-task}" \
          SESSION_SURVEY_GH_BIN="${SESSION_NUDGE_GH_BIN:-gh}" \
          SESSION_SURVEY_GIT_BIN="${SESSION_NUDGE_GIT_BIN:-git}" \
          bash "$collector" --summary --with-dedup --project-dir "$cwd" 2>/dev/null || echo "")

get() { printf '%s\n' "$summary" | grep -m1 "^$1=" | cut -d= -f2- || echo ""; }

project=$(get PROJECT)
dirty=$(get DIRTY)
unpushed=$(get UNPUSHED)
behind=$(get BEHIND)
open_tasks=$(get OPEN_TASKS)
assigned_issues=$(get ASSIGNED_ISSUES)
# Scoping signals (#2271/#2232): the detected slug is a guess, so name the
# scope the count actually came from instead of asserting project:<basename>.
task_scope=$(get TASK_SCOPE)
project_resolved=$(get PROJECT_RESOLVED)
recent_tasks=$(get RECENT_TASK_COUNT)

threads=""
[ "$dirty" = "true" ] && threads="${threads}uncommitted changes; "
[ "${unpushed:-0}" -gt 0 ] 2>/dev/null && threads="${threads}unpushed commits; "
# The other direction (#2500): a checkout behind upstream reads as settled
# unless the digest says so. `BEHIND=0` is also what no-upstream and detached
# HEAD report, so this stays silent there — same posture as UNPUSHED.
[ "${behind:-0}" -gt 0 ] 2>/dev/null && threads="${threads}${behind} commit(s) behind upstream — this checkout is stale; "
if [ "${open_tasks:-0}" -gt 0 ] 2>/dev/null; then
    if [ "$task_scope" = "remote-name" ] && [ -n "$project_resolved" ]; then
        threads="${threads}${open_tasks} open taskwarrior task(s) under project:${project_resolved} (resolved from the git remote; the cwd basename is ${project}); "
    else
        threads="${threads}${open_tasks} open taskwarrior task(s) under project:${project}; "
    fi
fi
[ "${recent_tasks:-0}" -gt 0 ] 2>/dev/null && threads="${threads}${recent_tasks} recently-touched taskwarrior task(s) in other projects — nothing under project:${project}, so the detected slug may be wrong; "
[ "${assigned_issues:-0}" -gt 0 ] 2>/dev/null && threads="${threads}${assigned_issues} assigned GitHub issue(s); "

# Nothing open — stay silent; spinup doesn't nudge for nothing
[ -z "$threads" ] && exit 0

touch "$state_file"

context="Open threads detected at session start (${threads%; }). If the user seems to be resuming work, offer to run session-plugin:session-spinup for a read-only briefing of the open threads. Offer once — do not run it unprompted, and drop it if the user starts a clearly unrelated task."

jq -nc --arg c "$context" \
    '{hookSpecificOutput: {hookEventName: "SessionStart", additionalContext: $c}}'
