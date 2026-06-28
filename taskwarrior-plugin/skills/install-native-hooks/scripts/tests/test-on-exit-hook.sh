#!/usr/bin/env bash
# test-on-exit-hook.sh — regression tests for the on-exit-taskwarrior-plugin
# native hook's batch gh-sync queue + coworker-marker upkeep (issue #1810).
#
# on-exit receives the WHOLE changeset on stdin (one task JSON per line) and its
# stdout is feedback only. These tests pin the semantic invariants a future bulk
# edit must not silently drop:
#   #4 QUEUE
#     1. a touched task carrying `ghid` (issue) → its UUID is appended to the queue
#     2. a touched task carrying `ghpr` (PR)    → its UUID is appended
#     3. a touched task with neither linkage UDA → NOT queued
#     4. multiple linked tasks in ONE invocation → all queued (whole-changeset)
#     5. CLAUDE_TASKWARRIOR_NO_GHSYNC_QUEUE=1 → nothing queued
#   #5 MARKER UPKEEP
#     6. now-+ACTIVE task (pid+worktree, no marker) → marker written
#     7. an existing skill marker is NOT clobbered (skip-if-exists; baselines kept)
#     8. now-inactive task (pid+worktree, marker present) → marker removed
#     9. removal guard: a sibling active claim (same pid+worktree) keeps the marker
#    10. no marker management without a worktree, or without a numeric pid
#   GENERAL
#    11. missing jq → fail open (exit 0, no queue write)

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="${SCRIPT_DIR}/../../templates/on-exit-taskwarrior-plugin"

pass=0
fail=0
check() { # check <description> <expected> <actual>
  if [ "$2" = "$3" ]; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    printf 'FAIL: %s\n  expected: %s\n  actual:   %s\n' "$1" "$2" "$3" >&2
  fi
}

if ! command -v jq >/dev/null 2>&1; then
  echo "SKIP: jq not available" >&2
  exit 0
fi
[ -f "$HOOK" ] || { echo "missing hook: $HOOK" >&2; exit 1; }

WORK="$(mktemp -d)"
[ -n "$WORK" ] || { echo "mktemp failed" >&2; exit 1; }
trap 'rm -rf "$WORK"' EXIT

QUEUE="${WORK}/ghsync.queue"

# A real git repo to stand in for a task's `worktree` UDA.
WT="${WORK}/repo"
mkdir -p "$WT"
git -C "$WT" init -q 2>/dev/null
GITDIR="$(git -C "$WT" rev-parse --absolute-git-dir 2>/dev/null)"

U1="11111111-1111-1111-1111-111111111111"
U2="22222222-2222-2222-2222-222222222222"
U3="33333333-3333-3333-3333-333333333333"

# run_hook <line...> — feeds each arg as a changeset line; queue env preset.
run_hook() {
  printf '%s\n' "$@" | CLAUDE_TASKWARRIOR_GHSYNC_QUEUE="$QUEUE" bash "$HOOK" 2>/dev/null
}
queue_has() { grep -qxF "$1" "$QUEUE" 2>/dev/null && echo yes || echo no; }
queue_count() { grep -c . "$QUEUE" 2>/dev/null; }

# --- #4.1: ghid linkage → queued --------------------------------------------
: > "$QUEUE"
run_hook "{\"uuid\":\"$U1\",\"description\":\"x\",\"ghid\":42}" >/dev/null
check "1: task with ghid is queued" "yes" "$(queue_has "$U1")"

# --- #4.2: ghpr linkage → queued --------------------------------------------
: > "$QUEUE"
run_hook "{\"uuid\":\"$U2\",\"description\":\"x\",\"ghpr\":99}" >/dev/null
check "2: task with ghpr is queued" "yes" "$(queue_has "$U2")"

# --- #4.3: no linkage UDA → not queued --------------------------------------
: > "$QUEUE"
run_hook "{\"uuid\":\"$U3\",\"description\":\"x\"}" >/dev/null
check "3: task with no linkage is NOT queued" "0" "$(queue_count)"

# --- #4.4: whole-changeset — multiple linked tasks in one invocation --------
: > "$QUEUE"
run_hook \
  "{\"uuid\":\"$U1\",\"description\":\"a\",\"ghid\":1}" \
  "{\"uuid\":\"$U3\",\"description\":\"b\"}" \
  "{\"uuid\":\"$U2\",\"description\":\"c\",\"ghpr\":2}" >/dev/null
check "4: first linked uuid queued" "yes" "$(queue_has "$U1")"
check "4: second linked uuid queued" "yes" "$(queue_has "$U2")"
check "4: unlinked task in same changeset not queued" "no" "$(queue_has "$U3")"

