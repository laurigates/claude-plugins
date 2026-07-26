#!/usr/bin/env bash
# Regression test for generate-adr-index.sh (issue #2129, item 4).
# Auto-discovered by scripts/run-skill-script-tests.sh via
# */skills/*/scripts/tests/test-*.sh.
#
# Semantic invariants pinned here:
#   - the generated table carries ONE ROW PER ADR (the `awk` regeneration
#     one-liner some repos use prints a single row from its END block regardless
#     of input — a 25-ADR index silently collapsing to 1 line);
#   - `--check` is clean immediately after a write (round-trip);
#   - `--check` FAILS (non-zero) on real drift;
#   - "markers absent" is a DISTINCT non-fatal state, never a spurious diff.
set -uo pipefail

# Neutralize inherited git context so nothing here can reach the real shared
# .git (issue #1745). This test builds no repo, but the sandboxes are created
# the same way and the guard costs nothing.
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_OBJECT_DIRECTORY GIT_COMMON_DIR GIT_NAMESPACE GIT_PREFIX

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GEN="$SCRIPT_DIR/../generate-adr-index.sh"

pass=0
fail=0
ok()  { printf 'ok   - %s\n' "$1"; pass=$((pass + 1)); }
bad() { printf 'FAIL - %s\n' "$1"; fail=$((fail + 1)); }

SANDBOX="$(mktemp -d)" || exit 1
[ -n "$SANDBOX" ] || exit 1
trap 'rm -rf "$SANDBOX"' EXIT

DIR_A="docs/adrs"                 # 13 ADRs, numbered in the filename
DIR_B="docs/blueprint/adrs"       # 12 ADRs, two of them numbered ONLY in frontmatter
mkdir -p "$SANDBOX/$DIR_A" "$SANDBOX/$DIR_B"

write_adr() { # <dir> <number> <basename> <status>
  local w_dir="$1" w_num="$2" w_base="$3" w_status="$4"
  cat > "$SANDBOX/$w_dir/$w_base" <<MD
---
id: ADR-$(printf '%04d' "$w_num")
status: $w_status
---

# ADR-$(printf '%04d' "$w_num"): Decision $w_num
MD
}

for n in $(seq 1 13); do
  write_adr "$DIR_A" "$n" "$(printf '%04d' "$n")-decision-$n.md" Accepted
done
for n in $(seq 14 23); do
  write_adr "$DIR_B" "$n" "$(printf '%04d' "$n")-decision-$n.md" Accepted
done
# The two frontmatter-only claimants (no number in the filename).
write_adr "$DIR_B" 24 "objs-format.md" Accepted
write_adr "$DIR_B" 25 "in-engine-ui.md" Proposed
# Non-ADR files that must never become rows.
printf 'not an ADR\n' > "$SANDBOX/$DIR_A/validation-report.md"

# Pre-existing hand-maintained index in DIR_A, already carrying the markers,
# but listing only 3 of the 13 ADRs with a stale status (the reported shape).
cat > "$SANDBOX/$DIR_A/README.md" <<'MD'
# Architecture Decision Records

Hand-written prose that must survive regeneration.

<!-- ADR-INDEX:START -->
| ADR | Title | Status |
| --- | ----- | ------ |
| [ADR-0001](0001-decision-1.md) | Decision 1 | Draft |
<!-- ADR-INDEX:END -->

Trailing prose that must also survive.
MD
# DIR_B has a README with NO markers at all.
printf '# Blueprint ADRs\n\nNo generated block here yet.\n' > "$SANDBOX/$DIR_B/README.md"

run() { bash "$GEN" --project-dir "$SANDBOX" --adr-dir "$DIR_A" --adr-dir "$DIR_B" "$@"; }

# --- TEST A: --check BEFORE any write: DIR_A drifted, DIR_B markers absent -----
out="$(run --check)"; rc=$?
if grep -q '^ADR_DIR_1_STATE=drifted$' <<<"$out" && grep -q 'TYPE=adr_index_drift' <<<"$out" \
   && grep -q '^STATUS=ERROR$' <<<"$out" && [ "$rc" -ne 0 ]; then
  ok "A: --check on a stale index → drift ERROR, non-zero exit"
else bad "A: expected drift ERROR + non-zero exit"; echo "$out"; fi
if grep -q '^ADR_DIR_2_STATE=markers_absent$' <<<"$out" \
   && grep -q 'TYPE=adr_index_markers_absent' <<<"$out" \
   && ! grep -q 'TYPE=adr_index_drift.*docs/blueprint/adrs' <<<"$out"; then
  ok "A: markers-absent is a distinct state, not a spurious diff"
