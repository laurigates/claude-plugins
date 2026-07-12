#!/usr/bin/env bash
# Regression test for install-pi.sh (the tier-driven pi skills installer).
# Uses a fixture repo (manifest + fake plugins) so paths are hermetic.
# Asserts:
#   A. general tier lands the cherry-picked core (foo-core, foo-extra) — the
#      full plugin's other skills are NOT installed
#   B. --category infra lands only infra-domain skills; other domains absent
#   C. exclude-tier plugins are never copied
#   D. --dry-run writes nothing
#   E. a real run drops the receipt
# Exit 0 on success, non-zero on failure.

set -uo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
installer="${script_dir}/../install-pi.sh"

fail() { echo "FAIL: $1" >&2; exit 1; }
pass() { echo "PASS: $1"; }

[ -f "$installer" ] || fail "install-pi.sh not found at $installer"

sandbox="$(mktemp -d)"
[ -n "$sandbox" ] || fail "mktemp -d returned empty"
trap 'rm -rf "$sandbox"' EXIT

fixture="${sandbox}/repo"

build_fixture() {
  rm -rf "${fixture:?}"
  mkdir -p "${fixture}/pi"

  # A general plugin with a cherry-pick list (core = foo-core, foo-extra;
  # foo-noise exists on disk but is NOT listed, so must be dropped).
  for s in foo-core foo-extra foo-noise; do
    mkdir -p "${fixture}/gen-plugin/skills/${s}"
    printf -- '---\nname: %s\n---\n' "$s" > "${fixture}/gen-plugin/skills/${s}/SKILL.md"
  done
  # A domain/infra plugin (no cherry-pick -> all skills).
  mkdir -p "${fixture}/box-plugin/skills/box-run"
  printf -- '---\nname: box-run\n---\n' > "${fixture}/box-plugin/skills/box-run/SKILL.md"
  # A domain/lang plugin (different category — must not appear for infra).
  mkdir -p "${fixture}/lang-plugin/skills/lang-fmt"
  printf -- '---\nname: lang-fmt\n---\n' > "${fixture}/lang-plugin/skills/lang-fmt/SKILL.md"
  # An exclude plugin (never copied).
  mkdir -p "${fixture}/meta-plugin/skills/meta-thing"
  printf -- '---\nname: meta-thing\n---\n' > "${fixture}/meta-plugin/skills/meta-thing/SKILL.md"

  cat > "${fixture}/pi/tiers.yaml" <<'YAML'
version: 1

plugins:
  gen-plugin:
    tier: general
    skills:
      - foo-core
      - foo-extra
  box-plugin: { tier: domain, category: infra }
  lang-plugin: { tier: domain, category: lang }
  meta-plugin: { tier: exclude, reason: "meta" }
YAML
}

# -----------------------------------------------------------------------------
# Case A: general tier lands cherry-picked core, drops the unlisted skill
# -----------------------------------------------------------------------------
build_fixture
gdest="${sandbox}/pi-home"
PI_HOME="$gdest" bash "$installer" --root "$fixture" --scope global >/dev/null 2>&1 \
  || fail "general install exited non-zero"
[ -f "${gdest}/skills/foo-core/SKILL.md" ] || fail "foo-core (cherry-picked) not installed"
[ -f "${gdest}/skills/foo-extra/SKILL.md" ] || fail "foo-extra (cherry-picked) not installed"
[ -e "${gdest}/skills/foo-noise" ] && fail "foo-noise (unlisted) should NOT be installed"
[ -e "${gdest}/skills/box-run" ] && fail "domain skill leaked into a general install"
pass "general tier lands only the cherry-picked core"

# -----------------------------------------------------------------------------
# Case B: --category infra lands only infra-domain skills
# -----------------------------------------------------------------------------
build_fixture
pdest="${sandbox}/proj"
mkdir -p "$pdest"
PI_PROJECT_DIR="$pdest" bash "$installer" --root "$fixture" --category infra >/dev/null 2>&1 \
  || fail "infra install exited non-zero"
[ -f "${pdest}/.pi/skills/box-run/SKILL.md" ] || fail "infra skill box-run not installed"
[ -e "${pdest}/.pi/skills/lang-fmt" ] && fail "lang-domain skill leaked into an infra install"
[ -e "${pdest}/.pi/skills/foo-core" ] && fail "general skill leaked into a domain install"
pass "--category infra lands only infra-domain skills"

# -----------------------------------------------------------------------------
# Case C: exclude-tier plugins are never copied
# -----------------------------------------------------------------------------
# (covered implicitly above, asserted explicitly here across both scopes)
[ -e "${gdest}/skills/meta-thing" ] && fail "exclude plugin copied into global scope"
[ -e "${pdest}/.pi/skills/meta-thing" ] && fail "exclude plugin copied into project scope"
pass "exclude-tier plugins are never copied"

# -----------------------------------------------------------------------------
# Case D: --dry-run writes nothing
# -----------------------------------------------------------------------------
build_fixture
ddest="${sandbox}/dry"
PI_HOME="$ddest" bash "$installer" --root "$fixture" --scope global --dry-run >/dev/null 2>&1 \
  || fail "dry-run exited non-zero"
[ -d "$ddest" ] && [ -n "$(find "$ddest" -mindepth 1 2>/dev/null)" ] && fail "--dry-run wrote to disk"
pass "--dry-run writes nothing"

# -----------------------------------------------------------------------------
# Case E: a real run drops the receipt
# -----------------------------------------------------------------------------
[ -f "${gdest}/skills/.claude-plugins-pi-receipt" ] || fail "receipt not dropped after real install"
pass "real run drops the receipt"

echo "ALL TESTS PASSED"
