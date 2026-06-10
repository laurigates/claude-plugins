#!/usr/bin/env bash
# Regression test for code-dep-audit.sh (issue #1556).
# Asserts the deterministic procedure extracted from code-dep-audit/SKILL.md:
#   - ecosystem detection from manifest/lockfile globs
#   - severity rollup (critical/high → ERROR, medium/low/outdated → WARN)
#   - severity / behind counts parsed from audit JSON
#   - static GPL/AGPL license denylist flagging
#   - graceful degradation on empty / no-ecosystem input
# Runs offline via the CODE_DEP_AUDIT_FIXTURE seam — no real audit tool needed.
# Exit 0 on success, non-zero on any failure.

set -uo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
audit_script="${script_dir}/../code-dep-audit.sh"

fail() {
  echo "FAIL: $1" >&2
  exit 1
}

pass() {
  echo "PASS: $1"
}

if ! command -v jq >/dev/null 2>&1; then
  echo "SKIP: jq not installed; cannot run code-dep-audit tests"
  exit 0
fi

[ -f "$audit_script" ] || fail "code-dep-audit.sh not found at $audit_script"

home_dir="$(mktemp -d)"
fixtures="$(mktemp -d)"
trap 'rm -rf "$home_dir" "$fixtures"' EXIT

# -----------------------------------------------------------------------------
# Case 1: PLANTED-VULN fixture (critical+high) → STATUS=ERROR, exit 1
# -----------------------------------------------------------------------------
proj1="$(mktemp -d)"
touch "${proj1}/package.json"
cat > "${fixtures}/vuln.json" <<'JSON'
{ "severity": {"critical": 2, "high": 1, "medium": 0, "low": 0},
  "outdated": 0,
  "licenses": [] }
JSON

set +e
out1="$(CODE_DEP_AUDIT_FIXTURE="${fixtures}/vuln.json" \
  bash "$audit_script" --home-dir "$home_dir" --project-dir "$proj1")"
rc1=$?
set -e
[ "$rc1" -eq 1 ] || fail "planted critical+high vuln must exit 1, got $rc1:\n$out1"
echo "$out1" | grep -q "^ECOSYSTEM=js$" \
  || fail "expected ECOSYSTEM=js from package.json, got:\n$out1"
echo "$out1" | grep -q "^STATUS=ERROR$" \
  || fail "expected STATUS=ERROR for critical/high vulns, got:\n$out1"
echo "$out1" | grep -q "^VULN_CRITICAL=2$" \
  || fail "expected VULN_CRITICAL=2, got:\n$out1"
echo "$out1" | grep -q "^VULN_HIGH=1$" \
  || fail "expected VULN_HIGH=1, got:\n$out1"
pass "planted critical+high vuln yields STATUS=ERROR with correct severity counts"
rm -rf "$proj1"

# -----------------------------------------------------------------------------
# Case 2: medium/low + outdated fixture → STATUS=WARN, exit 0
# -----------------------------------------------------------------------------
proj2="$(mktemp -d)"
touch "${proj2}/requirements.txt"
cat > "${fixtures}/warn.json" <<'JSON'
{ "severity": {"critical": 0, "high": 0, "medium": 3, "low": 5},
  "outdated": 7,
  "licenses": [] }
JSON

set +e
out2="$(CODE_DEP_AUDIT_FIXTURE="${fixtures}/warn.json" \
  bash "$audit_script" --home-dir "$home_dir" --project-dir "$proj2")"
rc2=$?
set -e
[ "$rc2" -eq 0 ] || fail "medium/low/outdated only must exit 0, got $rc2:\n$out2"
echo "$out2" | grep -q "^ECOSYSTEM=python$" \
  || fail "expected ECOSYSTEM=python from requirements.txt, got:\n$out2"
echo "$out2" | grep -q "^STATUS=WARN$" \
  || fail "expected STATUS=WARN for medium/low/outdated, got:\n$out2"
echo "$out2" | grep -q "^VULN_MEDIUM=3$" \
  || fail "expected VULN_MEDIUM=3, got:\n$out2"
echo "$out2" | grep -q "^OUTDATED_COUNT=7$" \
  || fail "expected OUTDATED_COUNT=7, got:\n$out2"
pass "medium/low + outdated yields STATUS=WARN with correct behind count"
rm -rf "$proj2"

# -----------------------------------------------------------------------------
# Case 3: problematic GPL/AGPL license fixture → flagged as WARN
# -----------------------------------------------------------------------------
proj3="$(mktemp -d)"
touch "${proj3}/Cargo.toml"
cat > "${fixtures}/license.json" <<'JSON'
{ "severity": {"critical": 0, "high": 0, "medium": 0, "low": 0},
  "outdated": 0,
  "licenses": [
    {"package": "clean-pkg", "license": "MIT"},
    {"package": "copyleft-pkg", "license": "GPL-3.0"},
    {"package": "strong-copyleft", "license": "AGPL-3.0"}
  ] }
JSON

set +e
out3="$(CODE_DEP_AUDIT_FIXTURE="${fixtures}/license.json" \
  bash "$audit_script" --home-dir "$home_dir" --project-dir "$proj3")"
rc3=$?
set -e
[ "$rc3" -eq 0 ] || fail "license-only WARN must exit 0, got $rc3:\n$out3"
echo "$out3" | grep -q "^ECOSYSTEM=rust$" \
  || fail "expected ECOSYSTEM=rust from Cargo.toml, got:\n$out3"
echo "$out3" | grep -q "^STATUS=WARN$" \
  || fail "expected STATUS=WARN for problematic licenses, got:\n$out3"
echo "$out3" | grep -q "^LICENSE_ISSUES=2$" \
  || fail "expected LICENSE_ISSUES=2 (GPL + AGPL, MIT clean), got:\n$out3"
