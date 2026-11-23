#!/usr/bin/env bash
# shellcheck shell=bash
#
# Structured summary block shared by the git-pr-sweep scripts, in the shape of
# .claude/rules/structured-script-output.md:
#
#   === <NAME> ===
#   KEY=value ...
#   STATUS=OK|WARN|ERROR
#   REASON=<TYPE>: <MSG> (+N more)     only when STATUS is not OK
#   ISSUE_COUNT=<rows under ISSUES:>
#   ISSUES:
#     - SEVERITY=<WARN|ERROR> TYPE=<type> MSG=<one line>
#   === END <NAME> ===
#
# The scripts emit their real payload as JSON (to --out FILE, or stdout). This
# block is the rollup a calling skill reads: written to stdout when the JSON
# went to a file, to stderr when the JSON went to stdout.
#
# Usage:
#   source "$(dirname "${BASH_SOURCE[0]}")/lib/summary.sh"
#   summary_init "PR SWEEP ROSTER"
#   summary_kv PRS_FETCHED 12
#   summary_issue WARN truncated "stopped at 500 PRs"
#   summary_emit            # prints the block to fd $SUMMARY_FD (default 1)
#   summary_status          # prints OK|WARN|ERROR

# The same flags as every caller; no -e, because the callers turn failures into
# ERROR rows rather than aborting mid-summary.
set -uo pipefail

SUMMARY_NAME=""
SUMMARY_KV=()
SUMMARY_ISSUES=()
SUMMARY_SEVERITIES=()
SUMMARY_TYPES=()
SUMMARY_MSGS=()
: "${SUMMARY_FD:=1}"

summary_init() {
  SUMMARY_NAME="$1"
  SUMMARY_KV=()
  SUMMARY_ISSUES=()
  SUMMARY_SEVERITIES=()
  SUMMARY_TYPES=()
  SUMMARY_MSGS=()
}

# One line, no control characters: a value must never break the KEY=VALUE grid.
summary__oneline() {
  printf '%s' "$1" | tr '\r\n\t' '   ' | tr -s ' '
}

summary_kv() {
  SUMMARY_KV+=("$1=$(summary__oneline "${2:-}")")
}

summary_issue() {
  local sev="$1" kind="$2" msg
  msg=$(summary__oneline "$3")
  SUMMARY_SEVERITIES+=("$sev")
  SUMMARY_TYPES+=("$kind")
  SUMMARY_MSGS+=("$msg")
  SUMMARY_ISSUES+=("  - SEVERITY=$sev TYPE=$kind MSG=$msg")
}

summary_status() {
  local s out="OK"
  for s in "${SUMMARY_SEVERITIES[@]:-}"; do
    [ "$s" = "ERROR" ] && { echo ERROR; return; }
    [ "$s" = "WARN" ] && out="WARN"
  done
  echo "$out"
}

summary_emit() {
  local st count i reason more
  st=$(summary_status)
  count=${#SUMMARY_ISSUES[@]}
  {
    echo "=== $SUMMARY_NAME ==="
    for i in "${SUMMARY_KV[@]:-}"; do [ -n "$i" ] && echo "$i"; done
    echo "STATUS=$st"
    if [ "$st" != "OK" ]; then
      # REASON comes from the first row at the reported severity.
      for i in "${!SUMMARY_SEVERITIES[@]}"; do
        if [ "${SUMMARY_SEVERITIES[$i]}" = "$st" ]; then
          reason="${SUMMARY_TYPES[$i]}: ${SUMMARY_MSGS[$i]}"
          break
        fi
      done
      reason="${reason:0:180}"
      more=""
      [ "$count" -gt 1 ] && more=" (+$((count - 1)) more)"
      echo "REASON=${reason}${more}"
    fi
    echo "ISSUE_COUNT=$count"
    if [ "$count" -gt 0 ]; then
      echo "ISSUES:"
      for i in "${SUMMARY_ISSUES[@]}"; do echo "$i"; done
    fi
    echo "=== END $SUMMARY_NAME ==="
  } >&"$SUMMARY_FD"
}
