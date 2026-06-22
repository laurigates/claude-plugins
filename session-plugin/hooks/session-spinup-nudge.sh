#!/usr/bin/env bash
# SessionStart hook — offers session-plugin:session-spinup when a fresh
# session opens with open threads worth surfacing: pending or +ACTIVE
# taskwarrior tasks for the cwd's project, uncommitted changes, unpushed
# commits, or open GitHub issues assigned to the user in the cwd repo.
# Injects context (additionalContext) instead of blocking — a SessionStart
# nudge should inform, not force a turn.
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

threads=""

# Git state: uncommitted changes or unpushed commits on the current branch
if git -C "$cwd" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    dirty=$(git -C "$cwd" status --porcelain 2>/dev/null | head -1 || true)
    [ -n "$dirty" ] && threads="${threads}uncommitted changes; "

    unpushed=$(git -C "$cwd" log '@{u}..HEAD' --oneline 2>/dev/null | head -1 || true)
    [ -n "$unpushed" ] && threads="${threads}unpushed commits; "
fi

# Taskwarrior: pending or in-flight tasks for the project inferred from the
# repo root basename. `export` is exit-0 on empty (parallel-safe-queries.md).
# SESSION_NUDGE_TASK_BIN is a test seam — see test-session-spinup-nudge.sh.
task_bin="${SESSION_NUDGE_TASK_BIN:-task}"
if command -v "$task_bin" >/dev/null 2>&1; then
    repo_root=$(git -C "$cwd" rev-parse --show-toplevel 2>/dev/null || echo "$cwd")
    project=$(basename "$repo_root")
    open_count=$("$task_bin" "project:$project" '(status:pending or +ACTIVE)' export 2>/dev/null \
        | jq 'length' 2>/dev/null || echo 0)
    if [ "${open_count:-0}" -gt 0 ] 2>/dev/null; then
        threads="${threads}${open_count} open taskwarrior task(s) under project:${project}; "
    fi
fi

# GitHub issues: open issues assigned to the user in the cwd repo. Gated on a
# fast `gh auth status` so an unauthenticated machine pays no network cost.
# Coarse count only — the skill does precise dedup against taskwarrior, but a
# tracked issue already trips the taskwarrior signal above, so over-counting
# here at worst restates an existing reason, never invents a false one.
# SESSION_NUDGE_GH_BIN is a test seam — see test-session-spinup-nudge.sh.
gh_bin="${SESSION_NUDGE_GH_BIN:-gh}"
if command -v "$gh_bin" >/dev/null 2>&1 && "$gh_bin" auth status >/dev/null 2>&1; then
    issue_count=$( (cd "$cwd" && "$gh_bin" issue list --assignee @me --state open \
        --json number --jq 'length' 2>/dev/null) || echo 0)
    if [ "${issue_count:-0}" -gt 0 ] 2>/dev/null; then
        threads="${threads}${issue_count} assigned GitHub issue(s); "
    fi
fi

# Nothing open — stay silent; spinup doesn't nudge for nothing
[ -z "$threads" ] && exit 0

touch "$state_file"

context="Open threads detected at session start (${threads%; }). If the user seems to be resuming work, offer to run session-plugin:session-spinup for a read-only briefing of the open threads. Offer once — do not run it unprompted, and drop it if the user starts a clearly unrelated task."

jq -nc --arg c "$context" \
    '{hookSpecificOutput: {hookEventName: "SessionStart", additionalContext: $c}}'
