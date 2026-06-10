#!/usr/bin/env bash
# Detect UX-testing posture for a project.
# Scans --project-dir for Playwright / axe-core signals (package.json deps +
# config globs), e2e/__snapshots__/e2e-workflow presence, and the playwright
# MCP-server entry in .mcp.json. Generative config-writing stays with the model.
# Usage: bash configure-ux-testing.sh --home-dir <path> --project-dir <path>
#
# Offline seam: the MCP lookup reads ${MCP_CONFIG_PATH:-<project>/.mcp.json}.
# Tests point MCP_CONFIG_PATH at a planted fixture so the check stays offline.

set -uo pipefail

home_dir=""
project_dir=""

while [ $# -gt 0 ]; do
  case "$1" in
    --home-dir) home_dir="$2"; shift 2 ;;
    --project-dir) project_dir="$2"; shift 2 ;;
    *) shift ;;
  esac
done

: "${home_dir:=$HOME}"
: "${project_dir:=$(pwd)}"

echo "=== CONFIGURE UX TESTING ==="

ux_issue_count=0
ux_status="OK"
ux_issues_list=""

add_issue() {
  ux_issues_list="${ux_issues_list}  - SEVERITY=$1 TYPE=$2 MSG=$3\n"
  ux_issue_count=$((ux_issue_count + 1))
  if [ "$1" = "ERROR" ]; then
    ux_status="ERROR"
  elif [ "$1" = "WARN" ] && [ "$ux_status" = "OK" ]; then
    ux_status="WARN"
  fi
}

exists_file() { [ -f "$1" ] && echo "true" || echo "false"; }

if ! command -v jq >/dev/null 2>&1; then
  echo "JQ_AVAILABLE=false"
  echo "STATUS=ERROR"
  echo "ISSUE_COUNT=1"
  echo "ISSUES:"
  echo "  - SEVERITY=ERROR TYPE=missing_tool MSG=jq is required but not installed"
  echo "=== END CONFIGURE UX TESTING ==="
  exit 1
fi
echo "JQ_AVAILABLE=true"

# -----------------------------------------------------------------------------
# Package manager
# -----------------------------------------------------------------------------
pkg_json=$(exists_file "${project_dir}/package.json")
echo "PACKAGE_JSON=${pkg_json}"
[ -f "${project_dir}/bun.lockb" ] && echo "BUN_LOCKFILE=true" || echo "BUN_LOCKFILE=false"

# -----------------------------------------------------------------------------
# Playwright config glob
# -----------------------------------------------------------------------------
playwright_config=false
for f in "${project_dir}"/playwright.config.*; do
  [ -f "$f" ] && { playwright_config=true; break; }
done
echo "PLAYWRIGHT_CONFIG=${playwright_config}"

# -----------------------------------------------------------------------------
# Playwright / axe-core deps in package.json (jq lookup, tolerant of missing)
# -----------------------------------------------------------------------------
dep_present() {
  # $1 = dependency name; checks dependencies + devDependencies
  local dep="$1"
  if [ "$pkg_json" != "true" ]; then
    echo "false"
    return
  fi
  if jq -e --arg d "$dep" \
      '((.dependencies // {}) + (.devDependencies // {})) | has($d)' \
      "${project_dir}/package.json" >/dev/null 2>&1; then
    echo "true"
  else
    echo "false"
  fi
}

playwright_dep=$(dep_present "@playwright/test")
axe_dep=$(dep_present "@axe-core/playwright")
echo "PLAYWRIGHT_DEP=${playwright_dep}"
echo "AXE_CORE_DEP=${axe_dep}"

# -----------------------------------------------------------------------------
# e2e directory + __snapshots__ + e2e workflow detection
# -----------------------------------------------------------------------------
e2e_dir=false
for d in "${project_dir}/e2e" "${project_dir}/tests/e2e"; do
  [ -d "$d" ] && { e2e_dir=true; break; }
done
echo "E2E_DIR=${e2e_dir}"

snapshots=false
# __snapshots__ can live a few levels deep under tests/
while IFS= read -r snap; do
  [ -n "$snap" ] && { snapshots=true; break; }
done < <(find "$project_dir" -maxdepth 5 -type d -name '__snapshots__' 2>/dev/null)
echo "VISUAL_SNAPSHOTS=${snapshots}"

e2e_workflow=false
workflows_dir="${project_dir}/.github/workflows"
if [ -d "$workflows_dir" ]; then
  for wf in "$workflows_dir"/e2e*.yml "$workflows_dir"/e2e*.yaml; do
    [ -f "$wf" ] && { e2e_workflow=true; break; }
  done
fi
echo "E2E_WORKFLOW=${e2e_workflow}"

# -----------------------------------------------------------------------------
# Playwright MCP-server lookup (offline seam via MCP_CONFIG_PATH)
# -----------------------------------------------------------------------------
mcp_config_path="${MCP_CONFIG_PATH:-${project_dir}/.mcp.json}"
playwright_mcp=false
if [ -f "$mcp_config_path" ]; then
  if jq -e '.mcpServers.playwright // empty' "$mcp_config_path" >/dev/null 2>&1; then
    playwright_mcp=true
  fi
fi
echo "PLAYWRIGHT_MCP=${playwright_mcp}"

# -----------------------------------------------------------------------------
# Presence-matrix rollup
# -----------------------------------------------------------------------------
ux_present=0
[ "$playwright_config" = "true" ] && ux_present=$((ux_present + 1))
[ "$playwright_dep" = "true" ] && ux_present=$((ux_present + 1))
[ "$axe_dep" = "true" ] && ux_present=$((ux_present + 1))
[ "$e2e_dir" = "true" ] && ux_present=$((ux_present + 1))
echo "UX_SIGNALS_PRESENT=${ux_present}"

playwright_detected=false
if [ "$playwright_config" = "true" ] || [ "$playwright_dep" = "true" ]; then
  playwright_detected=true
fi
echo "PLAYWRIGHT_DETECTED=${playwright_detected}"

[ "$playwright_detected" = "false" ] && add_issue "WARN" "no_playwright" "no Playwright config or @playwright/test dependency detected"
[ "$axe_dep" = "false" ] && add_issue "WARN" "no_a11y" "no @axe-core/playwright dependency — accessibility testing not configured"

echo "STATUS=${ux_status}"
echo "ISSUE_COUNT=${ux_issue_count}"
if [ -n "$ux_issues_list" ]; then
  echo "ISSUES:"
  echo -e "$ux_issues_list" | sed '/^$/d'
fi
echo "=== END CONFIGURE UX TESTING ==="

[ "$ux_status" = "ERROR" ] && exit 1
exit 0
