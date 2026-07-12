#!/usr/bin/env bash
# Regression test for check-pi-tiers.sh (the pi/tiers.yaml drift guard).
# Fixtures prove each invariant fires:
#   A. clean fixture → STATUS=OK, exit 0
#   B. marketplace plugin missing from the manifest → plugin_unclassified
#   C. manifest names a plugin not in marketplace → plugin_not_in_marketplace
#   D. cherry-picked skill ref with no SKILL.md → skill_ref_missing
#   E. plugin classified twice → plugin_duplicate
# Exit 0 on success, non-zero on failure.

set -uo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
guard="${script_dir}/../check-pi-tiers.sh"

fail() { echo "FAIL: $1" >&2; exit 1; }
pass() { echo "PASS: $1"; }

[ -f "$guard" ] || fail "check-pi-tiers.sh not found at $guard"

sandbox="$(mktemp -d)"
[ -n "$sandbox" ] || fail "mktemp -d returned empty"
trap 'rm -rf "$sandbox"' EXIT

build_fixture() {
  rm -rf "${sandbox:?}/pi" "${sandbox:?}/.claude-plugin" \
         "${sandbox:?}/foo-plugin" "${sandbox:?}/bar-plugin"
  mkdir -p "${sandbox}/pi" "${sandbox}/.claude-plugin" \
           "${sandbox}/foo-plugin/skills/foo-core" \
           "${sandbox}/bar-plugin/skills/bar-only"
  printf -- '---\nname: foo-core\n---\n' > "${sandbox}/foo-plugin/skills/foo-core/SKILL.md"
  printf -- '---\nname: bar-only\n---\n' > "${sandbox}/bar-plugin/skills/bar-only/SKILL.md"

  cat > "${sandbox}/.claude-plugin/marketplace.json" <<'JSON'
{
  "name": "test-marketplace",
  "plugins": [
    { "name": "foo-plugin", "source": "./foo-plugin" },
    { "name": "bar-plugin", "source": "./bar-plugin" }
  ]
}
JSON

  cat > "${sandbox}/pi/tiers.yaml" <<'YAML'
version: 1

plugins:
  foo-plugin:
    tier: general
    skills:
      - foo-core
  bar-plugin: { tier: domain, category: lang }
YAML
}

# -----------------------------------------------------------------------------
# Case A: clean fixture → STATUS=OK, exit 0
# -----------------------------------------------------------------------------
build_fixture
outA="$(bash "$guard" --strict --root "$sandbox")" || fail "expected exit 0 on clean fixture:\n$outA"
echo "$outA" | grep -q "^STATUS=OK$" || fail "expected STATUS=OK on clean fixture:\n$outA"
pass "clean fixture passes"

# -----------------------------------------------------------------------------
# Case B: marketplace plugin missing from the manifest → plugin_unclassified
# -----------------------------------------------------------------------------
build_fixture
# Drop bar-plugin from the manifest, leaving it in the marketplace.
cat > "${sandbox}/pi/tiers.yaml" <<'YAML'
version: 1

plugins:
  foo-plugin:
    tier: general
    skills:
      - foo-core
YAML
outB="$(bash "$guard" --strict --root "$sandbox")" && fail "expected failure for unclassified plugin"
echo "$outB" | grep -q "TYPE=plugin_unclassified" || fail "expected plugin_unclassified issue:\n$outB"
pass "marketplace plugin missing from manifest fails"

# -----------------------------------------------------------------------------
# Case C: manifest names a plugin not in marketplace → plugin_not_in_marketplace
# -----------------------------------------------------------------------------
build_fixture
cat >> "${sandbox}/pi/tiers.yaml" <<'YAML'
  ghost-plugin: { tier: exclude, reason: "not real" }
YAML
outC="$(bash "$guard" --strict --root "$sandbox")" && fail "expected failure for manifest plugin absent from marketplace"
echo "$outC" | grep -q "TYPE=plugin_not_in_marketplace" || fail "expected plugin_not_in_marketplace issue:\n$outC"
pass "manifest plugin not in marketplace fails"

# -----------------------------------------------------------------------------
# Case D: cherry-picked skill ref with no SKILL.md → skill_ref_missing
# -----------------------------------------------------------------------------
build_fixture
cat > "${sandbox}/pi/tiers.yaml" <<'YAML'
version: 1

plugins:
  foo-plugin:
    tier: general
    skills:
      - foo-core
      - foo-ghost
  bar-plugin: { tier: domain, category: lang }
YAML
outD="$(bash "$guard" --strict --root "$sandbox")" && fail "expected failure for missing skill ref"
echo "$outD" | grep -q "TYPE=skill_ref_missing" || fail "expected skill_ref_missing issue:\n$outD"
pass "missing cherry-picked skill ref fails"

# -----------------------------------------------------------------------------
# Case E: plugin classified twice → plugin_duplicate
# -----------------------------------------------------------------------------
build_fixture
cat >> "${sandbox}/pi/tiers.yaml" <<'YAML'
  bar-plugin: { tier: exclude, reason: "duplicate" }
YAML
outE="$(bash "$guard" --strict --root "$sandbox")" && fail "expected failure for duplicated plugin"
echo "$outE" | grep -q "TYPE=plugin_duplicate" || fail "expected plugin_duplicate issue:\n$outE"
pass "plugin classified twice fails"

echo "ALL TESTS PASSED"
