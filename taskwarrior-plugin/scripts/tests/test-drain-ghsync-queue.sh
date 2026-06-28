#!/usr/bin/env bash
# test-drain-ghsync-queue.sh — regression tests for drain-ghsync-queue.sh,
# the SessionStart drain for the on-exit gh-sync queue (issue #1810).
#
# Pins:
#   1. empty / missing queue        → DRAINED=0, STATUS=OK (no-op)
#   2. queued UUIDs                 → resolved to projects (one batched `task
#                                     export`) and the matching drift cache files
#                                     are invalidated; the queue is cleared
#   3. an empty-project task        → busts the `_all` cache key
#   4. a corrupt/duplicate queue    → garbage filtered, dups collapsed, queue
#                                     still cleared (its own failure mode)
#   5. task unavailable             → fail open: queue cleared, nothing busted
#
# `task` is a pure stub; no network, no real taskwarrior store.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DRAIN="${SCRIPT_DIR}/../drain-ghsync-queue.sh"

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
[ -f "$DRAIN" ] || { echo "missing drain: $DRAIN" >&2; exit 1; }

WORK="$(mktemp -d)"
[ -n "$WORK" ] || { echo "mktemp failed" >&2; exit 1; }
trap 'rm -rf "$WORK"' EXIT

QUEUE="${WORK}/ghsync.queue"
CACHE="${WORK}/cache"
BIN="${WORK}/bin"
mkdir -p "$CACHE" "$BIN"

U1="11111111-1111-1111-1111-111111111111"
U2="22222222-2222-2222-2222-222222222222"
U3="33333333-3333-3333-3333-333333333333"

# Stub `task`: `export` emits a fixed three-row result (alpha, beta, empty
# project); `_get` returns a data dir. Args (the UUIDs) are ignored.
cat > "${BIN}/task" <<'SH'
#!/usr/bin/env bash
for a in "$@"; do
  if [ "$a" = "_get" ]; then echo "$HOME/.task"; exit 0; fi
done
cat <<'JSON'
[{"uuid":"11111111-1111-1111-1111-111111111111","project":"alpha"},
 {"uuid":"22222222-2222-2222-2222-222222222222","project":"beta"},
 {"uuid":"33333333-3333-3333-3333-333333333333","project":""}]
JSON
SH
chmod +x "${BIN}/task"

run_drain() { # run_drain — emits the drain's structured output
  CLAUDE_TASKWARRIOR_GHSYNC_QUEUE="$QUEUE" \
  CLAUDE_TASKWARRIOR_DRIFT_CACHE_DIR="$CACHE" \
  PATH="${BIN}:$PATH" bash "$DRAIN" 2>/dev/null
}
field() { grep -m1 "^$1=" <<<"$2" | cut -d= -f2-; }

# --- Test 1: empty queue → no-op --------------------------------------------
: > "$QUEUE"
out=$(run_drain)
check "1: empty queue → DRAINED=0" "0" "$(field DRAINED "$out")"
check "1: empty queue → STATUS=OK" "OK" "$(field STATUS "$out")"

# --- Test 2+3+4: dedup, garbage filter, project resolution, cache bust -------
seed() { printf 'EPOCH=1\nSTALE=3\n' > "${CACHE}/$1.stale"; }
seed alpha; seed beta; seed gamma; seed _all
{
  echo "$U1"
  echo "not-a-uuid garbage"
  echo "$U2"
  echo "$U1"          # duplicate
  echo ""
  echo "$U3"
} > "$QUEUE"
out=$(run_drain)
check "2: three distinct uuids drained (dups/garbage dropped)" "3" "$(field DRAINED "$out")"
check "2: alpha cache invalidated" "no" "$([ -e "${CACHE}/alpha.stale" ] && echo yes || echo no)"
check "2: beta cache invalidated"  "no" "$([ -e "${CACHE}/beta.stale" ] && echo yes || echo no)"
check "2: unrelated gamma cache kept" "yes" "$([ -e "${CACHE}/gamma.stale" ] && echo yes || echo no)"
check "3: empty-project task busts _all cache" "no" "$([ -e "${CACHE}/_all.stale" ] && echo yes || echo no)"
check "2: three cache files invalidated" "3" "$(field CACHE_INVALIDATED "$out")"
check "4: queue cleared after drain" "0" "$(grep -c . "$QUEUE" 2>/dev/null)"

# --- Test 5: task unavailable → fail open -----------------------------------
seed alpha
echo "$U1" > "$QUEUE"
NOTASK="${WORK}/notask"; mkdir -p "$NOTASK"
for t in bash jq grep cut tr rm mkdir printf cat dirname; do
  if src=$(command -v "$t" 2>/dev/null); then ln -s "$src" "$NOTASK/$t" 2>/dev/null || true; fi
done
out=$(CLAUDE_TASKWARRIOR_GHSYNC_QUEUE="$QUEUE" CLAUDE_TASKWARRIOR_DRIFT_CACHE_DIR="$CACHE" \
  PATH="$NOTASK" bash "$DRAIN" 2>/dev/null)
check "5: no task → STATUS=OK (fail open)" "OK" "$(field STATUS "$out")"
check "5: no task → nothing invalidated" "0" "$(field CACHE_INVALIDATED "$out")"
check "5: no task → queue still cleared" "0" "$(grep -c . "$QUEUE" 2>/dev/null)"

# --- Summary ----------------------------------------------------------------
echo "=== GHSYNC DRAIN TEST ==="
echo "PASS=${pass}"
echo "FAIL=${fail}"
echo "STATUS=$([ "$fail" -eq 0 ] && echo OK || echo ERROR)"
echo "=== END GHSYNC DRAIN TEST ==="
[ "$fail" -eq 0 ]
