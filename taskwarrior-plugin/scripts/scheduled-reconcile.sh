#!/usr/bin/env bash
# scheduled-reconcile.sh — cadence wrapper around reconcile.sh (issue #1793).
#
# Forge state (an issue closing, a PR merging) is not a local event, so linked-
# task drift only retires when something polls for it. The SessionStart drift
# probe (#1792) surfaces it when you open a repo; this is the scheduled-poll
# sibling that closes the gap for queues spanning repos you don't open daily.
# The reconcile *logic* already lives in reconcile.sh; this only adds cadence.
#
# Two safety tiers (per .claude/rules/drift-detection-triggering.md):
#
#   default — NOTIFY-ONLY. Runs `reconcile.sh --all` in DRY-RUN (mutates
#     nothing); if STALE_COUNT>0, fires telegram-notify and/or a desktop
#     notification with a per-project breakdown. Zero auto-mutation.
#
#   --apply — BOUNDED AUTO-APPLY. Delegates to
#     `reconcile.sh --all --apply --only-verdicts=pr-merged,issue-closed` —
#     auto-closes only the unambiguous verdicts (a merged PR / closed issue are
#     facts). pr-closed-unmerged (abandoned? superseded?) and UNKNOWN are left
#     for a human. Notifies what was closed and what still needs review.
#
# Honors reconcile.sh's guards: GH_AVAILABLE=false → emit nothing and never
# notify "0 drift" (never act on uncertainty). Always exit 0 (parallel-safe);
# the outcome is in the KEY=VALUE block, not the exit code.
#
# Output: structured KEY=VALUE block (.claude/rules/structured-script-output.md).
#
# Flags / env:
#   --apply                   bounded auto-apply (default: notify-only)
#   --project-dir=<dir>       directory for gh/git probes (default: cwd)
#   --limit=<n>               max linked tasks to inspect (passed to reconcile)
#   --no-telegram             skip the telegram-notify channel
#   --no-desktop              skip the desktop-notification channel
#   CLAUDE_TASKWARRIOR_NO_SCHEDULED_RECONCILE=1   opt out entirely (no-op)
#   TW_RECONCILE_SCRIPT       reconcile.sh path (test seam)
#   TW_RECONCILE_TELEGRAM_BIN telegram-notify path (test seam)
#   TW_RECONCILE_DESKTOP_BIN  desktop notifier path (test seam; default osascript)

set -uo pipefail

# The bounded, unambiguous verdicts an auto-apply may close. A merged PR and a
# closed issue are facts; pr-closed (unmerged) is a judgement left to a human.
APPLY_VERDICTS="pr-merged,issue-closed"

sr_apply=false
sr_dir="$PWD"
sr_limit=""
sr_no_telegram="${CLAUDE_TASKWARRIOR_RECONCILE_NO_TELEGRAM:-0}"
sr_no_desktop="${CLAUDE_TASKWARRIOR_RECONCILE_NO_DESKTOP:-0}"

while [ $# -gt 0 ]; do
  case "$1" in
    --apply) sr_apply=true ;;
    --project-dir=*) sr_dir="${1#*=}" ;;
    --project-dir) shift; sr_dir="${1:-$PWD}" ;;
    --limit=*) sr_limit="${1#*=}" ;;
    --limit) shift; sr_limit="${1:-}" ;;
    --no-telegram) sr_no_telegram=1 ;;
    --no-desktop) sr_no_desktop=1 ;;
    *) ;;
  esac
  shift
done

echo "=== SCHEDULED RECONCILE ==="

# --- Opt-out -----------------------------------------------------------------
if [ "${CLAUDE_TASKWARRIOR_NO_SCHEDULED_RECONCILE:-0}" = "1" ]; then
  echo "SKIPPED=opt-out"
  echo "NOTIFIED=false"
  echo "STATUS=OK"
  echo "ISSUE_COUNT=0"
  echo "=== END SCHEDULED RECONCILE ==="
  exit 0
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RECONCILE_SH="${TW_RECONCILE_SCRIPT:-${SCRIPT_DIR}/../skills/task-reconcile/scripts/reconcile.sh}"

echo "MODE=$([ "$sr_apply" = true ] && echo apply || echo notify-only)"

if [ ! -f "$RECONCILE_SH" ]; then
  echo "RECONCILE_AVAILABLE=false"
  echo "NOTIFIED=false"
  echo "STATUS=WARN"
  echo "ISSUE_COUNT=1"
  echo "ISSUES:"
  echo "  - SEVERITY=WARN TYPE=reconcile_missing MSG=reconcile.sh not found at ${RECONCILE_SH}"
  echo "=== END SCHEDULED RECONCILE ==="
  exit 0
fi
echo "RECONCILE_AVAILABLE=true"

# --- Run reconcile (cross-project) -------------------------------------------
# notify-only → dry-run (no flags); apply → --apply scoped to the bounded set.
rc_args=(--all --project-dir "$sr_dir")
[ -n "$sr_limit" ] && rc_args+=(--limit "$sr_limit")
if [ "$sr_apply" = true ]; then
  rc_args+=(--apply --only-verdicts="$APPLY_VERDICTS")
fi

rc_out=$(bash "$RECONCILE_SH" "${rc_args[@]}" 2>/dev/null || true)

field() { printf '%s\n' "$rc_out" | grep -m1 "^$1=" | cut -d= -f2-; }

gh_avail=$(field GH_AVAILABLE)
echo "GH_AVAILABLE=${gh_avail:-unknown}"

