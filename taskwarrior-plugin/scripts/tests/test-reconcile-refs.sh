#!/usr/bin/env bash
# test-reconcile-refs.sh — regression tests for reconcile.sh description-text
# and cross-repo ref reconciliation (gaps 1 + 2).
#
# Pins:
#   A. A task with NO ghid/ghpr UDA but a bare #N in its description is selected
#      and classified from the referenced item's state (gap 1).
#   B. A ghid/ghpr UDA task still classifies exactly as before (back-compat).
#   C. A cross-repo ref `owner/repo#N` is resolved with `gh … -R owner/repo`,
#      not the CWD default (gap 2); kind is resolved (pr-then-issue fallback).
#   D. Multi-ref safety: a task whose refs are NOT all done (one still open) is
#      classified live, never closed.
#   E. Multi-ref all-done: every ref closed/merged → stale.
#   F. Multi-ref with a pr-closed among merged refs → aggregate verdict pr-closed
#      (ambiguous; kept out of the bounded --only-verdicts auto-apply set).
#   G. Shorthand `prompt-editor#60` (no owner/ slash) does NOT match → the task
#      is not selected (safe false-negative, never a wrong-repo close).
#
# `task` and `gh` are pure stubs; no network, no real taskwarrior store.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RECONCILE="${SCRIPT_DIR}/../../skills/task-reconcile/scripts/reconcile.sh"

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
[ -f "$RECONCILE" ] || { echo "missing reconcile: $RECONCILE" >&2; exit 1; }

WORK="$(mktemp -d)"
[ -n "$WORK" ] || { echo "mktemp failed" >&2; exit 1; }
trap 'rm -rf "$WORK"' EXIT

BIN="${WORK}/bin"
mkdir -p "$BIN"
IMPORT_CAPTURE="${WORK}/import.json"
GH_LOG="${WORK}/gh.log"

U1="11111111-1111-1111-1111-111111111111"  # ghpr 10 UDA        → MERGED  → pr-merged
U2="22222222-2222-2222-2222-222222222222"  # desc bare #20      → PR MERGED → pr-merged
U3="33333333-3333-3333-3333-333333333333"  # desc owner/repo#30 → ISSUE CLOSED (cross-repo) → issue-closed
U4="44444444-4444-4444-4444-444444444444"  # desc #40,#41,#42   → CLOSED,CLOSED,OPEN → live
U5="55555555-5555-5555-5555-555555555555"  # desc #50,#51       → CLOSED,CLOSED → issue-closed
U6="66666666-6666-6666-6666-666666666666"  # desc prompt-editor#60 (shorthand) → NOT selected
U7="77777777-7777-7777-7777-777777777777"  # desc #70,#71       → PR MERGED, PR CLOSED → pr-closed

# Stub `task`: import captures stdin; +BLOCKING → []; export → the fixture.
cat > "${BIN}/task" <<SH
#!/usr/bin/env bash
for a in "\$@"; do [ "\$a" = "import" ] && { cat > "${IMPORT_CAPTURE}"; exit 0; }; done
for a in "\$@"; do [ "\$a" = "+BLOCKING" ] && { echo "[]"; exit 0; }; done
cat <<'JSON'
[{"id":1,"uuid":"${U1}","project":"alpha","ghpr":"10.000000","description":"Merge touch-manager release"},
 {"id":2,"uuid":"${U2}","project":"alpha","description":"Merge PR #20 now"},
 {"id":3,"uuid":"${U3}","project":"beta","description":"track laurigates/other-repo#30 monitoring"},
 {"id":4,"uuid":"${U4}","project":"beta","description":"Monitor #40, #41, #42 write-tool issues"},
 {"id":5,"uuid":"${U5}","project":"gamma","description":"Monitor #50 and #51 both landed"},
 {"id":6,"uuid":"${U6}","project":"gamma","description":"publish prompt-editor#60 to registry"},
 {"id":7,"uuid":"${U7}","project":"delta","description":"land #70, close #71"}]
JSON
SH
chmod +x "${BIN}/task"

# Stub `gh`: auth OK; parse kind/num/-R; PR-numbers 10/20/70 MERGED, 71 CLOSED;
# every other number is an ISSUE (so `pr view` returns empty → issue fallback):
# 30/40/41/50/51 CLOSED, 42 OPEN. Records every invocation to GH_LOG.
cat > "${BIN}/gh" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$GH_LOG"
[ "$1 $2" = "auth status" ] && exit 0
kind="$1"; shift 2 2>/dev/null || true
num=""; repo=""
while [ $# -gt 0 ]; do
  case "$1" in
    -R) repo="${2:-}"; shift 2; continue ;;
    --json|--jq) shift 2; continue ;;
    [0-9]*) num="$1"; shift; continue ;;
    *) shift ;;
  esac
