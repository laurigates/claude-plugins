#!/usr/bin/env bash
# Tests for check-marketplace-enrollment.sh (issue #3579).
# Check 1e used to be an inline jq snippet in references/environment-checks.md:
# no allowed-tools rule covered it, so it prompted, and the agent re-derived it
# each run. The script must find the marketplace by its stable source.repo (the
# local key is user-chosen), ERROR when no extraKnownMarketplaces entry names
# that repo, WARN when the marketplace is enrolled but no enabledPlugins key
# under it is true, and stay OK otherwise.
# Exit 0 on success, non-zero on failure.

set -uo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
check_script="${script_dir}/../check-marketplace-enrollment.sh"

fail() {
  printf 'FAIL: %b\n' "$1" >&2
  exit 1
}

pass() {
  echo "PASS: $1"
}

if ! command -v jq >/dev/null 2>&1; then
  echo "SKIP: jq not installed; cannot run check-marketplace-enrollment tests"
  exit 0
fi

[ -f "$check_script" ] || fail "check-marketplace-enrollment.sh not found at $check_script"

tmp_root="$(mktemp -d)" || fail "mktemp -d failed"
if [ -z "$tmp_root" ] || [ ! -d "$tmp_root" ]; then
  fail "mktemp -d returned no directory"
fi
trap 'rm -rf "$tmp_root"' EXIT

# write_settings <project-dir> <json>
write_settings() {
  mkdir -p "$1/.claude"
  printf '%s\n' "$2" > "$1/.claude/settings.json"
}

# run_check <project-dir> [extra args...]
run_check() {
  local proj="$1"
  shift
  bash "$check_script" --home-dir "$tmp_root/home" --project-dir "$proj" "$@"
}

mkdir -p "$tmp_root/home"

# --- Case A: enrolled under a non-default key, one plugin enabled -> OK
proj_a="${tmp_root}/a"
write_settings "$proj_a" '{
  "extraKnownMarketplaces": {
    "other": {"source": {"source": "github", "repo": "someone/else"}},
    "claude-plugins": {"source": {"source": "github", "repo": "laurigates/claude-plugins"}}
  },
  "enabledPlugins": {"git-plugin@claude-plugins": true, "x@other": true}
}'
out_a="$(run_check "$proj_a")"; rc_a=$?
[ "$rc_a" -eq 0 ] || fail "case A exit $rc_a, expected 0:\n$out_a"
grep -q '^=== MARKETPLACE ENROLLMENT ===$' <<<"$out_a" || fail "case A missing header:\n$out_a"
grep -q '^=== END MARKETPLACE ENROLLMENT ===$' <<<"$out_a" || fail "case A missing footer:\n$out_a"
grep -q '^STATUS=OK$' <<<"$out_a" || fail "case A expected STATUS=OK:\n$out_a"
grep -q '^ISSUE_COUNT=0$' <<<"$out_a" || fail "case A expected ISSUE_COUNT=0:\n$out_a"
grep -q '^MARKETPLACE_KEY=claude-plugins$' <<<"$out_a" || fail "case A expected MARKETPLACE_KEY=claude-plugins (found by source.repo):\n$out_a"
grep -q '^ENABLED_PLUGIN_COUNT=1$' <<<"$out_a" || fail "case A expected ENABLED_PLUGIN_COUNT=1 (x@other is not this marketplace):\n$out_a"
grep -q '^REASON=' <<<"$out_a" && fail "case A: REASON= must not appear on OK:\n$out_a"
pass "marketplace found by source.repo under a user-chosen key"

# --- Case B: enrolled, but every plugin under it is disabled or absent -> WARN
proj_b="${tmp_root}/b"
write_settings "$proj_b" '{
  "extraKnownMarketplaces": {
    "laurigates-claude-plugins": {"source": {"source": "github", "repo": "laurigates/claude-plugins"}}
  },
  "enabledPlugins": {"git-plugin@laurigates-claude-plugins": false, "y@elsewhere": true}
}'
out_b="$(run_check "$proj_b")"; rc_b=$?
[ "$rc_b" -eq 0 ] || fail "case B exit $rc_b, expected 0 (WARN exits 0):\n$out_b"
grep -q '^STATUS=WARN$' <<<"$out_b" || fail "case B expected STATUS=WARN:\n$out_b"
grep -q '^ISSUE_COUNT=1$' <<<"$out_b" || fail "case B expected ISSUE_COUNT=1:\n$out_b"
grep -q 'SEVERITY=WARN TYPE=no_enabled_plugins' <<<"$out_b" || fail "case B expected a no_enabled_plugins row:\n$out_b"
grep -q '^REASON=no_enabled_plugins: ' <<<"$out_b" || fail "case B expected REASON=no_enabled_plugins: ...:\n$out_b"
grep -q '^ENABLED_PLUGIN_COUNT=0$' <<<"$out_b" || fail "case B: a plugin set to false is not enabled:\n$out_b"
pass "enrolled with no enabled plugin warns"

