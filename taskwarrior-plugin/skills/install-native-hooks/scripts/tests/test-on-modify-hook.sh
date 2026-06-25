#!/usr/bin/env bash
# test-on-modify-hook.sh — regression tests for the on-modify-taskwarrior-plugin
# native hook's claim invariant + stale-claim expiry (issue #1808).
#
# The hook receives two lines of JSON on stdin (original task, modified task)
# and must echo the (possibly repaired) modified task as the FIRST line of
# stdout; later stdout lines are advisory feedback. These tests pin the
# semantic invariants a future bulk edit must not silently drop:
#   1. newly +ACTIVE (start set, was unset) with no agent → identity stamped
#      from the env (the canonical `claude-<sid>` agent value coworker-check reads)
#   2. claim takeover (agent A → agent B) → warns, does NOT reject, does NOT drain
#   3. a modify touching a claim older than the TTL → drops +ACTIVE (start) and
#      drains identity UDAs
#   4. a fresh +ACTIVE claim (start ≈ now) is NOT expired
#   5. malformed JSON → fails open (echoes input unchanged, exit 0)
#   6. missing jq → fails open
#   7. the hyphenated-tag warning still fires
#   8. opt-out env (CLAUDE_TASKWARRIOR_NO_CLAIM_EXPIRY=1) suppresses expiry
#
# The first stdout line is the task JSON; assertions parse it with jq.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="${SCRIPT_DIR}/../../templates/on-modify-taskwarrior-plugin"

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

# run_hook <original-json> <modified-json> — emits combined stdout (env from caller).
run_hook() { printf '%s\n%s\n' "$1" "$2" | bash "$HOOK" 2>/dev/null; }
first_line() { printf '%s\n' "$1" | head -1; }

# compact UTC stamp helper (matches taskwarrior export format)
stamp() { # stamp <seconds-ago>
  local secs="$1" e
  e=$(date -u +%s)
  e=$((e - secs))
  if date -u -d "@$e" +%Y%m%dT%H%M%SZ 2>/dev/null; then return 0; fi
  date -u -r "$e" +%Y%m%dT%H%M%SZ 2>/dev/null   # BSD
}

NOW=$(stamp 0)
OLD=$(stamp 36000)   # 10h ago — past the 4h default TTL

# --- Test 1: newly +ACTIVE without agent → identity stamped ------------------
orig='{"description":"do a thing","status":"pending"}'
mod="{\"description\":\"do a thing\",\"status\":\"pending\",\"start\":\"$NOW\"}"
out=$(CLAUDE_SESSION_ID="abcdef1234567890" run_hook "$orig" "$mod")
line1=$(first_line "$out")
got_agent=$(printf '%s' "$line1" | jq -r '.agent // ""' 2>/dev/null)
check "1: agent stamped on newly +ACTIVE task" "claude-abcdef12" "$got_agent"
got_start=$(printf '%s' "$line1" | jq -r '.start // ""' 2>/dev/null)
check "1: start preserved on fresh claim" "$NOW" "$got_start"

# --- Test 2: claim takeover warns, no reject, no drain -----------------------
orig='{"description":"x","status":"pending","start":"'"$NOW"'","agent":"claude-aaaaaaaa"}'
mod='{"description":"x","status":"pending","start":"'"$NOW"'","agent":"claude-bbbbbbbb"}'
out=$(run_hook "$orig" "$mod")
line1=$(first_line "$out")
got_agent=$(printf '%s' "$line1" | jq -r '.agent // ""' 2>/dev/null)
check "2: takeover keeps the new agent (no drain)" "claude-bbbbbbbb" "$got_agent"
case "$out" in *"claim taken over"*) warned=yes ;; *) warned=no ;; esac
check "2: takeover emits a warning" "yes" "$warned"