done
if [ "$kind" = "pr" ]; then
  case "$num" in 10|20|70) echo MERGED ;; 71) echo CLOSED ;; *) : ;; esac
elif [ "$kind" = "issue" ]; then
  case "$num" in 30|40|41|50|51) echo CLOSED ;; 42) echo OPEN ;; *) : ;; esac
fi
exit 0
SH
chmod +x "${BIN}/gh"

run_reconcile() { GH_LOG="$GH_LOG" PATH="${BIN}:$PATH" bash "$RECONCILE" --all "$@" 2>/dev/null; }
field() { printf '%s\n' "$2" | grep -m1 "^$1=" | cut -d= -f2-; }
task_field() { # task_field <uuid> <key> <output>
  printf '%s\n' "$3" | grep "uuid=$1 " | grep -o "$2=[^ ]*" | cut -d= -f2-
}

# --- Dry run: selection + classification -----------------------------------
: > "$GH_LOG"
out=$(run_reconcile)
check "TOTAL_LINKED excludes shorthand-only task" "6" "$(field TOTAL_LINKED "$out")"
check "G: shorthand task not selected (no TASK line)" "" \
  "$(printf '%s\n' "$out" | grep -c "uuid=${U6} " | grep -v '^0$' || true)"
check "B: ghpr UDA back-compat → pr-merged" "pr-merged" "$(task_field "$U1" verdict "$out")"
check "A: bare #N in description → pr-merged" "pr-merged" "$(task_field "$U2" verdict "$out")"
check "C: cross-repo ref → issue-closed" "issue-closed" "$(task_field "$U3" verdict "$out")"
check "D: multi-ref with an open ref → live" "live" "$(task_field "$U4" verdict "$out")"
check "E: multi-ref all closed → issue-closed" "issue-closed" "$(task_field "$U5" verdict "$out")"
check "F: multi-ref merged+closed → pr-closed" "pr-closed" "$(task_field "$U7" verdict "$out")"
check "STALE_COUNT (u1,u2,u3,u5,u7)" "5" "$(field STALE_COUNT "$out")"
check "C: cross-repo used -R laurigates/other-repo" "yes" \
  "$(grep -q -- '-R laurigates/other-repo' "$GH_LOG" && echo yes || echo no)"

# --- Apply with the bounded allowlist --------------------------------------
: > "$IMPORT_CAPTURE"; : > "$GH_LOG"
out=$(run_reconcile --apply --only-verdicts=pr-merged,issue-closed)
check "bounded apply closes 4 (u1,u2,u3,u5)" "4" "$(field CLOSED_COUNT "$out")"
check "F: pr-closed task reported method=keep" "keep" "$(task_field "$U7" method "$out")"
check "u7 NOT in import payload" "0" \
  "$(jq --arg u "$U7" '[.[]|select(.uuid==$u)]|length' "$IMPORT_CAPTURE" 2>/dev/null)"
check "u3 (cross-repo issue) IS closed" "1" \
  "$(jq --arg u "$U3" '[.[]|select(.uuid==$u)]|length' "$IMPORT_CAPTURE" 2>/dev/null)"
check "u4 (live) never closed" "0" \
  "$(jq --arg u "$U4" '[.[]|select(.uuid==$u)]|length' "$IMPORT_CAPTURE" 2>/dev/null)"

# --- Apply WITHOUT allowlist closes every stale verdict (back-compat) -------
: > "$IMPORT_CAPTURE"
out=$(run_reconcile --apply)
check "unbounded apply closes all 5 stale" "5" "$(field CLOSED_COUNT "$out")"
check "u7 pr-closed IS closed without allowlist" "1" \
  "$(jq --arg u "$U7" '[.[]|select(.uuid==$u)]|length' "$IMPORT_CAPTURE" 2>/dev/null)"

# --- Summary ----------------------------------------------------------------
echo "=== RECONCILE REFS TEST ==="
echo "PASS=${pass}"
echo "FAIL=${fail}"
echo "STATUS=$([ "$fail" -eq 0 ] && echo OK || echo ERROR)"
echo "=== END RECONCILE REFS TEST ==="
[ "$fail" -eq 0 ]
