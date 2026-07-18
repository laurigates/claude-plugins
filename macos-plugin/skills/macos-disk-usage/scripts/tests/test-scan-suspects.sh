#!/usr/bin/env bash
# Regression test for scan-suspects.sh.
#
# Runs entirely offline on Linux CI against a PLANTED fixture home via the
# injectable --home-dir / --root seams — never against the real system. Asserts
# the SEMANTIC invariants:
#   - Fixed-path suspects present on disk are detected with the right tier
#     (uv=safe, ollama=decision).
#   - A build-artifact dir counts ONLY when its marker sibling exists: a
#     target/ beside Cargo.toml is matched as rust-target; a target/ WITHOUT a
#     Cargo.toml is not (marker discipline).
#   - node_modules beside package.json is matched.
#   - The ranked table orders by real size (biggest fixture = rank 1).
#   - Tier totals separate safe from decision.
#   - A big dir NOT in the catalog surfaces as UNKNOWN (the feedback loop).
#   - A missing catalog reports STATUS=ERROR_NO_CATALOG and exits non-zero.
#   - An empty home degrades gracefully (STATUS=OK, no suspects, exit 0).
# Exit 0 on success ("ALL TESTS PASSED"); non-zero on any failure.
set -uo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
scan="${script_dir}/../scan-suspects.sh"
catalog="${script_dir}/../suspects.tsv"

fail() { echo "FAIL: $1" >&2; exit 1; }
pass() { echo "PASS: $1"; }

for dep in du find awk sort dirname dd; do
  command -v "$dep" >/dev/null 2>&1 || { echo "SKIP: $dep not installed"; exit 0; }
done

[ -f "$scan" ] || fail "scan-suspects.sh not found at $scan"
[ -f "$catalog" ] || fail "suspects.tsv not found at $catalog"

mkfile() { mkdir -p "$(dirname "$1")"; dd if=/dev/zero of="$1" bs=1024 count="$2" 2>/dev/null; }

fx="$(mktemp -d)"
trap 'rm -rf "$fx"' EXIT

# --- Plant the fixture home ------------------------------------------------
mkfile "$fx/.cache/uv/blob"                 5000   # fixed path, tier=safe
mkfile "$fx/.ollama/models/blob"            2000   # fixed path, tier=decision
# rust project: target/ beside Cargo.toml -> matched (mkfile creates proj/ first)
mkfile "$fx/repos/proj/target/artifact"     8000   # dir rust-target, biggest
: > "$fx/repos/proj/Cargo.toml"
# target/ WITHOUT Cargo.toml -> marker discipline: must NOT match
mkfile "$fx/repos/norust/target/artifact"   3000
# node project: node_modules beside package.json -> matched
mkfile "$fx/repos/webapp/node_modules/dep"  1000   # dir node-modules, tier=safe
: > "$fx/repos/webapp/package.json"
# a big dir not in the catalog -> should surface as UNKNOWN
mkfile "$fx/BigMovies/recording.mov"        4000

out="$(bash "$scan" --home-dir "$fx" --root "$fx" --min-mb 1 --top 25)"
rc=$?
[ "$rc" -eq 0 ] || fail "scan exited non-zero ($rc)"
grep -q '^STATUS=OK$' <<<"$out" || fail "missing STATUS=OK"
pass "scan runs clean on the fixture"

grep -q 'SUSPECT id=uv-cache tier=safe ' <<<"$out" || fail "uv-cache not detected as safe"
pass "fixed-path uv-cache detected (safe)"

grep -q 'SUSPECT id=ollama-models tier=decision ' <<<"$out" || fail "ollama not detected as decision"
pass "fixed-path ollama-models detected (decision)"

# rust-target matched, and matched at proj/ (has Cargo.toml)
grep -q 'SUSPECT id=rust-target .*proj/target' <<<"$out" || fail "rust-target not matched beside Cargo.toml"
pass "rust-target matched beside Cargo.toml"

# marker discipline: the markerless norust/target must NOT be a rust-target hit
if grep 'SUSPECT id=rust-target' <<<"$out" | grep -q 'norust'; then
  fail "markerless target/ was wrongly counted as rust-target"
fi
pass "markerless target/ correctly skipped (marker discipline)"

grep -q 'SUSPECT id=node-modules .*webapp/node_modules' <<<"$out" || fail "node-modules not matched"
pass "node-modules matched beside package.json"

# ranked rank-1 (biggest) is the 8000KB rust-target; field 4 is the id
rank1_id="$(awk -F'\t' '$1=="1"{print $4}' <<<"$out")"
[ "$rank1_id" = "rust-target" ] || fail "rank 1 should be rust-target, got '$rank1_id'"
pass "ranked table orders by real size (rust-target #1)"

# tier totals: safe (uv+target+node_modules) far exceeds decision (ollama only)
safe_kb="$(grep -oE '^TIER_SAFE_KB=[0-9]+' <<<"$out" | cut -d= -f2)"
dec_kb="$(grep -oE '^TIER_DECISION_KB=[0-9]+' <<<"$out" | cut -d= -f2)"
[ "${safe_kb:-0}" -gt "${dec_kb:-0}" ] || fail "safe total ($safe_kb) should exceed decision ($dec_kb)"
[ "${dec_kb:-0}" -ge 2000 ] || fail "decision total should be >= 2000 (ollama), got '$dec_kb'"
pass "tier totals separate safe from decision (safe=$safe_kb decision=$dec_kb)"

grep -q 'UNKNOWN .*BigMovies' <<<"$out" || fail "uncatalogued BigMovies not surfaced as UNKNOWN"
pass "uncatalogued big dir surfaced as UNKNOWN (feedback loop)"

# --- Missing catalog ------------------------------------------------------
out_nocat="$(bash "$scan" --home-dir "$fx" --catalog "$fx/does-not-exist.tsv" 2>&1)"
rc_nocat=$?
grep -q '^STATUS=ERROR_NO_CATALOG$' <<<"$out_nocat" || fail "missing catalog should report ERROR_NO_CATALOG"
[ "$rc_nocat" -ne 0 ] || fail "missing catalog should exit non-zero"
pass "missing catalog fails loudly"

# --- Empty home degrades gracefully ---------------------------------------
empty="$(mktemp -d)"; trap 'rm -rf "$fx" "$empty"' EXIT
out_empty="$(bash "$scan" --home-dir "$empty" --root "$empty" --min-mb 1)"
rc_empty=$?
[ "$rc_empty" -eq 0 ] || fail "empty home should exit 0"
grep -q '^STATUS=OK$' <<<"$out_empty" || fail "empty home should still report STATUS=OK"
grep -q '^SUSPECT ' <<<"$out_empty" && fail "empty home should surface no suspects"
pass "empty home degrades gracefully"

echo "ALL TESTS PASSED"
