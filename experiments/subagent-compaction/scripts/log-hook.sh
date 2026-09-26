#!/usr/bin/env bash
# Hook command for every probed event: append the hook input (plus a timestamp)
# to the arm's hooks.jsonl. Never blocks — observation only.
# Usage (from settings.json): bash log-hook.sh <log-file>
# Observability hook: no -e, so a logging failure never surfaces as a hook error.
set -uo pipefail
log="${1:?usage: log-hook.sh <log-file>}"
in="$(cat)"
printf '%s\n' "$in" | jq -c --arg ts "$(date -Is)" '. + {_ts: $ts}' >> "$log" 2>/dev/null \
  || printf '%s\n' "$in" >> "$log"
exit 0