# --- Case C: no entry names the repo -> ERROR, exit 1, remediation named
proj_c="${tmp_root}/c"
write_settings "$proj_c" '{
  "extraKnownMarketplaces": {"claude-plugins": {"source": {"source": "github", "repo": "someone/claude-plugins"}}},
  "enabledPlugins": {"git-plugin@claude-plugins": true}
}'
out_c="$(run_check "$proj_c")"; rc_c=$?
[ "$rc_c" -eq 1 ] || fail "case C exit $rc_c, expected 1:\n$out_c"
grep -q '^STATUS=ERROR$' <<<"$out_c" || fail "case C expected STATUS=ERROR:\n$out_c"
grep -q 'SEVERITY=ERROR TYPE=not_enrolled' <<<"$out_c" || fail "case C expected a not_enrolled row:\n$out_c"
grep -qF '/configure:claude-plugins --fix' <<<"$out_c" || fail "case C expected the /configure:claude-plugins --fix remediation:\n$out_c"
grep -q '^REASON=not_enrolled: ' <<<"$out_c" || fail "case C expected REASON=not_enrolled: ...:\n$out_c"
pass "a lookalike key under another repo is not enrollment"

# --- Case D: no project settings file -> ERROR not_enrolled
proj_d="${tmp_root}/d"
mkdir -p "$proj_d"
out_d="$(run_check "$proj_d")"; rc_d=$?
[ "$rc_d" -eq 1 ] || fail "case D exit $rc_d, expected 1:\n$out_d"
grep -q '^PROJECT_SETTINGS=MISSING$' <<<"$out_d" || fail "case D expected PROJECT_SETTINGS=MISSING:\n$out_d"
grep -q 'TYPE=not_enrolled' <<<"$out_d" || fail "case D expected not_enrolled:\n$out_d"
pass "missing project settings reports not_enrolled"

# --- Case E: invalid JSON -> ERROR invalid_settings
proj_e="${tmp_root}/e"
write_settings "$proj_e" '{"extraKnownMarketplaces": '
out_e="$(run_check "$proj_e")"; rc_e=$?
[ "$rc_e" -eq 1 ] || fail "case E exit $rc_e, expected 1:\n$out_e"
grep -q '^PROJECT_SETTINGS=INVALID$' <<<"$out_e" || fail "case E expected PROJECT_SETTINGS=INVALID:\n$out_e"
grep -q 'TYPE=invalid_settings' <<<"$out_e" || fail "case E expected invalid_settings:\n$out_e"
pass "invalid settings JSON is an ERROR, not a silent pass"

# --- Case F: --repo overrides the marketplace looked for
out_f="$(run_check "$proj_c" --repo someone/claude-plugins)"; rc_f=$?
[ "$rc_f" -eq 0 ] || fail "case F exit $rc_f, expected 0:\n$out_f"
grep -q '^MARKETPLACE_REPO=someone/claude-plugins$' <<<"$out_f" || fail "case F expected MARKETPLACE_REPO echo:\n$out_f"
grep -q '^STATUS=OK$' <<<"$out_f" || fail "case F expected STATUS=OK under --repo:\n$out_f"
pass "--repo selects another marketplace"

# --- Structured-output contract (.claude/rules/structured-script-output.md)
contract="${script_dir}/../../../../../scripts/check-structured-output-contract.sh"
if [ -f "$contract" ]; then
  for fixture_out in "$out_a" "$out_b" "$out_c" "$out_e"; do
    bash "$contract" --validate - <<<"$fixture_out" >/dev/null \
      || fail "output fails the structured-output contract:\n$fixture_out"
  done
  pass "OK, WARN and ERROR output satisfy the structured-output contract"
fi

echo "All check-marketplace-enrollment tests passed"
