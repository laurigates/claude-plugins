#!/usr/bin/env bash
# Regression test for configure-formatting.sh detection.
# A planted fixture with biome.json must be detected and recommend "configured";
# a bare fixture must recommend "setup". A legacy (prettier-only) fixture must
# recommend "migrate".
# Exit 0 on success, non-zero on failure.

set -uo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
check_script="${script_dir}/../configure-formatting.sh"

fail() { echo "FAIL: $1" >&2; exit 1; }
pass() { echo "PASS: $1"; }

[ -f "$check_script" ] || fail "configure-formatting.sh not found at $check_script"

# -----------------------------------------------------------------------------
# Case 1: biome.json present → detected, RECOMMENDATION=configured, STATUS=OK
# -----------------------------------------------------------------------------
biome_proj="$(mktemp -d)"
trap 'rm -rf "$biome_proj"' EXIT
printf '{}' > "${biome_proj}/package.json"
printf '{"formatter":{"enabled":true}}' > "${biome_proj}/biome.json"

out1="$(bash "$check_script" --home-dir "$HOME" --project-dir "$biome_proj")"
echo "$out1" | grep -q "^BIOME=true$" || fail "expected BIOME=true:\n$out1"
echo "$out1" | grep -q "^RECOMMENDATION=configured$" || fail "expected RECOMMENDATION=configured:\n$out1"
echo "$out1" | grep -q "^STATUS=OK$" || fail "expected STATUS=OK with biome configured:\n$out1"
pass "biome.json detected and recommends configured"
rm -rf "$biome_proj"

# -----------------------------------------------------------------------------
# Case 2: bare project → RECOMMENDATION=setup, STATUS=WARN
# -----------------------------------------------------------------------------
bare="$(mktemp -d)"
out2="$(bash "$check_script" --home-dir "$HOME" --project-dir "$bare")"
echo "$out2" | grep -q "^BIOME=false$" || fail "expected BIOME=false:\n$out2"
echo "$out2" | grep -q "^RECOMMENDATION=setup$" || fail "expected RECOMMENDATION=setup for bare project:\n$out2"
echo "$out2" | grep -q "^STATUS=WARN$" || fail "expected STATUS=WARN for bare project:\n$out2"
pass "bare project recommends setup"
rm -rf "$bare"

# -----------------------------------------------------------------------------
# Case 3: legacy prettier only → RECOMMENDATION=migrate
# -----------------------------------------------------------------------------
legacy="$(mktemp -d)"
printf '{}' > "${legacy}/package.json"
printf '{}' > "${legacy}/.prettierrc"
out3="$(bash "$check_script" --home-dir "$HOME" --project-dir "$legacy")"
echo "$out3" | grep -q "^PRETTIER=true$" || fail "expected PRETTIER=true:\n$out3"
echo "$out3" | grep -q "^RECOMMENDATION=migrate$" || fail "expected RECOMMENDATION=migrate for prettier-only:\n$out3"
pass "legacy prettier-only project recommends migrate"
rm -rf "$legacy"

echo "ALL TESTS PASSED"
