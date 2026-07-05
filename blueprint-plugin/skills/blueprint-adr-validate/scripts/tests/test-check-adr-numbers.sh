#!/usr/bin/env bash
# Regression test for check-adr-numbers.sh (issue #1585).
# Auto-discovered by scripts/run-skill-script-tests.sh via
# */skills/*/scripts/tests/test-*.sh.
set -uo pipefail

# Neutralize any inherited git context so `git -C "$sandbox"` cannot be hijacked
# into the real shared .git (issue #1745).
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_OBJECT_DIRECTORY GIT_COMMON_DIR GIT_NAMESPACE GIT_PREFIX

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CHECK="$SCRIPT_DIR/../check-adr-numbers.sh"

pass=0
fail=0
ok()   { printf 'ok   - %s\n' "$1"; pass=$((pass + 1)); }
bad()  { printf 'FAIL - %s\n' "$1"; fail=$((fail + 1)); }

# --- fixture: a git repo with a base commit (origin/main-like) ----------------
SANDBOX="$(mktemp -d)"
[ -n "$SANDBOX" ] || { echo "mktemp failed"; exit 1; }
trap 'rm -rf "$SANDBOX"' EXIT

git -C "$SANDBOX" init -q
git -C "$SANDBOX" config user.email t@t.t
git -C "$SANDBOX" config user.name t
mkdir -p "$SANDBOX/docs/adrs"

# Base ref holds ADR 0038 under one filename, indexed in the README.
cat > "$SANDBOX/docs/adrs/0038-declarative-bootstrapping.md" <<'MD'
# ADR-0038: Declarative bootstrapping
status: Accepted
MD
cat > "$SANDBOX/docs/adrs/README.md" <<'MD'
# ADRs
- [ADR-0038](0038-declarative-bootstrapping.md)
MD
git -C "$SANDBOX" add -A
git -C "$SANDBOX" commit -q -m "base"
git -C "$SANDBOX" branch base-main

run() { bash "$CHECK" --project-dir "$SANDBOX" --base-ref "$1"; }

# --- TEST A: clean tree matching base → STATUS=OK -----------------------------
out="$(run base-main)"
if grep -q '^STATUS=OK$' <<<"$out"; then ok "A: clean tree → OK"; else bad "A: clean tree should be OK"; echo "$out"; fi

# --- TEST B: parallel-PR collision — a PR branched before the base's 0038
# merged, so its working tree has 0038-sensor but NOT the 0038-declarative that
# now sits on base-main under a different filename.
rm -f "$SANDBOX/docs/adrs/0038-declarative-bootstrapping.md"
cat > "$SANDBOX/docs/adrs/0038-sensor-pipeline.md" <<'MD'
# ADR-0038: Sensor pipeline
status: Accepted
MD
# index the new one so we isolate the collision (not the missing-index) signal
cat > "$SANDBOX/docs/adrs/README.md" <<'MD'
# ADRs
- [ADR-0038 sensor](0038-sensor-pipeline.md)
MD
out="$(run base-main)"; rc=$?
if grep -q 'TYPE=adr_number_collision' <<<"$out" && grep -q '^STATUS=ERROR$' <<<"$out"; then
  ok "B: base-ref collision detected (ERROR)"
else bad "B: expected adr_number_collision ERROR"; echo "$out"; fi
if [ "$rc" -eq 1 ]; then ok "B: exit 1 on collision"; else bad "B: expected exit 1, got $rc"; fi
rm -f "$SANDBOX/docs/adrs/0038-sensor-pipeline.md"
git -C "$SANDBOX" checkout -q -- docs/adrs/

# --- TEST C: two files in the working tree claim the same number --------------
cat > "$SANDBOX/docs/adrs/0041-alpha.md" <<'MD'
# ADR-0041: Alpha
MD
cat > "$SANDBOX/docs/adrs/0041-beta.md" <<'MD'
# ADR-0041: Beta
MD
printf -- '- [ADR-0041 a](0041-alpha.md)\n- [ADR-0041 b](0041-beta.md)\n' >> "$SANDBOX/docs/adrs/README.md"
out="$(run base-main)"
if grep -q 'TYPE=duplicate_adr_number' <<<"$out" && grep -q '^STATUS=ERROR$' <<<"$out"; then
  ok "C: within-tree duplicate detected (ERROR)"
else bad "C: expected duplicate_adr_number ERROR"; echo "$out"; fi
rm -f "$SANDBOX/docs/adrs/0041-alpha.md" "$SANDBOX/docs/adrs/0041-beta.md"
git -C "$SANDBOX" checkout -q -- docs/adrs/README.md

# --- TEST D: an ADR absent from the README index → WARN -----------------------
cat > "$SANDBOX/docs/adrs/0042-unindexed.md" <<'MD'
# ADR-0042: Unindexed
MD
out="$(run base-main)"; rc=$?
if grep -q 'TYPE=adr_missing_index_row' <<<"$out" && grep -q '^STATUS=WARN$' <<<"$out"; then
  ok "D: missing index row detected (WARN)"
else bad "D: expected adr_missing_index_row WARN"; echo "$out"; fi
if [ "$rc" -eq 0 ]; then ok "D: WARN exits 0 (parallel-safe)"; else bad "D: WARN should exit 0, got $rc"; fi
rm -f "$SANDBOX/docs/adrs/0042-unindexed.md"

# --- TEST E: no docs/adrs dir → OK, no false positive -------------------------
E_SANDBOX="$(mktemp -d)"
[ -n "$E_SANDBOX" ] || { echo "mktemp failed"; exit 1; }
git -C "$E_SANDBOX" init -q
out="$(bash "$CHECK" --project-dir "$E_SANDBOX" --base-ref HEAD 2>/dev/null)"
if grep -q 'ADR_DIR=none' <<<"$out" && grep -q '^STATUS=OK$' <<<"$out"; then
  ok "E: no ADR dir → OK"
else bad "E: missing ADR dir should be OK"; echo "$out"; fi
rm -rf "$E_SANDBOX"

# --- TEST F: base ref unavailable → still runs (dupes/index only) --------------
out="$(bash "$CHECK" --project-dir "$SANDBOX" --base-ref does-not-exist 2>/dev/null)"
if grep -q '^BASE_REF_AVAILABLE=false$' <<<"$out" && grep -q '^STATUS=OK$' <<<"$out"; then
  ok "F: absent base ref degrades gracefully"
else bad "F: absent base ref should degrade to OK"; echo "$out"; fi

echo "---"
echo "PASS=$pass FAIL=$fail"
[ "$fail" -eq 0 ]
