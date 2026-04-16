#!/usr/bin/env bash
# Regression test for fix-registry.sh stale enabledPlugins handling.
# Also guards health-check SKILL.md against the `!\`` context-command antipattern.
# Exit 0 on success, non-zero on failure.

set -uo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
fix_script="${script_dir}/fix-registry.sh"
health_check_skill="${script_dir}/../../health-check/SKILL.md"

fail() {
  echo "FAIL: $1" >&2
  exit 1
}

pass() {
  echo "PASS: $1"
}

# -----------------------------------------------------------------------------
# Guard 1: health-check SKILL.md must not use the `!\`` context-command antipattern
# -----------------------------------------------------------------------------
if grep -n '!`' "$health_check_skill" | grep -E '!`(echo|printf|eval)' >/dev/null; then
  fail "health-check/SKILL.md contains !\`echo|printf|eval backtick antipattern"
fi
pass "health-check/SKILL.md free of forbidden !\`echo backtick"

# -----------------------------------------------------------------------------
# Guard 2: fix-registry.sh cleans stale enabledPlugins in --dry-run
# -----------------------------------------------------------------------------
if ! command -v jq >/dev/null 2>&1; then
  echo "SKIP: jq not installed; cannot run fix-registry dry-run test"
  exit 0
fi

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

registry_file="${tmp_dir}/installed_plugins.json"
settings_file="${tmp_dir}/settings.json"
marketplaces_dir="${tmp_dir}/marketplaces"
mkdir -p "$marketplaces_dir/test-mp"

# Registry contains only 'good-plugin'.
cat > "$registry_file" <<'JSON'
{
  "version": 2,
  "plugins": {
    "good-plugin@test-mp": [
      {"scope": "user", "version": "1.0.0", "installPath": "/tmp/good"}
    ]
  }
}
JSON

# Marketplace lists 'good-plugin' and 'installable-plugin' (enabled but not installed).
cat > "${marketplaces_dir}/test-mp/marketplace.json" <<'JSON'
{
  "name": "test-mp",
  "plugins": [
    {"name": "good-plugin"},
    {"name": "installable-plugin"}
  ]
}
JSON

# settings.json has: good (valid), installable (enabled_not_installed), stale (fully gone).
cat > "$settings_file" <<'JSON'
{
  "enabledPlugins": {
    "good-plugin@test-mp": true,
    "installable-plugin@test-mp": true,
    "stale-plugin@dead-mp": true
  }
}
JSON

output=$(
  FIX_REGISTRY_FILE="$registry_file" \
  FIX_SETTINGS_FILE="$settings_file" \
  FIX_MARKETPLACES_DIR="$marketplaces_dir" \
  bash "$fix_script" --home-dir "$tmp_dir" --project-dir "$tmp_dir" --dry-run
)

echo "--- fix-registry.sh --dry-run output ---"
echo "$output"
echo "----------------------------------------"

# Stale key must be reported.
if ! grep -q 'STALE_ENABLED: key=stale-plugin@dead-mp' <<<"$output"; then
  fail "stale-plugin@dead-mp not reported as stale"
fi
pass "stale-plugin@dead-mp reported"

# Good keys must NOT be reported as stale.
if grep -q 'STALE_ENABLED: key=good-plugin@test-mp' <<<"$output"; then
  fail "good-plugin@test-mp incorrectly flagged as stale"
fi
if grep -q 'STALE_ENABLED: key=installable-plugin@test-mp' <<<"$output"; then
  fail "installable-plugin@test-mp incorrectly flagged as stale (should be kept)"
fi
pass "valid keys preserved"

# STALE_ENABLED_COUNT must be exactly 1.
if ! grep -q '^STALE_ENABLED_COUNT=1$' <<<"$output"; then
  fail "expected STALE_ENABLED_COUNT=1"
fi
pass "STALE_ENABLED_COUNT=1"

# Dry-run must not modify settings.json.
if ! diff -q <(jq -S . "$settings_file") <(cat <<'JSON' | jq -S .
{
  "enabledPlugins": {
    "good-plugin@test-mp": true,
    "installable-plugin@test-mp": true,
    "stale-plugin@dead-mp": true
  }
}
JSON
) >/dev/null; then
  fail "--dry-run modified settings.json"
fi
pass "--dry-run preserved settings.json"

# RESTART_REQUIRED should be emitted on dry-run when stale keys would be removed.
if ! grep -q '^RESTART_REQUIRED=true$' <<<"$output"; then
  fail "expected RESTART_REQUIRED=true in dry-run output"
fi
pass "RESTART_REQUIRED=true emitted in dry-run"

echo "ALL CHECKS PASSED"
exit 0
