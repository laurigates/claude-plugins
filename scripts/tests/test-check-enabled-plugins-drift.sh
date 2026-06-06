#!/usr/bin/env bash
# Regression test for scripts/check-enabled-plugins-drift.sh
#
# Per .claude/rules/regression-testing.md: the drift guard ships with a test
# proving it (a) passes when settings match the marketplace, and (b) flags each
# drift class — plugin not enabled, enabled plugin dangling, marketplace not
# registered. Uses temp-dir fixtures so it never touches the real repo state.
set -uo pipefail

script_dir="$(cd "$(dirname "$0")/.." && pwd)"
check="$script_dir/check-enabled-plugins-drift.sh"

pass=0
fail=0

ok() { echo "PASS: $1"; pass=$((pass + 1)); }
ko() { echo "FAIL: $1"; fail=$((fail + 1)); }

# assert_has <desc> <text> <needle>  — text contains needle
assert_has() {
  if printf '%s' "$2" | grep -q -- "$3"; then ok "$1"; else ko "$1"; fi
}

# assert_lacks <desc> <text>  — text is empty
assert_empty() {
  if [ -z "$2" ]; then ok "$1"; else ko "$1"; fi
}

# assert_strict_ok <desc> <dir>  — --strict exits 0
assert_strict_ok() {
  if bash "$check" --project-dir "$2" --strict >/dev/null 2>&1; then ok "$1"; else ko "$1"; fi
}

# assert_strict_fails <desc> <dir>  — --strict exits non-zero
assert_strict_fails() {
  if bash "$check" --project-dir "$2" --strict >/dev/null 2>&1; then ko "$1"; else ok "$1"; fi
}

# Build a fixture project dir. Args: <out-dir> <marketplace-json> <settings-json>
make_fixture() {
  mkdir -p "$1/.claude-plugin" "$1/.claude"
  printf '%s' "$2" > "$1/.claude-plugin/marketplace.json"
  printf '%s' "$3" > "$1/.claude/settings.json"
}

MKT='{"name":"test-mkt","plugins":[{"name":"alpha-plugin","source":"./alpha-plugin"},{"name":"beta-plugin","source":"./beta-plugin"}]}'

tmp_root="$(mktemp -d)"
trap 'rm -rf "$tmp_root"' EXIT

# --- TEST A: fully in sync ----------------------------------------------------
a="$tmp_root/a"
make_fixture "$a" "$MKT" \
  '{"extraKnownMarketplaces":{"test-mkt":{"source":{"source":"github","repo":"o/r"}}},"enabledPlugins":{"alpha-plugin@test-mkt":true,"beta-plugin@test-mkt":true}}'
out_a="$(bash "$check" --project-dir "$a")"
assert_has "in-sync settings report STATUS=OK" "$out_a" "STATUS=OK"
assert_has "in-sync settings report ISSUE_COUNT=0" "$out_a" "ISSUE_COUNT=0"
assert_strict_ok "in-sync settings pass --strict (exit 0)" "$a"

# --- TEST B: a marketplace plugin is not enabled ------------------------------
b="$tmp_root/b"
make_fixture "$b" "$MKT" \
  '{"extraKnownMarketplaces":{"test-mkt":{"source":{"source":"github","repo":"o/r"}}},"enabledPlugins":{"alpha-plugin@test-mkt":true}}'
out_b="$(bash "$check" --project-dir "$b")"
assert_has "unenabled marketplace plugin flagged plugin_not_enabled" "$out_b" "TYPE=plugin_not_enabled"
assert_has "missing enablement yields STATUS=ERROR" "$out_b" "STATUS=ERROR"
assert_strict_fails "missing enablement fails --strict (exit 1)" "$b"

# --- TEST C: an enabled plugin no longer in the marketplace -------------------
c="$tmp_root/c"
make_fixture "$c" "$MKT" \
  '{"extraKnownMarketplaces":{"test-mkt":{"source":{"source":"github","repo":"o/r"}}},"enabledPlugins":{"alpha-plugin@test-mkt":true,"beta-plugin@test-mkt":true,"ghost-plugin@test-mkt":true}}'
out_c="$(bash "$check" --project-dir "$c")"
assert_has "enabled plugin absent from marketplace flagged enabled_plugin_dangling" "$out_c" "TYPE=enabled_plugin_dangling"

# --- TEST D: marketplace not registered ---------------------------------------
d="$tmp_root/d"
make_fixture "$d" "$MKT" \
  '{"enabledPlugins":{"alpha-plugin@test-mkt":true,"beta-plugin@test-mkt":true}}'
out_d="$(bash "$check" --project-dir "$d")"
assert_has "unregistered marketplace flagged marketplace_not_registered" "$out_d" "TYPE=marketplace_not_registered"
assert_has "unregistered marketplace reports MARKETPLACE_REGISTERED=false" "$out_d" "MARKETPLACE_REGISTERED=false"

# --- TEST E: a plugin set to false counts as not enabled ----------------------
e="$tmp_root/e"
make_fixture "$e" "$MKT" \
  '{"extraKnownMarketplaces":{"test-mkt":{"source":{"source":"github","repo":"o/r"}}},"enabledPlugins":{"alpha-plugin@test-mkt":true,"beta-plugin@test-mkt":false}}'
out_e="$(bash "$check" --project-dir "$e")"
assert_has "plugin explicitly set to false flagged plugin_not_enabled" "$out_e" "TYPE=plugin_not_enabled"

# --- TEST F: --issue-body empty when clean, populated on drift ----------------
body_clean="$(bash "$check" --project-dir "$a" --issue-body)"
assert_empty "--issue-body empty when in sync" "$body_clean"
body_drift="$(bash "$check" --project-dir "$b" --issue-body)"
assert_has "--issue-body populated on drift" "$body_drift" "Plugin enablement drift"

echo ""
echo "RESULTS: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