echo "$out3" | grep -q "copyleft-pkg=GPL-3.0" \
  || fail "expected GPL package flagged by name, got:\n$out3"
echo "$out3" | grep -q "strong-copyleft=AGPL-3.0" \
  || fail "expected AGPL package flagged by name, got:\n$out3"
pass "GPL/AGPL licenses flagged (count=2), MIT not flagged"
rm -rf "$proj3"

# -----------------------------------------------------------------------------
# Case 4: CLEAN fixture (no vulns, no outdated, no bad licenses) → STATUS=OK
# -----------------------------------------------------------------------------
proj4="$(mktemp -d)"
touch "${proj4}/go.mod"
cat > "${fixtures}/clean.json" <<'JSON'
{ "severity": {"critical": 0, "high": 0, "medium": 0, "low": 0},
  "outdated": 0,
  "licenses": [{"package": "ok-pkg", "license": "Apache-2.0"}] }
JSON

set +e
out4="$(CODE_DEP_AUDIT_FIXTURE="${fixtures}/clean.json" \
  bash "$audit_script" --home-dir "$home_dir" --project-dir "$proj4")"
rc4=$?
set -e
[ "$rc4" -eq 0 ] || fail "clean fixture must exit 0, got $rc4:\n$out4"
echo "$out4" | grep -q "^ECOSYSTEM=go$" \
  || fail "expected ECOSYSTEM=go from go.mod, got:\n$out4"
echo "$out4" | grep -q "^STATUS=OK$" \
  || fail "expected STATUS=OK for clean deps, got:\n$out4"
echo "$out4" | grep -q "^ISSUE_COUNT=0$" \
  || fail "expected ISSUE_COUNT=0 for clean deps, got:\n$out4"
echo "$out4" | grep -q "^VULN_TOTAL=0$" \
  || fail "expected VULN_TOTAL=0, got:\n$out4"
echo "$out4" | grep -q "^LICENSE_ISSUES=0$" \
  || fail "expected LICENSE_ISSUES=0, got:\n$out4"
pass "clean fixture yields STATUS=OK and zero counts"
rm -rf "$proj4"

# -----------------------------------------------------------------------------
# Case 5: no recognized ecosystem → STATUS=OK, ECOSYSTEM=none, graceful exit 0
# -----------------------------------------------------------------------------
proj5="$(mktemp -d)"
set +e
out5="$(bash "$audit_script" --home-dir "$home_dir" --project-dir "$proj5")"
rc5=$?
set -e
[ "$rc5" -eq 0 ] || fail "no-ecosystem must exit 0, got $rc5:\n$out5"
echo "$out5" | grep -q "^ECOSYSTEM=none$" \
  || fail "expected ECOSYSTEM=none when no manifest present, got:\n$out5"
echo "$out5" | grep -q "^STATUS=OK$" \
  || fail "expected STATUS=OK when no ecosystem detected, got:\n$out5"
pass "no recognized ecosystem degrades gracefully to STATUS=OK"
rm -rf "$proj5"

# -----------------------------------------------------------------------------
# Case 6: empty seam input (empty fixture file) → graceful, no crash
# -----------------------------------------------------------------------------
proj6="$(mktemp -d)"
touch "${proj6}/package.json"
: > "${fixtures}/empty.json"

set +e
out6="$(CODE_DEP_AUDIT_FIXTURE="${fixtures}/empty.json" \
  bash "$audit_script" --home-dir "$home_dir" --project-dir "$proj6")"
rc6=$?
set -e
echo "$out6" | grep -q "^=== END CODE DEP AUDIT ===$" \
  || fail "empty seam input must still emit a closed section, got:\n$out6"
echo "$out6" | grep -q "^STATUS=" \
  || fail "empty seam input must still emit a STATUS line, got:\n$out6"
# Empty seam input means "no audit data gathered" → no issues to roll up.
# Graceful handling is a clean STATUS=OK / exit 0, not a crash.
[ "$rc6" -eq 0 ] || fail "empty seam input should degrade gracefully (exit 0), got $rc6:\n$out6"
echo "$out6" | grep -q "^STATUS=OK$" \
  || fail "expected STATUS=OK for empty seam input, got:\n$out6"
echo "$out6" | grep -q "^ISSUE_COUNT=0$" \
  || fail "expected ISSUE_COUNT=0 for empty seam input, got:\n$out6"
pass "empty seam input degrades gracefully (no audit data → STATUS=OK), no crash"
rm -rf "$proj6"

# -----------------------------------------------------------------------------
# Case 7: malformed JSON fixture (non-empty, unparseable) → STATUS=ERROR, exit 1
# -----------------------------------------------------------------------------
proj7="$(mktemp -d)"
touch "${proj7}/package.json"
printf '{ this is not valid json' > "${fixtures}/broken.json"

set +e
out7="$(CODE_DEP_AUDIT_FIXTURE="${fixtures}/broken.json" \
  bash "$audit_script" --home-dir "$home_dir" --project-dir "$proj7")"
rc7=$?
set -e
[ "$rc7" -eq 1 ] || fail "malformed JSON should ERROR (exit 1), got $rc7:\n$out7"
echo "$out7" | grep -q "^AUDIT_JSON_VALID=false$" \
  || fail "expected AUDIT_JSON_VALID=false for malformed JSON, got:\n$out7"
echo "$out7" | grep -q "^STATUS=ERROR$" \
  || fail "expected STATUS=ERROR for malformed JSON, got:\n$out7"
pass "malformed JSON seam input fails loudly (STATUS=ERROR, exit 1)"
rm -rf "$proj7"

echo "ALL TESTS PASSED"
