#!/usr/bin/env bash
# shellcheck disable=SC2015  # test idiom: `cond && pass || fail` — `pass` returns 0
# Regression tests for scripts/sync-plugin-configs.py
#
# Tests both check mode and fix mode to ensure configuration files stay in sync
# with actual plugin directories.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SYNC_SCRIPT="$SCRIPT_DIR/sync-plugin-configs.py"

PASS=0
FAIL=0

pass() { printf "  PASS: %s\n" "$1"; PASS=$((PASS + 1)); }
fail() { printf "  FAIL: %s\n" "$1"; FAIL=$((FAIL + 1)); }

# Create a mock repository root with necessary files
make_mock_repo() {
  local repo
  repo=$(mktemp -d) || return 1
  [ -n "$repo" ] && [ -d "$repo" ] || return 1

  # Create base config files
  echo '{"packages": {}}' > "$repo/release-please-config.json"
  echo '{}' > "$repo/.release-please-manifest.json"

  mkdir -p "$repo/.claude-plugin"
  echo '{"plugins": []}' > "$repo/.claude-plugin/marketplace.json"

  # Create a valid plugin
  mkdir -p "$repo/valid-plugin/.claude-plugin"
  cat << 'JSON' > "$repo/valid-plugin/.claude-plugin/plugin.json"
{
  "name": "valid-plugin",
  "version": "1.0.0",
  "description": "A valid test plugin",
  "keywords": ["testing"]
}
JSON

  # A plugin whose manifest already declares author + license: the generated
  # marketplace entry must mirror them rather than overwrite with defaults.
  mkdir -p "$repo/licensed-plugin/.claude-plugin"
  cat << 'JSON' > "$repo/licensed-plugin/.claude-plugin/plugin.json"
{
  "name": "licensed-plugin",
  "version": "1.0.0",
  "description": "A plugin with explicit author and license",
  "author": {"name": "Fixture Author", "url": "https://example.invalid/fixture"},
  "license": "MIT",
  "keywords": ["testing"]
}
JSON

  # Create an orphaned entry in release-please-config.json
  echo '{"packages": {"orphaned-plugin": {"component": "orphaned-plugin"}}}' > "$repo/release-please-config.json"

  # Create a version mismatch in manifest and marketplace
  mkdir -p "$repo/mismatch-plugin/.claude-plugin"
  cat << 'JSON' > "$repo/mismatch-plugin/.claude-plugin/plugin.json"
{
  "name": "mismatch-plugin",
  "version": "2.0.0",
  "description": "A mismatch test plugin"
}
JSON

  echo '{"mismatch-plugin": "1.0.0"}' > "$repo/.release-please-manifest.json"

  cat << 'JSON' > "$repo/.claude-plugin/marketplace.json"
{
  "plugins": [
    {
      "name": "mismatch-plugin",
      "version": "1.5.0",
      "description": "A mismatch test plugin",
      "source": "./mismatch-plugin",
      "category": "development"
    }
  ]
}
JSON

  echo "$repo"
}

echo "=== sync-plugin-configs regression tests ==="

repo=$(make_mock_repo)
if [ -z "$repo" ] || [ ! -d "$repo" ]; then
  echo "setup failed" >&2
  FAIL=$((FAIL + 1))
