#!/usr/bin/env bash
# Stop + SessionEnd hook — keeps a ledger of sessions that have not run an
# end-of-session skill, so closing one never silently drops its uncaptured
# learnings or manual steps.
#
# Why a ledger and not a block: no hook can stop a close. SessionEnd is
# notify-only, and a closed terminal window, a crash or a kill -9 may fire
# nothing at all. So the record is written early (on every Stop once the
# session has substance) and cleared late (once session-wrap / session-end /
# session-distill / session-workflow-capture appears in the transcript).
# Whatever way the session ends, an unwrapped one leaves an entry behind;
# session-spinup-nudge.sh surfaces it at the next session start, and
# scripts/unfinished-sessions.sh lists or dismisses entries.
#
# One JSON file per session under the ledger dir:
#   ${SESSION_LEDGER_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/claude-session-plugin/unfinished}
# Fields: session_id, cwd, transcript_path, first_seen, last_active,
# ended_at (null until SessionEnd), end_reason, user_turns, last_user_message.
#
# Prints nothing (Stop stdout would inject context) and always exits 0.
# Kept to grep + jq so it fits SessionEnd's short hook budget.
#
# Tunables: SESSION_LEDGER_MIN_TURNS (default 3 genuine user turns),
# CLAUDE_HOOKS_DISABLE_SESSION_LEDGER=1 turns the hook off.
set -euo pipefail

[ "${CLAUDE_HOOKS_DISABLE_SESSION_LEDGER:-}" = "1" ] && exit 0
command -v jq >/dev/null 2>&1 || exit 0

input=$(cat)
field() { jq -r --arg k "$1" '.[$k] // empty' <<<"$input" 2>/dev/null || true; }

event=$(field hook_event_name)
session_id=$(field session_id)
cwd=$(field cwd)
transcript=$(field transcript_path)
reason=$(field reason)

[ -z "$session_id" ] && exit 0
# The id names a file; refuse anything that could leave the ledger dir.
case "$session_id" in
    *[!A-Za-z0-9._-]* | .*) exit 0 ;;
esac

ledger_dir="${SESSION_LEDGER_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/claude-session-plugin/unfinished}"
entry="$ledger_dir/$session_id.json"

[ -n "$transcript" ] && [ -f "$transcript" ] || exit 0

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source-path=SCRIPTDIR source=lib/session-transcript.sh
. "$script_dir/lib/session-transcript.sh"

if session_end_skill_ran "$transcript"; then
    rm -f "$entry"
    exit 0
fi

user_lines=$(session_genuine_user_lines "$transcript")
user_turns=$(printf '%s\n' "$user_lines" | grep -c '"role":"user"' || true)
user_turns=${user_turns:-0}
min_turns="${SESSION_LEDGER_MIN_TURNS:-3}"
[ "$user_turns" -lt "$min_turns" ] 2>/dev/null && exit 0

last_msg=$(printf '%s\n' "$user_lines" | tail -1 | session_user_text | tr '\n\t' '  ' | cut -c1-200 | sed 's/[[:space:]]*$//')
now=$(date -u +%Y-%m-%dT%H:%M:%SZ)

ended_at="" end_reason=""
if [ "$event" = "SessionEnd" ]; then
    ended_at="$now"
    end_reason="${reason:-other}"
fi

first_seen="$now"
if [ -f "$entry" ]; then
    prev=$(jq -r '.first_seen // empty' "$entry" 2>/dev/null || true)
    [ -n "$prev" ] && first_seen="$prev"
fi

mkdir -p "$ledger_dir" 2>/dev/null || exit 0
tmp=$(mktemp "$ledger_dir/.${session_id}.XXXXXX" 2>/dev/null) || exit 0
if jq -n \
    --arg sid "$session_id" --arg cwd "$cwd" --arg tp "$transcript" \
    --arg first "$first_seen" --arg now "$now" \
    --arg ended "$ended_at" --arg why "$end_reason" \
    --argjson turns "$user_turns" --arg msg "$last_msg" \
    '{session_id: $sid, cwd: $cwd, transcript_path: $tp,
      first_seen: $first, last_active: $now,
      ended_at: (if $ended == "" then null else $ended end),
      end_reason: (if $why == "" then null else $why end),
      user_turns: $turns, last_user_message: $msg}' > "$tmp" 2>/dev/null; then
    mv -f "$tmp" "$entry"
else
    rm -f "$tmp"
fi
exit 0
