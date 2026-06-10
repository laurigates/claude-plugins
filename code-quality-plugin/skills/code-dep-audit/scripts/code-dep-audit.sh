#!/usr/bin/env bash
# Code Dependency Audit
# Detects the package ecosystem, runs the matching audit tool, parses its JSON
# into severity / behind / license-issue counts, and emits a structured rollup.
#
# Deterministic procedure extracted from code-dep-audit/SKILL.md (issue #1556).
# The agent still owns the generative report and the --fix path; this script
# only gathers and counts the audit data.
#
# Usage: bash code-dep-audit.sh --home-dir <path> --project-dir <path> [--verbose]
#
# Test/offline seam: the audit tools and any network call sit behind an
# injectable fixture. Set CODE_DEP_AUDIT_FIXTURE=<file> to feed canned audit
# JSON (in this script's normalized shape) instead of invoking a real tool, so
# the regression test runs offline with no audit tool installed.

set -uo pipefail

home_dir=""
project_dir=""
verbose_mode=false

while [ $# -gt 0 ]; do
  case "$1" in
    --home-dir) home_dir="$2"; shift 2 ;;
    --project-dir) project_dir="$2"; shift 2 ;;
    --verbose) verbose_mode=true; shift ;;
    *) shift ;;
  esac
done

: "${home_dir:=$HOME}"
: "${project_dir:=$(pwd)}"

echo "=== CODE DEP AUDIT ==="

audit_issue_count=0
audit_status="OK"
issues_list=""

# jq is required to parse the audit JSON.
if ! command -v jq >/dev/null 2>&1; then
  echo "JQ_AVAILABLE=false"
  echo "STATUS=ERROR"
  echo "ISSUE_COUNT=1"
  echo "ISSUES:"
  echo "  - SEVERITY=ERROR TYPE=missing_tool MSG=jq is required but not installed"
  echo "=== END CODE DEP AUDIT ==="
  exit 1
fi
echo "JQ_AVAILABLE=true"

# --- Ecosystem detection -----------------------------------------------------
# A single ecosystem is detected from the manifest/lockfile present at the
# project root. The detection order is fixed and deterministic.
detected_ecosystem="none"
audit_tool="none"

if [ -f "${project_dir}/package.json" ] \
  || [ -f "${project_dir}/package-lock.json" ] \
  || [ -f "${project_dir}/yarn.lock" ] \
  || [ -f "${project_dir}/bun.lockb" ]; then
  detected_ecosystem="js"
  audit_tool="npm audit --json"
elif [ -f "${project_dir}/pyproject.toml" ] \
  || [ -f "${project_dir}/requirements.txt" ]; then
  detected_ecosystem="python"
  audit_tool="pip-audit --format json"
elif [ -f "${project_dir}/Cargo.toml" ] || [ -f "${project_dir}/Cargo.lock" ]; then
  detected_ecosystem="rust"
  audit_tool="cargo audit --json"
elif [ -f "${project_dir}/go.mod" ] || [ -f "${project_dir}/go.sum" ]; then
  detected_ecosystem="go"
  audit_tool="govulncheck ./..."
fi

echo "ECOSYSTEM=${detected_ecosystem}"
echo "AUDIT_TOOL=${audit_tool}"

if [ "$detected_ecosystem" = "none" ]; then
  echo "STATUS=OK"
  echo "ISSUE_COUNT=0"
  echo "=== END CODE DEP AUDIT ==="
  exit 0
fi

# --- Gather audit JSON (behind the fixture seam) -----------------------------
# Normalized JSON shape this script consumes:
#   { "severity": {"critical":N,"high":N,"medium":N,"low":N},
#     "outdated": N,
#     "licenses": [ {"package":"x","license":"GPL-3.0"}, ... ] }
# The fixture provides this shape directly; a real-tool path would normalize
# each ecosystem's native output into it. Out of scope for this extraction:
# wiring every real tool's normalization — the seam keeps the parse/rollup
# logic deterministic and offline-testable, which is the value.
audit_json=""
fixture="${CODE_DEP_AUDIT_FIXTURE:-}"

if [ -n "$fixture" ]; then
  if [ ! -f "$fixture" ]; then
    issues_list="${issues_list}  - SEVERITY=ERROR TYPE=fixture_missing FILE=${fixture} MSG=fixture file not found\n"
    audit_issue_count=$((audit_issue_count + 1))
    audit_status="ERROR"
  else
    audit_json="$(cat "$fixture")"
  fi
  echo "AUDIT_SOURCE=fixture"
