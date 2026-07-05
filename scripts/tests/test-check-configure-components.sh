#!/usr/bin/env bash
# shellcheck disable=SC2016   # file-level: fixture strings deliberately contain literal backticks
# Regression test for check-configure-components.sh (the configure-plugin
# taxonomy drift guard). Fixtures prove each invariant fires:
#   A. clean fixture → STATUS=OK, exit 0
#   B. /configure:X literal in configure-all/SKILL.md not in the manifest →
#      skill_ref_unresolved (blocks reintroducing a hardcoded component list)
#   C. component missing from docs/flow.md mapping table → flow_missing_component
#   D. flow.md naming a skill not in the manifest → flow_dangling_skill
#   E. README missing a manifest skill → readme_missing_skill
#   F. on-disk skill absent from manifest → manifest_disk_drift (via lister)
# Exit 0 on success, non-zero on failure.

set -uo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
guard="${script_dir}/../check-configure-components.sh"
real_lister="${script_dir}/../../configure-plugin/skills/configure-all/scripts/list-components.sh"

fail() { echo "FAIL: $1" >&2; exit 1; }
pass() { echo "PASS: $1"; }

[ -f "$guard" ] || fail "check-configure-components.sh not found at $guard"
[ -f "$real_lister" ] || fail "list-components.sh not found at $real_lister"

sandbox="$(mktemp -d)"
[ -n "$sandbox" ] || fail "mktemp -d returned empty"
trap 'rm -rf "$sandbox"' EXIT

build_fixture() {
  rm -rf "${sandbox:?}/configure-plugin"
  local skills="${sandbox}/configure-plugin/skills"
  mkdir -p "${skills}/configure-all/scripts" "${sandbox}/configure-plugin/docs"
  cp "$real_lister" "${skills}/configure-all/scripts/list-components.sh"

  for s in configure-all configure-foo configure-bar foo-standards; do
    mkdir -p "${skills}/${s}"
    printf -- '---\nname: %s\n---\n# %s\n' "$s" "$s" > "${skills}/${s}/SKILL.md"
  done

  cat > "${skills}/configure-all/components.yaml" <<'YAML'
version: 1

domains:
  alpha: Alpha Domain

components:
  - name: configure-foo
    domain: alpha
    has_script: false
    types: all
  - name: configure-bar
    domain: alpha
    has_script: false
    types: all

orchestrators:
  - configure-all

advisory: []

reference_skills:
  - foo-standards
YAML

  cat > "${skills}/configure-all/SKILL.md" <<'MD'
---
name: configure-all
---
# /configure:all

Run `/configure:foo --check-only` and `/configure:bar --check-only`.
MD

  cat > "${sandbox}/configure-plugin/docs/flow.md" <<'MD'
# Flow

| Domain | Component skills | Reference skills |
|--------|------------------|------------------|
| Alpha Domain | `configure-foo`, `configure-bar` | `foo-standards` |
| Orchestration | `configure-all` | |
MD

  cat > "${sandbox}/configure-plugin/README.md" <<'MD'
# Configure Plugin

| Skill | Description |
|-------|-------------|
| `configure-all` | router |
| `configure-foo` | foo |
| `configure-bar` | bar |
| `foo-standards` | reference |
MD
}

# -----------------------------------------------------------------------------
# Case A: clean fixture → STATUS=OK, exit 0
# -----------------------------------------------------------------------------
build_fixture
outA="$(bash "$guard" --strict --root "$sandbox")" || fail "expected exit 0 on clean fixture:\n$outA"
echo "$outA" | grep -q "^STATUS=OK$" || fail "expected STATUS=OK on clean fixture:\n$outA"
pass "clean fixture passes"

# -----------------------------------------------------------------------------
# Case B: hardcoded /configure:X not in manifest → skill_ref_unresolved
# -----------------------------------------------------------------------------
build_fixture
printf 'Also run `/configure:ghost --check-only`.\n' >> "${sandbox}/configure-plugin/skills/configure-all/SKILL.md"
outB="$(bash "$guard" --strict --root "$sandbox")" && fail "expected failure for unresolved /configure:ghost"
echo "$outB" | grep -q "TYPE=skill_ref_unresolved" || fail "expected skill_ref_unresolved issue:\n$outB"
pass "unresolved /configure: literal in configure-all/SKILL.md fails"

# -----------------------------------------------------------------------------
# Case C: component missing from flow.md → flow_missing_component
# -----------------------------------------------------------------------------
build_fixture
sed -i.bak 's/`configure-bar`//' "${sandbox}/configure-plugin/docs/flow.md" && rm -f "${sandbox}/configure-plugin/docs/flow.md.bak"
outC="$(bash "$guard" --strict --root "$sandbox")" && fail "expected failure when flow.md omits configure-bar"
echo "$outC" | grep -q "TYPE=flow_missing_component" || fail "expected flow_missing_component issue:\n$outC"
pass "flow.md missing a component fails"

# -----------------------------------------------------------------------------
# Case D: flow.md names a skill not in the manifest → flow_dangling_skill
# -----------------------------------------------------------------------------
build_fixture
printf '| Ghost | `configure-ghost` | |\n' >> "${sandbox}/configure-plugin/docs/flow.md"
outD="$(bash "$guard" --strict --root "$sandbox")" && fail "expected failure for dangling configure-ghost in flow.md"
echo "$outD" | grep -q "TYPE=flow_dangling_skill" || fail "expected flow_dangling_skill issue:\n$outD"
pass "flow.md dangling skill fails"

# -----------------------------------------------------------------------------
# Case E: README missing a manifest skill → readme_missing_skill
# -----------------------------------------------------------------------------
build_fixture
sed -i.bak '/configure-bar/d' "${sandbox}/configure-plugin/README.md" && rm -f "${sandbox}/configure-plugin/README.md.bak"
outE="$(bash "$guard" --strict --root "$sandbox")" && fail "expected failure when README omits configure-bar"
echo "$outE" | grep -q "TYPE=readme_missing_skill" || fail "expected readme_missing_skill issue:\n$outE"
pass "README missing a skill fails"

# -----------------------------------------------------------------------------
# Case F: on-disk skill absent from manifest → manifest_disk_drift
# -----------------------------------------------------------------------------
build_fixture
mkdir -p "${sandbox}/configure-plugin/skills/configure-orphan"
printf -- '---\nname: configure-orphan\n---\n' > "${sandbox}/configure-plugin/skills/configure-orphan/SKILL.md"
outF="$(bash "$guard" --strict --root "$sandbox")" && fail "expected failure for on-disk skill missing from manifest"
echo "$outF" | grep -q "TYPE=manifest_disk_drift" || fail "expected manifest_disk_drift issue:\n$outF"
pass "on-disk skill absent from manifest fails"

echo "ALL TESTS PASSED"
