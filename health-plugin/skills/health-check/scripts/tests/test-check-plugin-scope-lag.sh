#!/usr/bin/env bash
# Tests for check-plugin-scope-lag.sh (issue #3220).
# A project-scope install pinned below the user-scope version of the same
# plugin keeps that project on the old build after a user-scope update; in
# W44 six projects ran hooks-plugin 2.15.2 while user scope was 2.15.5, so
# blocks already fixed in 2.15.3 kept firing. The check must WARN on every such
# entry (no allowlist), compare versions semver-aware (2.9 < 2.10), and stay
# quiet for equal versions, newer project pins, and project-only plugins.
# Exit 0 on success, non-zero on failure.

set -uo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
check_script="${script_dir}/../check-plugin-scope-lag.sh"

fail() {
  printf 'FAIL: %b\n' "$1" >&2
  exit 1
}

pass() {
  echo "PASS: $1"
}

if ! command -v jq >/dev/null 2>&1; then
  echo "SKIP: jq not installed; cannot run check-plugin-scope-lag tests"
  exit 0
fi

[ -f "$check_script" ] || fail "check-plugin-scope-lag.sh not found at $check_script"

tmp_root="$(mktemp -d)" || fail "mktemp -d failed"
if [ -z "$tmp_root" ] || [ ! -d "$tmp_root" ]; then
  fail "mktemp -d returned no directory"
fi
trap 'rm -rf "$tmp_root"' EXIT

# write_registry <home> <json-plugins-object>
write_registry() {
  mkdir -p "$1/.claude/plugins"
  printf '{"version":2,"plugins":%s}\n' "$2" > "$1/.claude/plugins/installed_plugins.json"
}

run_check() {
  bash "$check_script" --home-dir "$1" --project-dir "$1"
}

# --- Case A: patch lag (the W44 repro) -> WARN naming path and both versions
home_a="${tmp_root}/a"
write_registry "$home_a" '{
  "hooks-plugin@mp": [
    {"scope":"user","version":"2.15.5"},
    {"scope":"project","projectPath":"/work/thelma","version":"2.15.2"}
  ]
}'
out_a="$(run_check "$home_a")"; rc_a=$?
[ "$rc_a" -eq 0 ] || fail "case A exit $rc_a, expected 0:\n$out_a"
grep -q '^=== PLUGIN SCOPE LAG ===$' <<<"$out_a" || fail "case A missing header:\n$out_a"
grep -q '^STATUS=WARN$' <<<"$out_a" || fail "case A expected STATUS=WARN:\n$out_a"
grep -q '^ISSUE_COUNT=1$' <<<"$out_a" || fail "case A expected ISSUE_COUNT=1:\n$out_a"
grep -q 'TYPE=scope_lag PLUGIN=hooks-plugin@mp PROJECT=/work/thelma PROJECT_VERSION=2.15.2 USER_VERSION=2.15.5' <<<"$out_a" \
  || fail "case A expected a lag line with path and both versions:\n$out_a"
grep -q '^REASON=' <<<"$out_a" || fail "case A missing REASON=:\n$out_a"
pass "patch lag 2.15.2 < 2.15.5 warns with path and versions"

# --- Case B: equal versions -> OK
home_b="${tmp_root}/b"
write_registry "$home_b" '{
  "hooks-plugin@mp": [
    {"scope":"user","version":"2.15.5"},
    {"scope":"project","projectPath":"/work/x","version":"2.15.5"}
  ]
}'
out_b="$(run_check "$home_b")"
grep -q '^STATUS=OK$' <<<"$out_b" || fail "case B expected STATUS=OK:\n$out_b"
grep -q '^ISSUE_COUNT=0$' <<<"$out_b" || fail "case B expected ISSUE_COUNT=0:\n$out_b"
pass "equal versions are OK"

