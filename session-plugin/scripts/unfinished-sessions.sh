#!/usr/bin/env bash
# List, summarize or dismiss sessions recorded by hooks/session-ledger.sh:
# sessions that ended (or are still open) without an end-of-session skill.
#
# Usage:
#   unfinished-sessions.sh [--list] [--cwd DIR] [--exclude ID]
#   unfinished-sessions.sh --summary [--cwd DIR] [--exclude ID]
#   unfinished-sessions.sh --dismiss ID [ID...]
#   unfinished-sessions.sh --prune
#
#   --list     (default) one row per session, most recent first
#   --summary  counts only, for session-spinup-nudge.sh
#   --cwd      also count the sessions in DIR's git repo (or DIR itself)
#   --exclude  leave this session id out (the session asking)
#   --dismiss  delete entries, for a session whose loose ends are handled
#   --prune    delete entries whose transcript no longer exists
#
# STATE=open means no SessionEnd was seen: the session is still running, or
# it was killed before it could report. Resume either with
# `cd <CWD> && claude --resume <ID>`, then run /session-plugin:session-end.
#
# Ledger dir: ${SESSION_LEDGER_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/claude-session-plugin/unfinished}
set -euo pipefail

mode=list
filter_cwd=""
exclude_id=""
dismiss_ids=()
while [ $# -gt 0 ]; do
    case "$1" in
        --list) mode=list; shift ;;
        --summary) mode=summary; shift ;;
        --prune) mode=prune; shift ;;
        --dismiss)
            mode=dismiss; shift
            while [ $# -gt 0 ] && [ "${1#--}" = "$1" ]; do dismiss_ids+=("$1"); shift; done
            ;;
        --cwd) filter_cwd="${2:-}"; shift 2 ;;
        --exclude) exclude_id="${2:-}"; shift 2 ;;
        -h|--help) sed -n '2,23p' "$0"; exit 0 ;;
        *) echo "unknown argument: $1" >&2; exit 2 ;;
    esac
done

ledger_dir="${SESSION_LEDGER_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/claude-session-plugin/unfinished}"

if [ "$mode" = dismiss ]; then
    removed=0
    for sid in "${dismiss_ids[@]}"; do
        case "$sid" in *[!A-Za-z0-9._-]* | .* | "") continue ;; esac
        if [ -f "$ledger_dir/$sid.json" ]; then
            rm -f "$ledger_dir/$sid.json"; removed=$((removed + 1))
        fi
    done
    echo "=== DISMISS UNFINISHED SESSIONS ==="
    echo "REMOVED=${removed}"
    echo "STATUS=OK"
    echo "ISSUE_COUNT=0"
    echo "=== END DISMISS UNFINISHED SESSIONS ==="
    exit 0
fi

# All entries as one JSON array, most recent first. Unreadable files are skipped.
entries="[]"
if [ -d "$ledger_dir" ]; then
    # A plain loop, not `xargs -r` (GNU-only): this runs on macOS too.
    entries=$(for f in "$ledger_dir"/*.json; do
                  [ -f "$f" ] || continue
                  jq -c 'select(type == "object" and .session_id)' "$f" 2>/dev/null || true
              done | jq -sc 'sort_by(.last_active // "") | reverse' 2>/dev/null || echo "[]")
fi
[ -n "$exclude_id" ] && entries=$(jq -c --arg x "$exclude_id" 'map(select(.session_id != $x))' <<<"$entries")

if [ "$mode" = prune ]; then
    removed=0
    while IFS=$'\t' read -r sid tp; do
        [ -z "$sid" ] && continue
        if [ -z "$tp" ] || [ ! -f "$tp" ]; then
            rm -f "$ledger_dir/$sid.json"; removed=$((removed + 1))
        fi
    done < <(jq -r '.[] | [.session_id, (.transcript_path // "")] | @tsv' <<<"$entries")
    echo "=== PRUNE UNFINISHED SESSIONS ==="
    echo "REMOVED=${removed}"
    echo "STATUS=OK"
    echo "ISSUE_COUNT=0"
    echo "=== END PRUNE UNFINISHED SESSIONS ==="
    exit 0
fi

# "Here" = the same directory, or anywhere inside the same git repo. Both
# the cwd and the repo root are tried as prefixes: on macOS a /var path and
# its /private/var real path name the same directory.
here_root=""
if [ -n "$filter_cwd" ]; then
    here_root=$(git -C "$filter_cwd" rev-parse --show-toplevel 2>/dev/null || echo "$filter_cwd")
fi
here=$(jq -c --arg cwd "$filter_cwd" --arg root "$here_root" '
    if $cwd == "" then [] else
      map(select((.cwd // "") as $c
                 | $c == $cwd or $c == $root
                   or ($c | startswith($root + "/")) or ($c | startswith($cwd + "/"))))
    end' <<<"$entries")

total=$(jq 'length' <<<"$entries")
open_count=$(jq 'map(select(.ended_at == null)) | length' <<<"$entries")
here_count=$(jq 'length' <<<"$here")

if [ "$mode" = summary ]; then
    echo "UNFINISHED_COUNT=${total}"
    echo "UNFINISHED_OPEN=${open_count}"
    echo "UNFINISHED_HERE=${here_count}"
    echo "HERE_IDS=$(jq -r '[.[:3][] | .session_id] | join(",")' <<<"$here")"
    exit 0
fi

echo "=== UNFINISHED SESSIONS ==="
echo "LEDGER_DIR=${ledger_dir}"
echo "SESSION_COUNT=${total}"
echo "OPEN_COUNT=${open_count}"
[ -n "$filter_cwd" ] && echo "HERE_COUNT=${here_count}"
if [ "$total" -gt 0 ]; then
    echo "SESSIONS:"
    jq -r '.[] | "  - ID=\(.session_id) STATE=\(if .ended_at == null then "open" else "closed" end) LAST_ACTIVE=\(.last_active // "") TURNS=\(.user_turns // 0) CWD=\(.cwd // "") MSG=\(.last_user_message // "" | gsub("[\\n\\t]"; " "))"' <<<"$entries"
fi
echo "STATUS=OK"
echo "ISSUE_COUNT=0"
echo "=== END UNFINISHED SESSIONS ==="