else bad "A: markers-absent must not be reported as drift"; echo "$out"; fi

# --- TEST B: markers absent + --check ALONE → WARN, exit 0 (non-fatal) ---------
out="$(bash "$GEN" --project-dir "$SANDBOX" --adr-dir "$DIR_B" --check)"; rc=$?
if grep -q '^ADR_DIR_1_STATE=markers_absent$' <<<"$out" && grep -q '^STATUS=WARN$' <<<"$out" \
   && [ "$rc" -eq 0 ]; then
  ok "B: markers absent → WARN, exit 0 (parallel-safe)"
else bad "B: markers absent should be WARN/exit 0, got rc=$rc"; echo "$out"; fi

# --- TEST C: write mode regenerates one row per ADR ---------------------------
out="$(run)"; rc=$?
if [ "$rc" -eq 0 ] && grep -q '^ADR_DIR_1_STATE=written$' <<<"$out" \
   && grep -q '^ADR_DIR_2_STATE=markers_inserted$' <<<"$out"; then
  ok "C: write regenerates DIR_A and adopts markers in DIR_B"
else bad "C: expected written + markers_inserted"; echo "$out"; fi

rows_a="$(grep -c '^| \[ADR-' "$SANDBOX/$DIR_A/README.md")"
rows_b="$(grep -c '^| \[ADR-' "$SANDBOX/$DIR_B/README.md")"
if [ "$rows_a" -eq 13 ] && [ "$rows_b" -eq 12 ] && [ "$((rows_a + rows_b))" -eq 25 ]; then
  ok "C: 25 ADRs across two directories → 13 + 12 rows (one row per ADR)"
else bad "C: expected 13+12=25 rows, got $rows_a + $rows_b"; fi
if grep -q '^TOTAL_ROWS=25$' <<<"$out"; then
  ok "C: TOTAL_ROWS reports every ADR (not a single END-block row)"
else bad "C: expected TOTAL_ROWS=25"; echo "$out"; fi

# Content invariants: the stale status is corrected, frontmatter-only claimants
# get rows, non-ADR files do not, and hand-written prose survives.
if grep -qF '| [ADR-0001](0001-decision-1.md) | Decision 1 | Accepted |' "$SANDBOX/$DIR_A/README.md"; then
  ok "C: stale status regenerated from frontmatter"
else bad "C: expected ADR-0001 row with the frontmatter status"; sed -n '1,30p' "$SANDBOX/$DIR_A/README.md"; fi
if grep -qF '| [ADR-0024](objs-format.md) |' "$SANDBOX/$DIR_B/README.md" \
   && grep -qF '| [ADR-0025](in-engine-ui.md) | Decision 25 | Proposed |' "$SANDBOX/$DIR_B/README.md"; then
  ok "C: frontmatter-only claimants get index rows"
else bad "C: expected rows for the frontmatter-only ADRs"; sed -n '1,30p' "$SANDBOX/$DIR_B/README.md"; fi
if ! grep -q 'validation-report' "$SANDBOX/$DIR_A/README.md"; then
  ok "C: non-ADR files are not indexed"
else bad "C: validation-report.md must not be a row"; fi
if grep -qF 'Hand-written prose that must survive regeneration.' "$SANDBOX/$DIR_A/README.md" \
   && grep -qF 'Trailing prose that must also survive.' "$SANDBOX/$DIR_A/README.md"; then
  ok "C: prose outside the markers survives"
else bad "C: prose around the block was clobbered"; fi
# Rows must be in ascending ADR order.
order="$(grep '^| \[ADR-' "$SANDBOX/$DIR_A/README.md" | sed -E 's/^\| \[ADR-0*([0-9]+)\].*/\1/' | tr '\n' ' ')"
if [ "$order" = "1 2 3 4 5 6 7 8 9 10 11 12 13 " ]; then
  ok "C: rows sorted numerically, not lexically"
else bad "C: expected ascending numeric order, got: $order"; fi

# --- TEST D: --check is clean immediately after the write (round-trip) --------
out="$(run --check)"; rc=$?
if [ "$rc" -eq 0 ] && grep -q '^STATUS=OK$' <<<"$out" \
   && grep -q '^ADR_DIR_1_STATE=in_sync$' <<<"$out" \
   && grep -q '^ADR_DIR_2_STATE=in_sync$' <<<"$out" \
   && grep -q '^ISSUE_COUNT=0$' <<<"$out"; then
  ok "D: --check clean after write → OK, exit 0"
