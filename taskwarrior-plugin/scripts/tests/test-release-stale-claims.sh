#!/usr/bin/env bash
# test-release-stale-claims.sh — regression tests for release-stale-claims.sh,
# the deterministic dead-PID +ACTIVE claim auto-release (issue #1792).
#
# Pins:
#   1. dead PID on this host        → counted STALE; --apply releases it
#                                      (stop + clear pid + annotate, by UUID)
#   2. live PID (current shell $$)  → untouched (not stale)
#   3. claim with a foreign host    → untouched (not ours to judge)
#   4. dry-run (default)            → mutates NOTHING (no stop/modify/annotate)
#   5. empty +ACTIVE set            → STALE_CLAIMS=0, STATUS=OK
#
# `task` is a pure stub: `export` emits a fixture JSON, every other invocation is
# recorded to a mutation log. No network, no real taskwarrior store.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RELEASE="${SCRIPT_DIR}/../release-stale-claims.sh"

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
[ -f "$RELEASE" ] || { echo "missing script: $RELEASE" >&2; exit 1; }

WORK="$(mktemp -d)"
[ -n "$WORK" ] || { echo "mktemp failed" >&2; exit 1; }
trap 'rm -rf "$WORK"' EXIT

BIN="${WORK}/bin"
mkdir -p "$BIN"
EXPORT_JSON="${WORK}/active.json"
MUTATION_LOG="${WORK}/mutations.log"

U_DEAD="aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa"   # dead PID, this host  → stale
U_LIVE="bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb"   # live PID, this host  → untouched
U_FOREIGN="cccccccc-cccc-cccc-cccc-cccccccccccc" # dead PID, other host → untouched

HOST="testhost"
LIVE_PID="$$"            # the test runner itself — guaranteed alive
DEAD_PID="2147483646"   # max-ish PID, effectively never present → kill -0 fails

# Fixture: three +ACTIVE claims.
cat > "$EXPORT_JSON" <<JSON
[
  {"uuid":"${U_DEAD}","pid":${DEAD_PID},"host":"${HOST}"},
  {"uuid":"${U_LIVE}","pid":${LIVE_PID},"host":"${HOST}"},
  {"uuid":"${U_FOREIGN}","pid":${DEAD_PID},"host":"otherhost"}
]
JSON

# Stub `task`: `export` prints the fixture; everything else is a mutation we log.
cat > "${BIN}/task" <<'SH'
#!/usr/bin/env bash
for a in "$@"; do
  if [ "$a" = "export" ]; then cat "$FAKE_EXPORT_JSON"; exit 0; fi
done
printf '%s\n' "$*" >> "$MUTATION_LOG"
exit 0
SH
chmod +x "${BIN}/task"

run_release() { # run_release [extra-args...]
  FAKE_EXPORT_JSON="$EXPORT_JSON" MUTATION_LOG="$MUTATION_LOG" \
    PATH="${BIN}:$PATH" bash "$RELEASE" --host "$HOST" "$@" 2>/dev/null
}
field() { grep -m1 "^$1=" <<<"$2" | cut -d= -f2-; }

# --- Test 1+2+3+4: dry-run classification, no mutation -----------------------
: > "$MUTATION_LOG"
out=$(run_release)
check "dry-run: 3 active claims seen" "3" "$(field ACTIVE_CLAIMS "$out")"
check "1: exactly one dead-PID same-host claim is stale" "1" "$(field STALE_CLAIMS "$out")"
check "1: the dead-PID this-host claim is the stale one" "$U_DEAD" "$(field STALE_UUIDS "$out")"
check "2+3: only same-host claims considered (dead+live this host)" "2" "$(field SAME_HOST_CLAIMS "$out")"
check "dry-run: nothing released" "0" "$(field RELEASED "$out")"
check "4: dry-run mutates nothing (empty mutation log)" "0" "$(grep -c . "$MUTATION_LOG" 2>/dev/null || true)"
check "dry-run: MODE reported" "dry-run" "$(field MODE "$out")"
check "dry-run: STATUS OK" "OK" "$(field STATUS "$out")"

# --- Test: --apply releases ONLY the stale claim ----------------------------
: > "$MUTATION_LOG"
out=$(run_release --apply)
check "apply: one claim released" "1" "$(field RELEASED "$out")"
check "apply: MODE reported" "apply" "$(field MODE "$out")"
# The dead-this-host claim got all three mutations; live + foreign got none.
check "apply: dead claim stopped"   "1" "$(grep -c "${U_DEAD} stop"     "$MUTATION_LOG")"
check "apply: dead claim pid drained" "1" "$(grep -c "${U_DEAD} modify pid:" "$MUTATION_LOG")"
check "apply: dead claim annotated" "1" "$(grep -c "${U_DEAD} annotate auto-released: claiming PID gone" "$MUTATION_LOG")"
check "2: live-PID claim never mutated"    "0" "$(grep -c "$U_LIVE" "$MUTATION_LOG")"
check "3: foreign-host claim never mutated" "0" "$(grep -c "$U_FOREIGN" "$MUTATION_LOG")"
# rc.confirmation=no must be present on every mutation (deterministic batch).
check "apply: all mutations pass rc.confirmation=no" "3" "$(grep -c "rc.confirmation=no" "$MUTATION_LOG")"

# --- Test 5: empty +ACTIVE set → no-op --------------------------------------
echo '[]' > "$EXPORT_JSON"
: > "$MUTATION_LOG"
out=$(run_release --apply)
check "5: empty set → STALE_CLAIMS=0" "0" "$(field STALE_CLAIMS "$out")"
check "5: empty set → RELEASED=0" "0" "$(field RELEASED "$out")"
check "5: empty set → STATUS OK" "OK" "$(field STATUS "$out")"
check "5: empty set → no mutations" "0" "$(grep -c . "$MUTATION_LOG" 2>/dev/null || true)"

# --- Summary ----------------------------------------------------------------
echo "=== RELEASE STALE CLAIMS TEST ==="
echo "PASS=${pass}"
echo "FAIL=${fail}"
echo "STATUS=$([ "$fail" -eq 0 ] && echo OK || echo ERROR)"
echo "=== END RELEASE STALE CLAIMS TEST ==="
[ "$fail" -eq 0 ]
