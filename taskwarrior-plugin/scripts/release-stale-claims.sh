#!/usr/bin/env bash
# release-stale-claims.sh — deterministic auto-release of abandoned +ACTIVE
# claims whose claiming process is dead (issue #1792).
#
# `task-status` / `task-coordinate` already *detect* +ACTIVE claims older than N
# hours, but nothing *acts* on them, so a crashed/exited agent's claim lingers
# and pollutes `/git:coworker-check` (its 4th signal reads +ACTIVE claims) and
# `task-coordinate`'s "in flight" view. Unlike linked-issue drift (which needs a
# `gh` poll), a dead claim is **deterministically observable locally** —
# `kill -0 "$pid"` failing on the claim's own `host` is a fact, not a judgment —
# so this is a clean script/hook candidate with no LLM in the loop
# (see .claude/rules/drift-detection-triggering.md: local event ⇒ no poll).
#
# For each +ACTIVE task this script:
#   1. considers ONLY claims whose `host` UDA matches the current hostname — a
#      dead PID on a *different* host is not ours to judge (taskwarrior stores can
#      be TaskChampion-synced across hosts).
#   2. checks `kill -0 "$pid"`; if it fails the claiming process is gone, so the
#      claim is STALE.
#   3. in --apply mode, drains it: `task <uuid> stop` (drops +ACTIVE / drains the
#      clock), clears the `pid` UDA, and annotates `auto-released: claiming PID gone`.
#
# Read-only by default (dry-run) — `--apply` is required to mutate. The loop keys
# on immutable UUIDs (not numeric IDs, which renumber after every close) and every
# taskwarrior mutation passes `rc.confirmation=no` + `</dev/null` so a batch close
# is deterministic and never eats the caller's stdin
# (see .claude/rules/taskwarrior-bulk-operations.md).
#
# Output: structured KEY=VALUE block (see .claude/rules/structured-script-output.md)
# so the SessionStart drift probe and other callers can roll it up. The probe reads
# STALE_CLAIMS for its dry-run finding.
#
# Flags:
#   --apply         Release stale claims (default: dry-run, mutate nothing)
#   --host <name>   Override the host to match against (default: `hostname`).
#                   Primarily for tests; a claim's `host` UDA is compared to this.
#
# Exit codes:
#   0 - OK / WARN (dry-run, releases succeeded, or nothing to do)
#   1 - ERROR (task binary or jq missing — cannot proceed)

set -uo pipefail

apply=false
current_host=""
while [ $# -gt 0 ]; do
  case "$1" in
    --apply) apply=true ;;
    --host) shift; current_host="${1:-}" ;;
    --host=*) current_host="${1#*=}" ;;
    *) ;;
  esac
  shift
done

echo "=== TASKWARRIOR STALE CLAIMS ==="

if ! command -v task >/dev/null 2>&1; then
  echo "TASK_AVAILABLE=false"
  echo "STATUS=ERROR"
  echo "ISSUE_COUNT=0"
  echo "=== END TASKWARRIOR STALE CLAIMS ==="
  exit 1
fi
echo "TASK_AVAILABLE=true"

if ! command -v jq >/dev/null 2>&1; then
  echo "JQ_AVAILABLE=false"
  echo "STATUS=ERROR"
  echo "ISSUE_COUNT=0"
  echo "=== END TASKWARRIOR STALE CLAIMS ==="
  exit 1
fi
echo "JQ_AVAILABLE=true"

[ -n "$current_host" ] || current_host="$(hostname 2>/dev/null || true)"
echo "HOST=${current_host}"
echo "MODE=$([ "$apply" = true ] && echo apply || echo dry-run)"

# Snapshot active claims. `export` returns [] and exits 0 on no matches, so this
# stays parallel-safe (see .claude/rules/parallel-safe-queries.md). Each row is
# TSV: uuid <TAB> pid <TAB> host. Read into an array up front so the mutation
# loop below never shares stdin with the snapshot.
export_json="$(task +ACTIVE export 2>/dev/null || echo '[]')"
[ -n "$export_json" ] || export_json='[]'

mapfile -t claim_rows < <(
  printf '%s' "$export_json" \
    | jq -r '.[] | [.uuid, ((.pid // "") | tostring), (.host // "")] | @tsv' 2>/dev/null || true
)

active_claims="${#claim_rows[@]}"
same_host=0
stale=0
released=0
release_failures=0
stale_uuids=()

for row in "${claim_rows[@]:-}"; do
  [ -n "$row" ] || continue
  uuid="${row%%	*}"
  rest="${row#*	}"
  pid="${rest%%	*}"
  host="${rest#*	}"
  [ -n "$uuid" ] || continue

  # Gate 1: same host only. A claim with no host, or a different host, is not
  # ours to judge — skip it.
  [ -n "$host" ] || continue
  [ "$host" = "$current_host" ] || continue
  same_host=$((same_host + 1))

  # Gate 2: a usable PID. Without a numeric pid we cannot prove the process is
  # gone, so leave the claim alone.
  case "$pid" in
    ''|*[!0-9]*) continue ;;
  esac
  [ "$pid" -gt 0 ] 2>/dev/null || continue

  # Gate 3: is the process alive? kill -0 succeeds iff the PID exists.
  if kill -0 "$pid" 2>/dev/null; then
    continue
  fi

  # Dead PID on this host → stale claim.
  stale=$((stale + 1))
  stale_uuids+=("$uuid")

  if [ "$apply" = true ]; then
    ok=true
    # annotate first (records intent while the task is still addressable), then
    # drain the pid UDA, then stop (drops +ACTIVE). rc.confirmation=no + </dev/null
    # keep the batch deterministic and stdin-safe (taskwarrior-bulk-operations.md).
    task rc.confirmation=no "$uuid" annotate "auto-released: claiming PID gone" </dev/null >/dev/null 2>&1 || ok=false
    task rc.confirmation=no "$uuid" modify pid: </dev/null >/dev/null 2>&1 || ok=false
    task rc.confirmation=no "$uuid" stop </dev/null >/dev/null 2>&1 || ok=false
    if [ "$ok" = true ]; then
      released=$((released + 1))
    else
      release_failures=$((release_failures + 1))
    fi
  fi
done

echo "ACTIVE_CLAIMS=${active_claims}"
echo "SAME_HOST_CLAIMS=${same_host}"
echo "STALE_CLAIMS=${stale}"
echo "RELEASED=${released}"

if [ "${#stale_uuids[@]}" -gt 0 ]; then
  echo "STALE_UUIDS=$(IFS=,; echo "${stale_uuids[*]}")"
fi

if [ "$release_failures" -gt 0 ]; then
  echo "RELEASE_FAILURES=${release_failures}"
  echo "STATUS=WARN"
else
  echo "STATUS=OK"
fi

echo "ISSUE_COUNT=${stale}"
if [ "$stale" -gt 0 ]; then
  echo "ISSUES:"
  for u in "${stale_uuids[@]}"; do
    echo "  - SEVERITY=WARN TYPE=stale_claim UUID=${u} MSG=claiming PID gone"
  done
fi
echo "=== END TASKWARRIOR STALE CLAIMS ==="
exit 0