# --- Case C: project-only plugin (no user entry) -> no WARN
home_c="${tmp_root}/c"
write_registry "$home_c" '{
  "only-project@mp": [
    {"scope":"project","projectPath":"/work/y","version":"0.1.0"}
  ]
}'
out_c="$(run_check "$home_c")"
grep -q '^STATUS=OK$' <<<"$out_c" || fail "case C expected STATUS=OK:\n$out_c"
pass "project-only plugin does not warn"

# --- Case D: 2.9 vs 2.10 ordering (lexical sort would get this wrong)
home_d="${tmp_root}/d"
write_registry "$home_d" '{
  "lagging@mp": [
    {"scope":"user","version":"2.10.0"},
    {"scope":"project","projectPath":"/work/old","version":"2.9.0"}
  ],
  "ahead@mp": [
    {"scope":"user","version":"2.9.0"},
    {"scope":"project","projectPath":"/work/new","version":"2.10.0"}
  ]
}'
out_d="$(run_check "$home_d")"
grep -q '^STATUS=WARN$' <<<"$out_d" || fail "case D expected STATUS=WARN:\n$out_d"
grep -q '^ISSUE_COUNT=1$' <<<"$out_d" || fail "case D expected exactly one lag (2.9 < 2.10):\n$out_d"
grep -q 'PLUGIN=lagging@mp PROJECT=/work/old PROJECT_VERSION=2.9.0 USER_VERSION=2.10.0' <<<"$out_d" \
  || fail "case D expected lagging@mp flagged:\n$out_d"
grep -q 'PLUGIN=ahead@mp' <<<"$out_d" && fail "case D: a project pin newer than user scope must not warn:\n$out_d"
pass "2.9 < 2.10 ordering is semver-aware; newer project pin is quiet"

# --- Case E: several lagging projects for one plugin -> one line each
home_e="${tmp_root}/e"
write_registry "$home_e" '{
  "hooks-plugin@mp": [
    {"scope":"project","projectPath":"/work/p1","version":"2.15.2"},
    {"scope":"user","version":"2.15.5"},
    {"scope":"project","projectPath":"/work/p2","version":"2.15.2"},
    {"scope":"project","projectPath":"/work/p3","version":"2.15.5"}
  ]
}'
out_e="$(run_check "$home_e")"
grep -q '^ISSUE_COUNT=2$' <<<"$out_e" || fail "case E expected ISSUE_COUNT=2:\n$out_e"
grep -q 'PROJECT=/work/p1 ' <<<"$out_e" || fail "case E expected /work/p1:\n$out_e"
grep -q 'PROJECT=/work/p2 ' <<<"$out_e" || fail "case E expected /work/p2:\n$out_e"
grep -q '^REASON=scope_lag: .* (+1 more)$' <<<"$out_e" || fail "case E expected REASON with (+1 more):\n$out_e"
pass "each lagging project gets its own line"

# --- Structured-output contract (.claude/rules/structured-script-output.md)
contract="${script_dir}/../../../../../scripts/check-structured-output-contract.sh"
if [ -f "$contract" ]; then
  for fixture_out in "$out_a" "$out_b" "$out_e"; do
    bash "$contract" --validate - <<<"$fixture_out" >/dev/null \
      || fail "output fails the structured-output contract:\n$fixture_out"
  done
  pass "WARN and OK output satisfy the structured-output contract"
fi

# --- Case F: missing registry -> exit 0, not a WARN
home_f="${tmp_root}/f"
mkdir -p "$home_f"
out_f="$(run_check "$home_f")"; rc_f=$?
[ "$rc_f" -eq 0 ] || fail "case F exit $rc_f, expected 0:\n$out_f"
grep -q '^STATUS=OK$' <<<"$out_f" || fail "case F expected STATUS=OK:\n$out_f"
grep -q '^REGISTRY_EXISTS=false$' <<<"$out_f" || fail "case F expected REGISTRY_EXISTS=false:\n$out_f"
pass "missing registry exits 0"

echo "All check-plugin-scope-lag tests passed"