else

  # --- Test 1: Check Mode (should identify issues and exit 1) ---
  echo "--- Testing Check Mode ---"
  out1=$(python3 "$SYNC_SCRIPT" --repo-root "$repo" 2>&1) || rc1=$?
  rc1=${rc1:-0}

  [ "$rc1" -eq 1 ] \
    && pass "check mode: exits 1 with issues" \
    || fail "check mode: expected exit 1, got $rc1. Output: $out1"

  echo "$out1" | grep -q "Plugin 'valid-plugin' missing from release-please-config.json" \
    && pass "check mode: identifies missing release-please-config entry" \
    || fail "check mode: failed to identify missing release-please-config entry"

  echo "$out1" | grep -q "Orphaned entry 'orphaned-plugin' in release-please-config.json" \
    && pass "check mode: identifies orphaned release-please-config entry" \
    || fail "check mode: failed to identify orphaned release-please-config entry"

  echo "$out1" | grep -q "Plugin 'valid-plugin' missing from .release-please-manifest.json" \
    && pass "check mode: identifies missing manifest entry" \
    || fail "check mode: failed to identify missing manifest entry"

  echo "$out1" | grep -q "Plugin 'valid-plugin' missing from .claude-plugin/marketplace.json" \
    && pass "check mode: identifies missing marketplace entry" \
    || fail "check mode: failed to identify missing marketplace entry"

  echo "$out1" | grep -q "Version mismatch for 'mismatch-plugin': manifest=1.0.0, marketplace=1.5.0" \
    && pass "check mode: identifies version mismatch" \
    || fail "check mode: failed to identify version mismatch. Output: $out1"


  # --- Test 2: Fix Mode (should apply fixes and exit 0) ---
  echo "--- Testing Fix Mode ---"
  out2=$(python3 "$SYNC_SCRIPT" --fix --repo-root "$repo" 2>&1) || rc2=$?
  rc2=${rc2:-0}

  [ "$rc2" -eq 0 ] \
    && pass "fix mode: exits 0 after applying fixes" \
    || fail "fix mode: expected exit 0, got $rc2. Output: $out2"

  # Verify release-please-config.json was fixed
  grep -q '"valid-plugin"' "$repo/release-please-config.json" \
    && pass "fix mode: added valid-plugin to release-please-config.json" \
    || fail "fix mode: failed to add valid-plugin to release-please-config.json"

  grep -q '"orphaned-plugin"' "$repo/release-please-config.json" \
    && fail "fix mode: failed to remove orphaned-plugin from release-please-config.json" \
    || pass "fix mode: removed orphaned-plugin from release-please-config.json"

  # Verify manifest was fixed
  grep -q '"valid-plugin": "1.0.0"' "$repo/.release-please-manifest.json" \
    && pass "fix mode: added valid-plugin to manifest" \
    || fail "fix mode: failed to add valid-plugin to manifest"

  # Verify marketplace was fixed
  # Read the entry as JSON, not as a fixed `grep -A N` line window: the entry
  # now also carries author + license (#2698), which pushes `category` past any
  # window sized for the old six-key shape.
  valid_category=$(python3 -c 'import json,sys
print(next((p.get("category","") for p in json.load(open(sys.argv[1]))["plugins"] if p["name"]=="valid-plugin"), ""))' \
    "$repo/.claude-plugin/marketplace.json")
  [ "$valid_category" = "testing" ] \
    && pass "fix mode: added valid-plugin to marketplace with correct inferred category" \
    || fail "fix mode: failed to add valid-plugin to marketplace with category"

  # #2698: a generated entry carries author + license. valid-plugin's manifest
  # declares neither, so the entry takes the defaults (the root MIT LICENSE and
  # the marketplace owner); licensed-plugin's entry mirrors its own manifest.
  # Before the fix create_marketplace_entry emitted only name/source/
  # description/version/keywords/category, so both reads below were empty.
  entry_meta() {
    python3 -c 'import json,sys
e=[p for p in json.load(open(sys.argv[1]))["plugins"] if p["name"]==sys.argv[2]]
e=e[0] if e else {}
a=e.get("author")
print("%s|%s|%s" % (a.get("name","") if isinstance(a,dict) else "", a.get("url","") if isinstance(a,dict) else "", e.get("license","")))' \
      "$repo/.claude-plugin/marketplace.json" "$1"
  }
  valid_meta=$(entry_meta valid-plugin)
  [ "$valid_meta" = "Lauri Gates||MIT" ] \
    && pass "fix mode: generated entry carries default author + license (MIT)" \
    || fail "fix mode: generated entry lacks author/license. Got: '$valid_meta'"

  licensed_meta=$(entry_meta licensed-plugin)
  [ "$licensed_meta" = "Fixture Author|https://example.invalid/fixture|MIT" ] \
    && pass "fix mode: generated entry mirrors the manifest's author + license" \
    || fail "fix mode: generated entry did not mirror manifest author/license. Got: '$licensed_meta'"

  # Verify version mismatch was fixed in marketplace to match manifest
  marketplace_mismatch_version=$(grep -A 8 '"name": "mismatch-plugin"' "$repo/.claude-plugin/marketplace.json" | grep '"version"' | awk -F'"' '{print $4}')
  [ "$marketplace_mismatch_version" = "1.0.0" ] \
    && pass "fix mode: synced marketplace version to manifest version (1.0.0)" \
    || fail "fix mode: failed to sync marketplace version. Got: $marketplace_mismatch_version"

  # --- Test 3: Idempotency (should exit 0 with no issues) ---
  echo "--- Testing Idempotency ---"
  out3=$(python3 "$SYNC_SCRIPT" --repo-root "$repo" 2>&1) || rc3=$?
  rc3=${rc3:-0}

  [ "$rc3" -eq 0 ] \
    && pass "idempotency: exits 0 with no issues after fix" \
    || fail "idempotency: expected exit 0, got $rc3. Output: $out3"

  echo "$out3" | grep -q "All plugin configurations are in sync!" \
    && pass "idempotency: reports all in sync" \
    || fail "idempotency: failed to report all in sync. Output: $out3"

  rm -rf "$repo"
fi

echo "=== Results: $PASS passed, $FAIL failed ==="
[ "$FAIL" -eq 0 ]