# --- Test 3: stale claim → drop +ACTIVE + drain identity ---------------------
orig='{"description":"x","status":"pending","start":"'"$OLD"'","agent":"claude-aaaaaaaa","host":"h","branch":"b","worktree":"/w"}'
mod="$orig"
out=$(run_hook "$orig" "$mod")
line1=$(first_line "$out")
got_start=$(printf '%s' "$line1" | jq -r '.start // "GONE"' 2>/dev/null)
got_agent=$(printf '%s' "$line1" | jq -r '.agent // "GONE"' 2>/dev/null)
check "3: stale claim drops +ACTIVE (start removed)" "GONE" "$got_start"
check "3: stale claim drains agent UDA" "GONE" "$got_agent"
case "$out" in *"expired stale claim"*) expired=yes ;; *) expired=no ;; esac
check "3: stale claim emits expiry feedback" "yes" "$expired"

# --- Test 4: fresh claim is NOT expired -------------------------------------
orig='{"description":"x","status":"pending","start":"'"$NOW"'","agent":"claude-aaaaaaaa"}'
mod="$orig"
out=$(run_hook "$orig" "$mod")
line1=$(first_line "$out")
got_start=$(printf '%s' "$line1" | jq -r '.start // "GONE"' 2>/dev/null)
check "4: fresh claim keeps +ACTIVE" "$NOW" "$got_start"

# --- Test 5: malformed JSON fails open --------------------------------------
out=$(run_hook '{"description":"orig"}' 'not json at all')
rc_line=$(first_line "$out")
check "5: malformed modified line echoed back unchanged" "not json at all" "$rc_line"
printf '%s\n%s\n' '{"a":1}' 'still not json' | bash "$HOOK" >/dev/null 2>&1
check "5: malformed JSON still exits 0 (fail open)" "0" "$?"

# --- Test 6: missing jq fails open ------------------------------------------
NOJQ_BIN="$(mktemp -d)"
[ -n "$NOJQ_BIN" ] || { echo "mktemp failed" >&2; exit 1; }
trap 'rm -rf "$NOJQ_BIN"' EXIT
for t in bash date head printf hostname git grep; do
  if src=$(command -v "$t" 2>/dev/null); then ln -s "$src" "$NOJQ_BIN/$t" 2>/dev/null || true; fi
done
mod='{"description":"x","status":"pending","start":"'"$OLD"'"}'
out=$(printf '%s\n%s\n' '{}' "$mod" | PATH="$NOJQ_BIN" bash "$HOOK" 2>/dev/null)
check "6: without jq the modified task passes through unchanged" "$mod" "$(first_line "$out")"

# --- Test 7: hyphenated-tag warning still fires -----------------------------
orig='{"description":"x","status":"pending"}'
mod='{"description":"do +bad-tag now","status":"pending"}'
out=$(run_hook "$orig" "$mod")
case "$out" in *"hyphenated +tag"*) tagwarn=yes ;; *) tagwarn=no ;; esac
check "7: hyphenated-tag warning preserved" "yes" "$tagwarn"

# --- Test 8: opt-out env suppresses expiry ----------------------------------
orig='{"description":"x","status":"pending","start":"'"$OLD"'","agent":"claude-aaaaaaaa"}'
mod="$orig"
out=$(CLAUDE_TASKWARRIOR_NO_CLAIM_EXPIRY=1 run_hook "$orig" "$mod")
line1=$(first_line "$out")
got_start=$(printf '%s' "$line1" | jq -r '.start // "GONE"' 2>/dev/null)
check "8: opt-out keeps stale claim +ACTIVE" "$OLD" "$got_start"

# --- Summary ----------------------------------------------------------------
echo "=== ON-MODIFY HOOK TEST ==="
echo "PASS=${pass}"
echo "FAIL=${fail}"
echo "STATUS=$([ "$fail" -eq 0 ] && echo OK || echo ERROR)"
echo "=== END ON-MODIFY HOOK TEST ==="
[ "$fail" -eq 0 ]
