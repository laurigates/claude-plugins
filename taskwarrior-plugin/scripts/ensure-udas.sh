#!/usr/bin/env bash
# ensure-udas.sh — single source of truth for the taskwarrior-plugin UDA set.
#
# The plugin's skills (task-add, task-claim, task-reconcile) and the
# SessionStart drift-probe all need the same 10 UDAs declared in ~/.taskrc.
# Before this script the install block was copy-pasted into task-add and
# task-claim; this consolidates it so the canonical set lives in one place.
#
# Idempotent: only declares UDAs that `task _udas` does not already report.
# UDA declarations persist in ~/.taskrc, so callers should confirm with the
# user before running on first use per host.
#
# Flags:
#   --check    Report missing UDAs without installing (STATUS=WARN if any
#              missing, STATUS=OK if all present). Default is install mode.
#
# Output: structured KEY=VALUE block (see
# .claude/rules/structured-script-output.md) so callers can roll it up.
#
# Exit codes:
#   0 - all UDAs present, or install succeeded (or --check with none missing)
#   1 - task binary missing, or an install command failed

set -uo pipefail

uda_check_only=false
for arg in "$@"; do
  case "$arg" in
    --check) uda_check_only=true ;;
    *) ;;
  esac
done

echo "=== TASKWARRIOR UDAS ==="

if ! command -v task >/dev/null 2>&1; then
  echo "TASK_AVAILABLE=false"
  echo "STATUS=ERROR"
  echo "ISSUE_COUNT=1"
  echo "ISSUES:"
  echo "  - SEVERITY=ERROR TYPE=task_missing MSG=task binary not found on PATH"
  echo "=== END TASKWARRIOR UDAS ==="
  exit 1
fi
echo "TASK_AVAILABLE=true"

# Canonical UDA set: name<TAB>type<TAB>label.
# Linkage UDAs (set by task-add, read by task-reconcile/task-status/task-done).
# Identity UDAs (set by task-claim, drained by task-release/task-done).
uda_specs=(
  "bpid	string	Blueprint ID"
  "bpdoc	string	Blueprint doc"
  "bpms	string	Milestone"
  "ghid	numeric	GH Issue"
  "ghpr	numeric	GH PR"
  "agent	string	Agent ID"
  "pid	numeric	Agent PID"
  "host	string	Host"
  "branch	string	Git branch"
  "worktree	string	Worktree path"
)

present_udas=""
present_udas=$(task _udas 2>/dev/null || true)

uda_missing=()
for spec in "${uda_specs[@]}"; do
  uda_name="${spec%%	*}"
  if printf '%s\n' "$present_udas" | grep -qx "$uda_name"; then
    continue
  fi
  uda_missing+=("$spec")
done

echo "UDAS_REQUIRED=${#uda_specs[@]}"
echo "UDAS_MISSING=${#uda_missing[@]}"

if [ "${#uda_missing[@]}" -eq 0 ]; then
  echo "STATUS=OK"
  echo "ISSUE_COUNT=0"
  echo "=== END TASKWARRIOR UDAS ==="
  exit 0
fi

missing_names=""
for spec in "${uda_missing[@]}"; do
  missing_names="${missing_names:+$missing_names,}${spec%%	*}"
done
echo "MISSING_NAMES=${missing_names}"

if [ "$uda_check_only" = true ]; then
  echo "STATUS=WARN"
  echo "ISSUE_COUNT=${#uda_missing[@]}"
  echo "ISSUES:"
  for spec in "${uda_missing[@]}"; do
    echo "  - SEVERITY=WARN TYPE=uda_missing UDA=${spec%%	*} MSG=declare with --install or /taskwarrior:task-add"
  done
  echo "=== END TASKWARRIOR UDAS ==="
  exit 0
fi

install_failures=0
installed=""
for spec in "${uda_missing[@]}"; do
  uda_name="${spec%%	*}"
  rest="${spec#*	}"
  uda_type="${rest%%	*}"
  uda_label="${rest#*	}"
  # rc.confirmation=no is REQUIRED: `task config` prompts by default, and a
  # non-interactive call without it exits 0 WITHOUT writing the value — the UDA
  # silently fails to persist and `task add ghid:N` then appends to description.
  # </dev/null guards against any residual prompt consuming the caller's stdin.
  if task rc.confirmation=no config "uda.${uda_name}.type" "$uda_type" </dev/null >/dev/null 2>&1 \
     && task rc.confirmation=no config "uda.${uda_name}.label" "$uda_label" </dev/null >/dev/null 2>&1; then
    installed="${installed:+$installed,}${uda_name}"
  else
    install_failures=$((install_failures + 1))
  fi
done

echo "UDAS_INSTALLED=${installed:-none}"
if [ "$install_failures" -gt 0 ]; then
  echo "STATUS=ERROR"
  echo "ISSUE_COUNT=${install_failures}"
  echo "=== END TASKWARRIOR UDAS ==="
  exit 1
fi

echo "STATUS=OK"
echo "ISSUE_COUNT=0"
echo "=== END TASKWARRIOR UDAS ==="
exit 0