# --- #4.5: opt-out env suppresses queueing ----------------------------------
: > "$QUEUE"
printf '%s\n' "{\"uuid\":\"$U1\",\"ghid\":7}" \
  | CLAUDE_TASKWARRIOR_GHSYNC_QUEUE="$QUEUE" \
    CLAUDE_TASKWARRIOR_NO_GHSYNC_QUEUE=1 bash "$HOOK" >/dev/null 2>&1
check "5: opt-out env queues nothing" "0" "$(queue_count)"

# --- #5.6: now-+ACTIVE task → marker written --------------------------------
: > "$QUEUE"
rm -f "${GITDIR}/.claude-session-"*
run_hook "{\"uuid\":\"$U1\",\"start\":\"20260628T000000Z\",\"pid\":\"54321\",\"worktree\":\"$WT\"}" >/dev/null
check "6: marker written for raw +ACTIVE claim" "yes" \
  "$([ -e "${GITDIR}/.claude-session-54321" ] && echo yes || echo no)"

# --- #5.7: existing skill marker is not clobbered ---------------------------
SKILL_MARKER="${GITDIR}/.claude-session-77777"
printf 'pid=77777\nstarted=skill\nhost=h\ncwd=%s\n' "$WT" > "$SKILL_MARKER"
printf 'baseline-status\n' > "${GITDIR}/.claude-baseline-77777.status"
run_hook "{\"uuid\":\"$U1\",\"start\":\"20260628T000000Z\",\"pid\":\"77777\",\"worktree\":\"$WT\"}" >/dev/null
check "7: skill marker contents preserved (skip-if-exists)" "started=skill" \
  "$(grep -m1 '^started=' "$SKILL_MARKER" 2>/dev/null)"
check "7: skill baseline snapshot preserved" "yes" \
  "$([ -e "${GITDIR}/.claude-baseline-77777.status" ] && echo yes || echo no)"

# --- #5.8: now-inactive task → stale marker removed -------------------------
MARK="${GITDIR}/.claude-session-44444"
printf 'pid=44444\nsource=taskwarrior-on-exit\n' > "$MARK"
printf 'x\n' > "${GITDIR}/.claude-baseline-44444.status"
run_hook "{\"uuid\":\"$U1\",\"pid\":\"44444\",\"worktree\":\"$WT\"}" >/dev/null
check "8: stale marker removed after raw stop/done" "no" \
  "$([ -e "$MARK" ] && echo yes || echo no)"
check "8: companion baseline removed too" "no" \
  "$([ -e "${GITDIR}/.claude-baseline-44444.status" ] && echo yes || echo no)"

# --- #5.9: removal guard — a sibling active claim keeps the marker ----------
GUARD="${GITDIR}/.claude-session-44444"
printf 'pid=44444\n' > "$GUARD"
run_hook \
  "{\"uuid\":\"$U1\",\"pid\":\"44444\",\"worktree\":\"$WT\"}" \
  "{\"uuid\":\"$U2\",\"start\":\"20260628T000000Z\",\"pid\":\"44444\",\"worktree\":\"$WT\"}" >/dev/null
check "9: marker kept when a sibling claim is still active (same pid+worktree)" "yes" \
  "$([ -e "$GUARD" ] && echo yes || echo no)"
rm -f "$GUARD"

# --- #5.10: no marker management without worktree / numeric pid -------------
before=$(find "$GITDIR" -name '.claude-session-*' | wc -l | tr -d ' ')
run_hook "{\"uuid\":\"$U1\",\"start\":\"20260628T000000Z\",\"pid\":\"99999\"}" >/dev/null
run_hook "{\"uuid\":\"$U1\",\"start\":\"20260628T000000Z\",\"worktree\":\"$WT\"}" >/dev/null
after=$(find "$GITDIR" -name '.claude-session-*' | wc -l | tr -d ' ')
check "10: no marker created without worktree or numeric pid" "$before" "$after"

# --- #11: missing jq → fail open --------------------------------------------
: > "$QUEUE"
NOJQ_BIN="${WORK}/nojq"
mkdir -p "$NOJQ_BIN"
for t in bash date hostname git grep printf find; do
  if src=$(command -v "$t" 2>/dev/null); then ln -s "$src" "$NOJQ_BIN/$t" 2>/dev/null || true; fi
done
printf '%s\n' "{\"uuid\":\"$U1\",\"ghid\":5}" \
  | PATH="$NOJQ_BIN" CLAUDE_TASKWARRIOR_GHSYNC_QUEUE="$QUEUE" bash "$HOOK" >/dev/null 2>&1
check "11: missing jq exits 0 (fail open)" "0" "$?"
check "11: missing jq queues nothing" "0" "$(queue_count)"

# --- Summary ----------------------------------------------------------------
echo "=== ON-EXIT HOOK TEST ==="
echo "PASS=${pass}"
echo "FAIL=${fail}"
echo "STATUS=$([ "$fail" -eq 0 ] && echo OK || echo ERROR)"
echo "=== END ON-EXIT HOOK TEST ==="
[ "$fail" -eq 0 ]
