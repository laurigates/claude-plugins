#!/usr/bin/env bash
# shellcheck disable=SC2016,SC2034  # check() evals single-quoted assertions; out/rc are read inside them
# Tests for unfinished-sessions.sh — the reader for the session-ledger.sh
# ledger. Pins the output contract session-spinup-nudge.sh parses
# (UNFINISHED_COUNT / UNFINISHED_HERE / HERE_IDS) and the --list rows a
# person or skill reads to resume a session.
#
# Run: bash session-plugin/scripts/tests/test-unfinished-sessions.sh
set -euo pipefail

# Neutralize any inherited git context before building sandbox repos (issues #1745, #3080).
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_OBJECT_DIRECTORY \
  GIT_COMMON_DIR GIT_NAMESPACE GIT_PREFIX

SCRIPT="$(cd "$(dirname "$0")/.." && pwd)/unfinished-sessions.sh"
PASS=0
FAIL=0

LEDGER=$(mktemp -d) || { echo "mktemp -d failed" >&2; exit 1; }
REPO=$(mktemp -d) || { echo "mktemp -d failed" >&2; exit 1; }
OTHER=$(mktemp -d) || { echo "mktemp -d failed" >&2; exit 1; }
trap 'rm -rf "$LEDGER" "$REPO" "$OTHER"' EXIT
git -C "$REPO" init -q
mkdir -p "$REPO/sub"
TRANSCRIPT=$(mktemp) || { echo "mktemp failed" >&2; exit 1; }
trap 'rm -rf "$LEDGER" "$REPO" "$OTHER" "$TRANSCRIPT"' EXIT

entry() { # id cwd last_active ended_at(or null) transcript
    jq -n --arg id "$1" --arg cwd "$2" --arg la "$3" --arg end "$4" --arg tp "$5" \
        '{session_id: $id, cwd: $cwd, transcript_path: $tp, first_seen: $la, last_active: $la,
          ended_at: (if $end == "null" then null else $end end), end_reason: null,
          user_turns: 4, last_user_message: "deploy key\tstill to rotate"}' > "$LEDGER/$1.json"
}

run() { SESSION_LEDGER_DIR="$LEDGER" bash "$SCRIPT" "$@"; }
ok()  { printf "  PASS: %s\n" "$1"; PASS=$((PASS + 1)); }
bad() { printf "  FAIL: %s\n" "$1"; FAIL=$((FAIL + 1)); }
check() { if eval "$2"; then ok "$1"; else bad "$1"; fi; }

echo "=== unfinished-sessions tests ==="

echo ""
echo "empty ledger:"
out=$(SESSION_LEDGER_DIR="$LEDGER/missing" bash "$SCRIPT" --summary); rc=$?
check "missing ledger dir exits 0" '[ "$rc" = 0 ]'
check "missing ledger dir counts zero" 'grep -qx "UNFINISHED_COUNT=0" <<<"$out"'
out=$(run --list)
check "empty list is STATUS=OK with no rows" 'grep -qx "STATUS=OK" <<<"$out" && ! grep -q "^SESSIONS:" <<<"$out"'

entry s-old  "$REPO"     2026-11-20T10:00:00Z 2026-11-20T11:00:00Z "$TRANSCRIPT"
entry s-new  "$REPO/sub" 2026-11-24T10:00:00Z null                 "$TRANSCRIPT"
entry s-far  "$OTHER"    2026-11-23T10:00:00Z 2026-11-23T11:00:00Z "$TRANSCRIPT"
entry s-self "$REPO"     2026-11-25T10:00:00Z null                 "$TRANSCRIPT"
echo "garbage" > "$LEDGER/broken.json"
: > "$LEDGER/.s-tmp.abc123"

echo ""
echo "summary:"
out=$(run --summary --cwd "$REPO" --exclude s-self)
check "counts every entry except the excluded one" 'grep -qx "UNFINISHED_COUNT=3" <<<"$out"'
check "open = entries without ended_at" 'grep -qx "UNFINISHED_OPEN=1" <<<"$out"'
check "here includes subdirectories of the same repo" 'grep -qx "UNFINISHED_HERE=2" <<<"$out"'
check "HERE_IDS lists most recent first" 'grep -qx "HERE_IDS=s-new,s-old" <<<"$out"'
out=$(run --summary)
check "no --cwd means UNFINISHED_HERE=0" 'grep -qx "UNFINISHED_HERE=0" <<<"$out" && grep -qx "UNFINISHED_COUNT=4" <<<"$out"'

echo ""
echo "list:"
out=$(run --list --exclude s-self)
check "list section is delimited" 'grep -qx "=== UNFINISHED SESSIONS ===" <<<"$out" && grep -qx "=== END UNFINISHED SESSIONS ===" <<<"$out"'
check "list row carries ID, STATE and CWD (resume coordinates)" \
    'grep -q "^  - ID=s-new STATE=open .* CWD=$REPO/sub MSG=" <<<"$out"'
check "closed session reads STATE=closed" 'grep -q "ID=s-old STATE=closed" <<<"$out"'
check "rows are most recent first" '[ "$(grep -o "ID=s-[a-z]*" <<<"$out" | head -1)" = "ID=s-new" ]'
check "tabs in the message are flattened" '! grep -q "$(printf "\t")" <<<"$out"'
check "malformed entry is skipped" '! grep -q "broken" <<<"$out"'

echo ""
echo "dismiss and prune:"
out=$(run --dismiss s-old ../escape)
check "dismiss removes the named entry" '[ ! -e "$LEDGER/s-old.json" ] && grep -qx "REMOVED=1" <<<"$out"'
check "dismiss ignores path-like ids" '[ -e "$LEDGER/s-new.json" ]'
rm -f "$TRANSCRIPT"
entry s-gone "$REPO" 2026-11-21T10:00:00Z null "$LEDGER/nonexistent.jsonl"
out=$(run --prune)
check "prune removes entries whose transcript is gone" '[ ! -e "$LEDGER/s-gone.json" ] && [ ! -e "$LEDGER/s-new.json" ]'

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
