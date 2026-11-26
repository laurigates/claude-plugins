#!/usr/bin/env bash
# Shared helpers for local-run probes. Sourced by each probe's run.sh:
#
#   . "$(dirname "$0")/../lib/report.sh"
#   probe_start            # header, OS guard, results/ reset
#   need jq claude         # setup check (exit 1 when missing)
#   log "control: RAN=1"   # a line that also lands in results/summary.txt
#   verdict CODE "meaning. Next: step."
#
# verdict prints the === VERDICT === block, writes results/summary.txt, runs the
# outbound channels (notify, clipboard) behind a secret scan, and exits:
#   0 decided   1 ERROR   2 INCONCLUSIVE   3 SKIP
#
# Inputs (set by run.sh or the root justfile):
#   PROBE_NAME, PROBE_REF   shown in the header
#   REQUIRES_OS             darwin | linux | any (default any)
#   PROBE_CLIP=1            copy summary.txt to the clipboard (off by default)
#   PROBE_NOTIFY=0          skip the channels listed in .handoff.json
# shellcheck shell=bash

PROBE_DIR="${PROBE_DIR:-$(pwd)}"
RESULTS="$PROBE_DIR/results"
SUMMARY="$RESULTS/summary.txt"
HANDOFF="$PROBE_DIR/.handoff.json"

log() {
  printf '%s\n' "$*"
  printf '%s\n' "$*" >>"$SUMMARY"
}

section() { log "=== $1 ==="; }

probe_os() {
  case "$(uname -s)" in
    Darwin) echo darwin ;;
    Linux) echo linux ;;
    *) uname -s | tr '[:upper:]' '[:lower:]' ;;
  esac
}

probe_start() {
  mkdir -p "$RESULTS"
  : >"$SUMMARY"
  section PROBE
  log "NAME=${PROBE_NAME:-$(basename "$PROBE_DIR")}"
  [ -n "${PROBE_REF:-}" ] && log "REF=$PROBE_REF"
  log "HOST=$(hostname -s 2>/dev/null || hostname) OS=$(probe_os) DATE=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  local want="${REQUIRES_OS:-any}"
  if [ "$want" != "any" ] && [ "$want" != "$(probe_os)" ]; then
    verdict SKIP "requires $want, this host is $(probe_os). Run it on a $want workstation."
  fi
}

need() {
  local missing=()
  local c
  for c in "$@"; do command -v "$c" >/dev/null 2>&1 || missing+=("$c"); done
  if [ "${#missing[@]}" -gt 0 ]; then
    verdict ERROR "missing tool(s): ${missing[*]}. Install them and re-run."
  fi
}

# Exit 0 when results/ looks clean. gitleaks when present, a token-shape regex otherwise.
secrets_clean() {
  if command -v gitleaks >/dev/null 2>&1; then
    gitleaks dir "$RESULTS" --no-banner --redact >/dev/null 2>&1
    return $?
  fi
  ! grep -rEq '(ghp_|gho_|github_pat_)[A-Za-z0-9_]{20,}|sk-ant-[A-Za-z0-9_-]{20,}|AKIA[0-9A-Z]{16}|xox[abpr]-[A-Za-z0-9-]{10,}|-----BEGIN [A-Z ]*PRIVATE KEY' "$RESULTS"
}

clip_copy() {
  local tool
  for tool in pbcopy wl-copy; do
    if command -v "$tool" >/dev/null 2>&1; then "$tool" <"$SUMMARY" && echo "CLIP=$tool" && return 0; fi
  done
  if command -v xclip >/dev/null 2>&1; then
    xclip -selection clipboard <"$SUMMARY" && echo "CLIP=xclip" && return 0
  fi
  echo "CLIP=none (no pbcopy, wl-copy or xclip)"
}

handoff_get() { # $1 jq path; empty when absent
  [ -f "$HANDOFF" ] && command -v jq >/dev/null 2>&1 || return 0
  jq -r "$1 // empty" "$HANDOFF" 2>/dev/null
}

notify_pr() {
  local pr="$1"
  command -v gh >/dev/null 2>&1 || { echo "NOTIFY_PR=skipped (no gh)"; return 0; }
  local repo="${pr%%#*}" num="${pr##*#}"
  local body="$RESULTS/.pr-comment.md"
  {
    printf 'Local probe result: `%s`\n\n```\n' "$(basename "$PROBE_DIR")"
    cat "$SUMMARY"
    printf '```\n'
  } >"$body"
  if gh pr comment "$num" -R "$repo" --body-file "$body" >/dev/null 2>&1; then
    echo "NOTIFY_PR=sent $pr"
  else
    echo "NOTIFY_PR=failed $pr"
  fi
}

notify_session() { # local sessions only: headless claude -p does not list cloud sessions
  local target="$1"
  command -v claude >/dev/null 2>&1 || { echo "NOTIFY_SESSION=skipped (no claude)"; return 0; }
  local msg
  msg="Probe $(basename "$PROBE_DIR") finished: $(grep '^STATUS=' "$SUMMARY" | head -1). Full summary: $SUMMARY"
  local reply
  reply=$(claude -p "Use the SendMessage tool exactly once with to=\"$target\" and this message, verbatim: $msg. Then print SENT, or SEND_ERROR and the error." \
    --model haiku --allowedTools SendMessage --output-format text 2>/dev/null)
  if grep -q '^SENT' <<<"$reply"; then
    echo "NOTIFY_SESSION=sent $target"
  else
    echo "NOTIFY_SESSION=failed $target"
  fi
}

outbound() {
  local pr session
  pr=$(handoff_get '.notify.pr')
  session=$(handoff_get '.notify.session')
  [ "${PROBE_NOTIFY:-1}" = "0" ] && { pr=""; session=""; }
  if [ -z "$pr" ] && [ -z "$session" ] && [ "${PROBE_CLIP:-0}" != "1" ]; then
    return 0
  fi
  if ! secrets_clean; then
    echo "WARN: results/ contains something shaped like a secret; skipped notify and clipboard."
    return 0
  fi
  [ -n "$pr" ] && notify_pr "$pr"
  [ -n "$session" ] && notify_session "$session"
  [ "${PROBE_CLIP:-0}" = "1" ] && clip_copy
  return 0
}

verdict() {
  local code="$1"
  shift
  section VERDICT
  log "STATUS=$code $*"
  outbound
  case "$code" in
    ERROR) exit 1 ;;
    INCONCLUSIVE) exit 2 ;;
    SKIP) exit 3 ;;
    *) exit 0 ;;
  esac
}
