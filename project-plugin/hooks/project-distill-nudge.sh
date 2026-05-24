#!/usr/bin/env bash
# Stop hook — nudges the agent to propose /project:distill when the user is
# signaling end-of-session in a repo with a distillable surface
# (`.claude/rules/` directory or a justfile).
#
# Fires at most once per session_id (state file). Conservative on three axes
# (turn count, repo scope, wind-down phrasing) so it stays quiet on quick
# lookups and on repos where there is nothing to distill into.

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
state_dir="${HOME}/.cache/claude-project-distill-nudge"
mkdir -p "$state_dir"
state_file="$state_dir/$session_id"
[ -f "$state_file" ] && exit 0

# Need substantial conversation — distill is heavier than wrap; raise the bar
user_turns=$(grep -c '"role":"user"' "$transcript" 2>/dev/null || echo 0)
[ "$user_turns" -lt 8 ] && exit 0

# Scope filter: the cwd's repo must have something distillable. Resolve via
# `git rev-parse --show-toplevel` so worktrees match against their parent
# repo's surface. Fall back to cwd itself when not in a git repo.
[ -z "$cwd" ] && exit 0
[ ! -d "$cwd" ] && exit 0

repo_root=$(git -C "$cwd" rev-parse --show-toplevel 2>/dev/null || echo "$cwd")

has_surface=0
if [ -d "$repo_root/.claude/rules" ]; then
    has_surface=1
elif [ -f "$repo_root/justfile" ] || [ -f "$repo_root/Justfile" ]; then
    has_surface=1
fi

[ "$has_surface" = 0 ] && exit 0

# Wind-down signal in the last 3 user messages. Recent messages are at the
# end of the transcript, so tail is enough.
recent=$(grep '"role":"user"' "$transcript" 2>/dev/null | tail -3 || true)
if ! echo "$recent" | grep -Eiq '\b(wrap up|wrap this|wrap the session|done for (today|now|the day)|calling it|good night|signing off|end of day|gotta go|heading out|i.?m done|thats it for|that.?s it for)\b'; then
    exit 0
fi

# Mark and emit. `decision: block` injects the reason as continued context
# so the agent will produce one more response — a /project:distill suggestion.
touch "$state_file"

reason="The user is wrapping up a session in a repo with a distillable surface (.claude/rules/ or a justfile). Before letting the session end, briefly offer to run /project:distill --dry-run so the user can preview captured learnings before applying. Cite the skill's 'Update Over Add' principle — favour updating existing rules/skills/recipes over creating new artifacts. Only nudge — never run /project:distill without explicit user confirmation."

jq -nc --arg r "$reason" '{decision: "block", reason: $r}'