else
  # No real-tool invocation is wired in this extraction step; the agent runs the
  # tool per SKILL.md when no fixture is supplied. Report tool availability so
  # the agent knows whether the ecosystem's audit tool is installed.
  tool_bin="${audit_tool%% *}"
  if command -v "$tool_bin" >/dev/null 2>&1; then
    echo "AUDIT_TOOL_AVAILABLE=true"
  else
    echo "AUDIT_TOOL_AVAILABLE=false"
    issues_list="${issues_list}  - SEVERITY=WARN TYPE=tool_missing TOOL=${tool_bin} MSG=audit tool not installed; run /configure:security to set it up\n"
    audit_issue_count=$((audit_issue_count + 1))
    [ "$audit_status" = "OK" ] && audit_status="WARN"
  fi
  echo "AUDIT_SOURCE=live"
fi

# --- Parse severity / behind / license counts --------------------------------
crit=0; high=0; med=0; low=0; behind=0

if [ -n "$audit_json" ]; then
  # Validate JSON before parsing; a malformed fixture is an ERROR.
  if ! echo "$audit_json" | jq empty >/dev/null 2>&1; then
    echo "AUDIT_JSON_VALID=false"
    issues_list="${issues_list}  - SEVERITY=ERROR TYPE=invalid_json MSG=audit JSON failed to parse\n"
    audit_issue_count=$((audit_issue_count + 1))
    audit_status="ERROR"
  else
    echo "AUDIT_JSON_VALID=true"
    crit=$(echo "$audit_json" | jq -r '.severity.critical // 0')
    high=$(echo "$audit_json" | jq -r '.severity.high // 0')
    med=$(echo "$audit_json" | jq -r '.severity.medium // 0')
    low=$(echo "$audit_json" | jq -r '.severity.low // 0')
    behind=$(echo "$audit_json" | jq -r '.outdated // 0')

    # Severity rollup: any critical/high → ERROR; medium/low or outdated → WARN.
    vuln_total=$((crit + high + med + low))
    if [ "$crit" -gt 0 ] || [ "$high" -gt 0 ]; then
      issues_list="${issues_list}  - SEVERITY=ERROR TYPE=vulnerability MSG=${crit} critical and ${high} high severity vulnerabilities\n"
      audit_issue_count=$((audit_issue_count + crit + high))
      audit_status="ERROR"
    fi
    if [ "$med" -gt 0 ] || [ "$low" -gt 0 ]; then
      issues_list="${issues_list}  - SEVERITY=WARN TYPE=vulnerability MSG=${med} medium and ${low} low severity vulnerabilities\n"
      audit_issue_count=$((audit_issue_count + med + low))
      [ "$audit_status" = "OK" ] && audit_status="WARN"
    fi
    if [ "$behind" -gt 0 ]; then
      issues_list="${issues_list}  - SEVERITY=WARN TYPE=outdated MSG=${behind} packages behind latest\n"
      audit_issue_count=$((audit_issue_count + 1))
      [ "$audit_status" = "OK" ] && audit_status="WARN"
    fi

    # --- License denylist: static problematic-license check (GPL/AGPL) -------
    # Flags copyleft licenses that are problematic in proprietary projects.
    license_flagged=$(echo "$audit_json" | jq -r '
      [.licenses // [] | .[]
        | select(.license != null)
        | select(.license | ascii_upcase | test("AGPL|GPL"))]
      | length')
    if [ "$license_flagged" -gt 0 ]; then
      flagged_pkgs=$(echo "$audit_json" | jq -r '
        [.licenses // [] | .[]
          | select(.license != null)
          | select(.license | ascii_upcase | test("AGPL|GPL"))
          | "\(.package)=\(.license)"]
        | join(",")')
      issues_list="${issues_list}  - SEVERITY=WARN TYPE=license MSG=${license_flagged} problematic licenses (${flagged_pkgs})\n"
      audit_issue_count=$((audit_issue_count + license_flagged))
      [ "$audit_status" = "OK" ] && audit_status="WARN"
    fi

    echo "VULN_CRITICAL=${crit}"
    echo "VULN_HIGH=${high}"
    echo "VULN_MEDIUM=${med}"
    echo "VULN_LOW=${low}"
    echo "VULN_TOTAL=${vuln_total}"
    echo "OUTDATED_COUNT=${behind}"
    echo "LICENSE_ISSUES=${license_flagged}"
  fi
fi

if [ "$verbose_mode" = true ]; then
  echo "HOME_DIR=${home_dir}"
  echo "PROJECT_DIR=${project_dir}"
fi

echo "STATUS=${audit_status}"
echo "ISSUE_COUNT=${audit_issue_count}"
if [ -n "$issues_list" ]; then
  echo "ISSUES:"
  echo -e "$issues_list" | sed '/^$/d'
fi
echo "=== END CODE DEP AUDIT ==="

[ "$audit_status" = "ERROR" ] && exit 1
exit 0
