#!/usr/bin/env bash
# Regression test for configure-security.sh detection.
# A planted fixture WITH Dependabot + CodeQL + gitleaks + SECURITY.md must report
# all four present; a bare fixture must report them missing with STATUS=WARN.
# Exit 0 on success, non-zero on failure.

set -uo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
check_script="${script_dir}/../configure-security.sh"

fail() { echo "FAIL: $1" >&2; exit 1; }
pass() { echo "PASS: $1"; }

[ -f "$check_script" ] || fail "configure-security.sh not found at $check_script"

# -----------------------------------------------------------------------------
# Case 1: fully-configured project → all layers present, STATUS=OK
# -----------------------------------------------------------------------------
full="$(mktemp -d)"
trap 'rm -rf "$full"' EXIT
mkdir -p "${full}/.github/workflows"
printf '{}' > "${full}/package.json"
printf 'version: 2\nupdates: []\n' > "${full}/.github/dependabot.yml"
printf 'name: CodeQL\njobs:\n  analyze:\n    steps:\n      - uses: github/codeql-action/analyze@v3\n' \
  > "${full}/.github/workflows/codeql.yml"
printf '[allowlist]\n' > "${full}/.gitleaks.toml"
printf 'repos:\n  - repo: https://github.com/gitleaks/gitleaks\n' > "${full}/.pre-commit-config.yaml"
printf '# Security Policy\n' > "${full}/SECURITY.md"

out1="$(bash "$check_script" --home-dir "$HOME" --project-dir "$full")"
echo "$out1" | grep -q "^DEPENDABOT=true$" || fail "expected DEPENDABOT=true:\n$out1"
echo "$out1" | grep -q "^CODEQL=true$" || fail "expected CODEQL=true:\n$out1"
echo "$out1" | grep -q "^GITLEAKS_CONFIG=true$" || fail "expected GITLEAKS_CONFIG=true:\n$out1"
echo "$out1" | grep -q "^SECURITY_POLICY=true$" || fail "expected SECURITY_POLICY=true:\n$out1"
echo "$out1" | grep -q "^PRE_COMMIT_GITLEAKS=true$" || fail "expected PRE_COMMIT_GITLEAKS=true:\n$out1"
echo "$out1" | grep -q "^SECURITY_LAYERS_PRESENT=3$" || fail "expected SECURITY_LAYERS_PRESENT=3:\n$out1"
echo "$out1" | grep -q "^STATUS=OK$" || fail "expected STATUS=OK for fully-configured project:\n$out1"
echo "$out1" | grep -q "^LANG_JS=true$" || fail "expected LANG_JS=true:\n$out1"
pass "fully-configured project reports all security layers present and STATUS=OK"
rm -rf "$full"

# -----------------------------------------------------------------------------
# Case 2: bare project → all missing, STATUS=WARN
# -----------------------------------------------------------------------------
bare="$(mktemp -d)"
out2="$(bash "$check_script" --home-dir "$HOME" --project-dir "$bare")"
echo "$out2" | grep -q "^DEPENDABOT=false$" || fail "expected DEPENDABOT=false:\n$out2"
echo "$out2" | grep -q "^CODEQL=false$" || fail "expected CODEQL=false:\n$out2"
echo "$out2" | grep -q "^GITLEAKS_CONFIG=false$" || fail "expected GITLEAKS_CONFIG=false:\n$out2"
echo "$out2" | grep -q "^SECURITY_POLICY=false$" || fail "expected SECURITY_POLICY=false:\n$out2"
echo "$out2" | grep -q "^SECURITY_LAYERS_PRESENT=0$" || fail "expected SECURITY_LAYERS_PRESENT=0:\n$out2"
echo "$out2" | grep -q "^STATUS=WARN$" || fail "expected STATUS=WARN for bare project:\n$out2"
echo "$out2" | grep -q "^ISSUE_COUNT=4$" || fail "expected ISSUE_COUNT=4 for bare project:\n$out2"
pass "bare project reports all security layers missing and STATUS=WARN"
rm -rf "$bare"

echo "ALL TESTS PASSED"