# Never act on uncertainty: if upstream state is unknowable, emit nothing and
# never report "0 drift" (which would falsely read as "queue is clean").
if [ "$gh_avail" != "true" ]; then
  echo "NOTIFIED=false"
  echo "STATUS=OK"
  echo "ISSUE_COUNT=0"
  echo "NOTE=upstream state unavailable (no authenticated gh / no remote); nothing surfaced"
  echo "=== END SCHEDULED RECONCILE ==="
  exit 0
fi

stale=$(field STALE_COUNT)
case "$stale" in ''|*[!0-9]*) stale=0 ;; esac
echo "STALE_COUNT=${stale}"

closed=$(field CLOSED_COUNT)
case "$closed" in ''|*[!0-9]*) closed="" ;; esac
[ "$sr_apply" = true ] && echo "CLOSED_COUNT=${closed:-0}"

# --- Per-project breakdown + closeable/needs-review split from TASK lines -----
# A stale TASK line: `TASK ... project=<p> ... verdict=<v> method=<m>`.
# closeable = the bounded verdicts; needs_review = stale but outside the set.
declare -A proj_stale
closeable=0
needs_review=0
breakdown=""
while IFS= read -r line; do
  case "$line" in TASK\ *) ;; *) continue ;; esac
  v=$(printf '%s\n' "$line" | grep -o 'verdict=[^ ]*' | cut -d= -f2)
  [ "$v" = "live" ] && continue
  p=$(printf '%s\n' "$line" | grep -o 'project=[^ ]*' | cut -d= -f2)
  [ -z "$p" ] && p="-"
  proj_stale[$p]=$(( ${proj_stale[$p]:-0} + 1 ))
  case ",${APPLY_VERDICTS}," in
    *",$v,"*) closeable=$((closeable + 1)) ;;
    *) needs_review=$((needs_review + 1)) ;;
  esac
done <<< "$rc_out"

for p in "${!proj_stale[@]}"; do
  breakdown="${breakdown:+$breakdown, }${p}=${proj_stale[$p]}"
done
echo "CLOSEABLE_COUNT=${closeable}"
echo "NEEDS_REVIEW_COUNT=${needs_review}"
echo "PROJECT_BREAKDOWN=${breakdown}"

# --- Decide whether there is anything to surface -----------------------------
if [ "$sr_apply" = true ]; then
  # In apply mode, surface when we closed something or there is residual drift.
  surface=$(( ${closed:-0} > 0 || needs_review > 0 ? 1 : 0 ))
else
  surface=$(( stale > 0 ? 1 : 0 ))
fi

if [ "$surface" -eq 0 ]; then
  echo "NOTIFIED=false"
  echo "STATUS=OK"
  echo "ISSUE_COUNT=0"
  echo "=== END SCHEDULED RECONCILE ==="
  exit 0
fi

# --- Build the notification message ------------------------------------------
if [ "$sr_apply" = true ]; then
  msg="taskwarrior reconcile: closed ${closed:-0} stale task(s) (pr-merged/issue-closed)"
  [ "$needs_review" -gt 0 ] && msg="${msg}; ${needs_review} need review (pr-closed)"
else
  msg="taskwarrior reconcile: ${stale} stale linked task(s) mirror a closed/merged GitHub issue or PR"
  [ "$closeable" -gt 0 ] && msg="${msg}; ${closeable} auto-closeable, ${needs_review} need review"
fi
[ -n "$breakdown" ] && msg="${msg}"$'\n'"by project: ${breakdown}"
msg="${msg}"$'\n'"run /taskwarrior:task-reconcile to act"

# --- Fire the channels (each guarded + overridable for tests) ----------------
notified=false

telegram_bin="${TW_RECONCILE_TELEGRAM_BIN:-}"
if [ -z "$telegram_bin" ]; then
  if command -v telegram-notify >/dev/null 2>&1; then
    telegram_bin="telegram-notify"
  elif [ -x "${HOME}/.local/bin/telegram-notify" ]; then
    telegram_bin="${HOME}/.local/bin/telegram-notify"
  fi
fi
if [ "$sr_no_telegram" != "1" ] && [ -n "$telegram_bin" ]; then
  if "$telegram_bin" "$msg" >/dev/null 2>&1; then
    notified=true
    echo "TELEGRAM_NOTIFIED=true"
  else
    echo "TELEGRAM_NOTIFIED=false"
  fi
fi

if [ "$sr_no_desktop" != "1" ]; then
  desktop_bin="${TW_RECONCILE_DESKTOP_BIN:-}"
  if [ -n "$desktop_bin" ]; then
    if "$desktop_bin" "$msg" >/dev/null 2>&1; then
      notified=true
      echo "DESKTOP_NOTIFIED=true"
    fi
  elif command -v osascript >/dev/null 2>&1; then
    # macOS desktop notification (first line only — notifications are one-liners).
    first_line=${msg%%$'\n'*}
    if osascript -e "display notification \"${first_line//\"/\\\"}\" with title \"taskwarrior reconcile\"" >/dev/null 2>&1; then
      notified=true
      echo "DESKTOP_NOTIFIED=true"
    fi
  elif command -v notify-send >/dev/null 2>&1; then
    if notify-send "taskwarrior reconcile" "$msg" >/dev/null 2>&1; then
      notified=true
      echo "DESKTOP_NOTIFIED=true"
    fi
  fi
fi

echo "NOTIFIED=${notified}"
echo "STATUS=OK"
echo "ISSUE_COUNT=0"
echo "=== END SCHEDULED RECONCILE ==="
exit 0