else bad "D: expected in_sync/OK/exit 0 after write, got rc=$rc"; echo "$out"; fi

# --- TEST E: write is idempotent ---------------------------------------------
before="$(cat "$SANDBOX/$DIR_A/README.md")"
out="$(run)"
after="$(cat "$SANDBOX/$DIR_A/README.md")"
if grep -q '^ADR_DIR_1_STATE=unchanged$' <<<"$out" && [ "$before" = "$after" ]; then
  ok "E: second write is a no-op (unchanged)"
else bad "E: write should be idempotent"; echo "$out"; fi

# --- TEST F: real drift is detected — a new ADR and a changed status ----------
write_adr "$DIR_A" 26 "0026-late-arrival.md" Accepted
out="$(run --check)"; rc=$?
if [ "$rc" -ne 0 ] && grep -q '^ADR_DIR_1_STATE=drifted$' <<<"$out" \
   && grep -q 'TYPE=adr_index_drift' <<<"$out" && grep -q '^STATUS=ERROR$' <<<"$out"; then
  ok "F: a new unindexed ADR drifts the index (ERROR, non-zero)"
else bad "F: expected drift on a new ADR, got rc=$rc"; echo "$out"; fi
run >/dev/null
# `sed -i.bak` + rm: portable across GNU and BSD sed (.claude/rules/shell-scripting.md).
sed -i.bak 's/^status: Accepted$/status: Superseded/' "$SANDBOX/$DIR_A/0026-late-arrival.md"
rm -f "$SANDBOX/$DIR_A/0026-late-arrival.md.bak"
out="$(run --check)"; rc=$?
if [ "$rc" -ne 0 ] && grep -q '^ADR_DIR_1_STATE=drifted$' <<<"$out"; then
  ok "F: a changed frontmatter status drifts the index"
else bad "F: expected drift on a status change, got rc=$rc"; echo "$out"; fi

# --- TEST G: no index file at all → created on write, distinct state on check --
G_DIR="docs/decisions"
mkdir -p "$SANDBOX/$G_DIR"
write_adr "$G_DIR" 31 "0031-standalone.md" Accepted
out="$(bash "$GEN" --project-dir "$SANDBOX" --adr-dir "$G_DIR" --check)"; rc=$?
if grep -q '^ADR_DIR_1_STATE=index_absent$' <<<"$out" && grep -q '^STATUS=WARN$' <<<"$out" \
   && [ "$rc" -eq 0 ]; then
  ok "G: missing index file → index_absent WARN, exit 0"
else bad "G: expected index_absent WARN, got rc=$rc"; echo "$out"; fi
out="$(bash "$GEN" --project-dir "$SANDBOX" --adr-dir "$G_DIR")"
if grep -q '^ADR_DIR_1_STATE=index_created$' <<<"$out" \
   && grep -qF '| [ADR-0031](0031-standalone.md) |' "$SANDBOX/$G_DIR/README.md" \
   && grep -qF '<!-- ADR-INDEX:START -->' "$SANDBOX/$G_DIR/README.md"; then
  ok "G: write creates the index with markers"
else bad "G: expected an index_created README with markers"; echo "$out"; fi
out="$(bash "$GEN" --project-dir "$SANDBOX" --adr-dir "$G_DIR" --check)"; rc=$?
if [ "$rc" -eq 0 ] && grep -q '^ADR_DIR_1_STATE=in_sync$' <<<"$out"; then
  ok "G: created index round-trips clean"
else bad "G: created index should be in_sync"; echo "$out"; fi

# --- TEST H: an empty / ADR-less directory is a silent no-op ------------------
mkdir -p "$SANDBOX/docs/empty"
out="$(bash "$GEN" --project-dir "$SANDBOX" --adr-dir docs/empty --check)"; rc=$?
if [ "$rc" -eq 0 ] && grep -q '^ADR_DIR_1_STATE=no_adrs$' <<<"$out" \
   && grep -q '^STATUS=OK$' <<<"$out"; then
  ok "H: ADR-less directory → no_adrs, silent OK"
else bad "H: expected no_adrs OK, got rc=$rc"; echo "$out"; fi

# --- TEST I: unknown argument is rejected, not swallowed ----------------------
bash "$GEN" --project-dir "$SANDBOX" --checks >/dev/null 2>&1; rc=$?
if [ "$rc" -eq 2 ]; then ok "I: unknown argument rejected (exit 2)"; else bad "I: expected exit 2, got $rc"; fi

echo "---"
echo "PASS=$pass FAIL=$fail"
[ "$fail" -eq 0 ]
