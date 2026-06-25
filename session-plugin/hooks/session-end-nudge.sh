#!/usr/bin/env bash
# Stop hook — offers the session-plugin:session-end orchestrator when the user
# signals end-of-session. Collapses the former user-level session-wrap-nudge
# and project-plugin's project-distill-nudge into ONE nudge (decision D4 in
# docs/session-plugin-workflow.md), so wind-down produces a single offer
# instead of competing hook injections.
#
# Fires at most once per session_id (state file). Conservative gates:
#   - >= 6 genuine user turns (tool results and slash-command expansions are
#     excluded from both the turn count and the wind-down scan)
#   - a wind-down phrase in the last 3 genuine user messages
#   - something to capture into: taskwarrior on PATH, or a distillable
#     surface (.claude/rules/ or a justfile) in the cwd's repo
#   - silent when a session-wrap / session-end / session-distill invocation
#     already appears in the transcript — the skill owns the flow from there
#
# Regression context (see test-session-end-nudge.sh):
#   - The old project-distill-nudge matched its wind-down regex against the
#     /session-wrap skill's own injected markdown ("Wrap up a working
#     session…") and fired mid-skill, racing a pending y/n confirmation.
#     Genuine-user-line filtering + the in-progress guard prevent both.
set -euo pipefail

input=$(cat)

# Hard exits — never loop or run without the data we need
stop_active=$(jq -r '.stop_hook_active // false' <<<"$input" 2>/dev/null || echo "false")
[ "$stop_active" = "true" ] && exit 0

session_id=$(jq -r '.session_id // empty' <<<"$input" 2>/dev/null || echo "")
cwd=$(jq -r '.cwd // empty' <<<"$input" 2>/dev/null || echo "")
transcript=$(jq -r '.transcript_path // empty' <<<"$input" 2>/dev/null || echo "")

[ -z "$session_id" ] && exit 0
[ -z "$transcript" ] && exit 0
[ ! -f "$transcript" ] && exit 0

# At most one nudge per session
state_dir="${HOME}/.cache/claude-session-end-nudge"
mkdir -p "$state_dir"
state_file="$state_dir/$session_id"
[ -f "$state_file" ] && exit 0

# Skip when an end-of-session skill is already driving the flow this session —
# either invoked as a slash command (<command-name> tag in the expansion) or
# via the Skill tool ("skill":"…" in the tool_use input).
if grep -q 'command-name>[^<]*session-\(wrap\|end\|distill\)' "$transcript" 2>/dev/null; then
    exit 0
fi
if grep -q '"skill"[[:space:]]*:[[:space:]]*"[^"]*session-\(wrap\|end\|distill\)' "$transcript" 2>/dev/null; then
    exit 0
fi

# Genuine user prompts only: drop tool_result lines (role=user but harness-
# generated) and slash-command expansions (role=user but skill markdown).
user_lines=$(grep '"role":"user"' "$transcript" 2>/dev/null \
    | grep -v '"tool_use_id"' \
    | grep -v 'command-name>' || true)

user_turns=$(printf '%s\n' "$user_lines" | grep -c '"role":"user"' || true)
user_turns=${user_turns:-0}
[ "$user_turns" -lt 6 ] && exit 0

# Something to capture into: taskwarrior (wrap destination) or a distillable
# surface in the repo (distill target). Resolve the repo root via git so
# worktrees match their parent repo's surface. SESSION_NUDGE_TASK_BIN is a
# test seam — point it at a nonexistent path to simulate "no taskwarrior".
task_bin="${SESSION_NUDGE_TASK_BIN:-task}"
has_surface=0
has_open_tasks=0
if command -v "$task_bin" >/dev/null 2>&1; then
    has_surface=1
    # Read-only query for open/active tasks in the current project.
    # Uses 'export' (not 'list') so it exits 0 on empty — parallel-safe.
    if [ -n "$cwd" ]; then
        repo_root_tw=$(git -C "$cwd" rev-parse --show-toplevel 2>/dev/null || echo "$cwd")
        proj=$(basename "$repo_root_tw")
        task_count=$("$task_bin" project:"$proj" '(status:pending or +ACTIVE)' export 2>/dev/null \
            | jq 'length' 2>/dev/null || echo 0)
        [ "${task_count:-0}" -gt 0 ] && has_open_tasks=1
    fi
elif [ -n "$cwd" ] && [ -d "$cwd" ]; then
    repo_root=$(git -C "$cwd" rev-parse --show-toplevel 2>/dev/null || echo "$cwd")
    if [ -d "$repo_root/.claude/rules" ] \
        || [ -f "$repo_root/justfile" ] || [ -f "$repo_root/Justfile" ]; then
        has_surface=1
    fi
fi
[ "$has_surface" = 0 ] && exit 0

# Wind-down signal in the last 3 genuine user messages
recent=$(printf '%s\n' "$user_lines" | tail -3)
if ! echo "$recent" | grep -Eiq '\b(wrap up|wrap this|wrap the session|done for (today|now|the day)|calling it|good night|signing off|end of day|gotta go|heading out|i.?m done|thats it for|that.?s it for)\b'; then
    exit 0
fi

# Mark and emit. `decision: block` injects the reason as continued context so
# the agent produces one more response — an offer, never an execution.
touch "$state_file"

task_cue=""
if [ "$has_open_tasks" = 1 ]; then
    task_cue=" Also mention a taskwarrior state-sync pass: check which tasks are still open or active (task project:<name> '(status:pending or +ACTIVE)' export | jq '.[]'), offer to mark done / update statuses / add follow-up tasks — use stable UUIDs from 'task +LATEST uuids' when referencing specific tasks."
fi

reason="The user is winding down the session. Briefly offer to run the session-plugin:session-end orchestrator — it surveys the session once, previews which end-of-session passes qualify (session-wrap loose-thread capture, session-distill durable learnings, /feedback:session plugin feedback) and runs only what the user confirms in a single prompt.${task_cue} Offer only — never run it without explicit user confirmation. If nothing follow-up-worthy surfaced this session, acknowledge the wind-down and end."

jq -nc --arg r "$reason" '{decision: "block", reason: $r}'
