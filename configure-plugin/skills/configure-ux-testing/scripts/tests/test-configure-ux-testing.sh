#!/usr/bin/env bash
# Regression test for configure-ux-testing.sh detection.
# A planted fixture with a playwright config + e2e dir (+ axe dep + playwright
# MCP via the offline seam) must be detected; a bare fixture must not.
# SKIP (exit 0) if jq is absent.
# Exit 0 on success, non-zero on failure.

set -uo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
check_script="${script_dir}/../configure-ux-testing.sh"

fail() { echo "FAIL: $1" >&2; exit 1; }
pass() { echo "PASS: $1"; }

if ! command -v jq >/dev/null 2>&1; then
  echo "SKIP: jq not installed; cannot run configure-ux-testing tests"
  exit 0
fi

[ -f "$check_script" ] || fail "configure-ux-testing.sh not found at $check_script"

# -----------------------------------------------------------------------------
# Case 1: configured project → playwright detected, e2e dir present, MCP present
# -----------------------------------------------------------------------------
full="$(mktemp -d)"
trap 'rm -rf "$full"' EXIT
mkdir -p "${full}/tests/e2e/__snapshots__" "${full}/.github/workflows"
cat > "${full}/package.json" <<'JSON'
{
  "devDependencies": {
    "@playwright/test": "^1.40.0",
    "@axe-core/playwright": "^4.8.0"
  }
}
JSON
printf 'export default {};\n' > "${full}/playwright.config.ts"
printf 'name: e2e\n' > "${full}/.github/workflows/e2e.yml"
cat > "${full}/.mcp.json" <<'JSON'
{ "mcpServers": { "playwright": { "command": "bunx", "args": ["-y", "@playwright/mcp@latest"] } } }
JSON

out1="$(MCP_CONFIG_PATH="${full}/.mcp.json" bash "$check_script" --home-dir "$HOME" --project-dir "$full")"
echo "$out1" | grep -q "^PLAYWRIGHT_CONFIG=true$" || fail "expected PLAYWRIGHT_CONFIG=true:\n$out1"
echo "$out1" | grep -q "^PLAYWRIGHT_DEP=true$" || fail "expected PLAYWRIGHT_DEP=true:\n$out1"
echo "$out1" | grep -q "^AXE_CORE_DEP=true$" || fail "expected AXE_CORE_DEP=true:\n$out1"
echo "$out1" | grep -q "^E2E_DIR=true$" || fail "expected E2E_DIR=true:\n$out1"
echo "$out1" | grep -q "^VISUAL_SNAPSHOTS=true$" || fail "expected VISUAL_SNAPSHOTS=true:\n$out1"
echo "$out1" | grep -q "^E2E_WORKFLOW=true$" || fail "expected E2E_WORKFLOW=true:\n$out1"
echo "$out1" | grep -q "^PLAYWRIGHT_MCP=true$" || fail "expected PLAYWRIGHT_MCP=true:\n$out1"
echo "$out1" | grep -q "^PLAYWRIGHT_DETECTED=true$" || fail "expected PLAYWRIGHT_DETECTED=true:\n$out1"
echo "$out1" | grep -q "^STATUS=OK$" || fail "expected STATUS=OK for configured project:\n$out1"
pass "configured project detects playwright config, deps, e2e dir, snapshots, workflow, and MCP"
rm -rf "$full"

# -----------------------------------------------------------------------------
# Case 2: bare project → nothing detected, STATUS=WARN
# -----------------------------------------------------------------------------
bare="$(mktemp -d)"
out2="$(MCP_CONFIG_PATH="${bare}/.mcp.json" bash "$check_script" --home-dir "$HOME" --project-dir "$bare")"
echo "$out2" | grep -q "^PLAYWRIGHT_CONFIG=false$" || fail "expected PLAYWRIGHT_CONFIG=false:\n$out2"
echo "$out2" | grep -q "^PLAYWRIGHT_DEP=false$" || fail "expected PLAYWRIGHT_DEP=false:\n$out2"
echo "$out2" | grep -q "^E2E_DIR=false$" || fail "expected E2E_DIR=false:\n$out2"
echo "$out2" | grep -q "^PLAYWRIGHT_MCP=false$" || fail "expected PLAYWRIGHT_MCP=false:\n$out2"
echo "$out2" | grep -q "^PLAYWRIGHT_DETECTED=false$" || fail "expected PLAYWRIGHT_DETECTED=false:\n$out2"
echo "$out2" | grep -q "^STATUS=WARN$" || fail "expected STATUS=WARN for bare project:\n$out2"
pass "bare project detects no UX testing infrastructure and reports STATUS=WARN"
rm -rf "$bare"

echo "ALL TESTS PASSED"
