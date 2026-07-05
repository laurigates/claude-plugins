#!/usr/bin/env bash
# Regression test for list-components.sh.
# Fixture manifests + skill trees prove: a clean manifest lists every
# component with domain/script flags (STATUS=OK); a manifest entry missing on
# disk is an ERROR; an on-disk skill absent from the manifest is an ERROR
# (the invariant that keeps /configure:all actually meaning "all");
# --domain filters the component rows.
# Exit 0 on success, non-zero on failure.

set -uo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
lister="${script_dir}/../list-components.sh"

fail() { echo "FAIL: $1" >&2; exit 1; }
pass() { echo "PASS: $1"; }

[ -f "$lister" ] || fail "list-components.sh not found at $lister"

sandbox="$(mktemp -d)"
[ -n "$sandbox" ] || fail "mktemp -d returned empty"
trap 'rm -rf "$sandbox"' EXIT

make_skill() {
  mkdir -p "${sandbox}/skills/$1"
  printf -- '---\nname: %s\n---\n# %s\n' "$1" "$1" > "${sandbox}/skills/$1/SKILL.md"
}

write_manifest() {
  cat > "${sandbox}/components.yaml" <<'YAML'
version: 1

domains:
  alpha: Alpha Domain
  beta: Beta Domain

components:
  - name: configure-foo
    domain: alpha
    has_script: true
    types: all
  - name: configure-bar
    domain: beta
    has_script: false
    types: python

orchestrators:
  - configure-all

advisory: []

reference_skills:
  - foo-standards
YAML
}

# -----------------------------------------------------------------------------
# Case 1: clean manifest ↔ disk → STATUS=OK, component rows carry metadata
# -----------------------------------------------------------------------------
make_skill configure-foo
mkdir -p "${sandbox}/skills/configure-foo/scripts"
printf '#!/usr/bin/env bash\n' > "${sandbox}/skills/configure-foo/scripts/configure-foo.sh"
make_skill configure-bar
make_skill configure-all
make_skill foo-standards
write_manifest

out1="$(bash "$lister" --manifest "${sandbox}/components.yaml" --skills-dir "${sandbox}/skills")"
echo "$out1" | grep -q "^COMPONENT=configure-foo DOMAIN=alpha HAS_SCRIPT=true TYPES=all$" || fail "expected configure-foo row with script+domain:\n$out1"
echo "$out1" | grep -q "^COMPONENT=configure-bar DOMAIN=beta HAS_SCRIPT=false TYPES=python$" || fail "expected configure-bar row:\n$out1"
echo "$out1" | grep -q "^COMPONENT_COUNT=2$" || fail "expected COMPONENT_COUNT=2:\n$out1"
echo "$out1" | grep -q "^STATUS=OK$" || fail "expected STATUS=OK for clean fixture:\n$out1"
pass "clean manifest lists components with STATUS=OK"

# -----------------------------------------------------------------------------
# Case 2: manifest entry missing on disk → ERROR missing_on_disk, exit 1
# -----------------------------------------------------------------------------
rm -rf "${sandbox}/skills/configure-bar"
out2="$(bash "$lister" --manifest "${sandbox}/components.yaml" --skills-dir "${sandbox}/skills")" && rc2=0 || rc2=$?
[ "$rc2" -ne 0 ] || fail "expected non-zero exit when a manifest entry is missing on disk"
echo "$out2" | grep -q "TYPE=missing_on_disk" || fail "expected missing_on_disk issue:\n$out2"
pass "manifest entry missing on disk raises ERROR"
make_skill configure-bar

# -----------------------------------------------------------------------------
# Case 3: on-disk skill absent from manifest → ERROR unlisted_skill, exit 1
# -----------------------------------------------------------------------------
make_skill configure-orphan
out3="$(bash "$lister" --manifest "${sandbox}/components.yaml" --skills-dir "${sandbox}/skills")" && rc3=0 || rc3=$?
[ "$rc3" -ne 0 ] || fail "expected non-zero exit for an unlisted on-disk skill"
echo "$out3" | grep -q "TYPE=unlisted_skill" || fail "expected unlisted_skill issue:\n$out3"
echo "$out3" | grep -q "configure-orphan" || fail "expected the orphan skill named:\n$out3"
pass "unlisted on-disk skill raises ERROR"
rm -rf "${sandbox}/skills/configure-orphan"

# -----------------------------------------------------------------------------
# Case 4: --domain filters component rows
# -----------------------------------------------------------------------------
out4="$(bash "$lister" --manifest "${sandbox}/components.yaml" --skills-dir "${sandbox}/skills" --domain alpha)"
echo "$out4" | grep -q "^COMPONENT=configure-foo " || fail "expected configure-foo under --domain alpha:\n$out4"
if echo "$out4" | grep -q "^COMPONENT=configure-bar "; then
  fail "did not expect configure-bar under --domain alpha:\n$out4"
fi
pass "--domain filters component rows"

echo "ALL TESTS PASSED"
