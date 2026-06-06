#!/usr/bin/env bash
# Guard against drift between the repo's plugin marketplace and the set of
# plugins enabled in project settings (.claude/settings.json).
#
# The repo dogfoods its own plugins: every plugin published in
# .claude-plugin/marketplace.json should be enabled in the committed project
# settings so contributors load the full set. This script keeps the two in
# lockstep with three zero-false-positive checks:
#
#   1. MARKETPLACE REGISTERED — extraKnownMarketplaces contains the marketplace
#      name declared in marketplace.json, so the enabled keys resolve to a
#      source.
#   2. ALL ENABLED — every plugin in marketplace.json is enabled in
#      enabledPlugins as "<plugin>@<marketplace>" (value not false).
#   3. NO DANGLING — every enabledPlugins key for this marketplace maps to a
#      real plugin still listed in marketplace.json.
#
# Emits the structured KEY=value / STATUS= convention
# (.claude/rules/structured-script-output.md) so scheduled-audits can roll it
# up, and a markdown issue body for the audit workflow.
#
# Usage:
#   check-enabled-plugins-drift.sh [--project-dir <path>] [--issue-body] [--strict]
#
#   --project-dir   Repo root to audit (default: git toplevel, else cwd)
#   --issue-body    Emit a markdown issue body (empty when clean) instead of the
#                   structured section
#   --strict        Exit 1 when drift is found (default: always exit 0)
set -uo pipefail

proj_dir=""
emit_issue_body=false
strict=false

while [ $# -gt 0 ]; do
  case "$1" in
    --project-dir) proj_dir="$2"; shift 2 ;;
    --issue-body) emit_issue_body=true; shift ;;
    --strict) strict=true; shift ;;
    *) shift ;;
  esac
done

if [ -z "$proj_dir" ]; then
  proj_dir="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
fi

marketplace="$proj_dir/.claude-plugin/marketplace.json"
settings="$proj_dir/.claude/settings.json"

issue_count=0
declare -a issues=()

add_issue() {
  # add_issue <severity> <type> <message>
  issues+=("  - SEVERITY=$1 TYPE=$2 MSG=$3")
  issue_count=$((issue_count + 1))
}

jq_available=true
command -v jq >/dev/null 2>&1 || jq_available=false

mkt_name=""
mkt_count=0
enabled_count=0
registered="false"

if [ "$jq_available" = false ]; then
  add_issue ERROR missing_jq "jq is required to audit plugin enablement but is not installed"
elif [ ! -f "$marketplace" ]; then
  add_issue ERROR missing_marketplace "marketplace.json not found at $marketplace"
elif [ ! -f "$settings" ]; then
  add_issue ERROR missing_settings ".claude/settings.json not found at $settings"
else
  mkt_name="$(jq -r '.name // empty' "$marketplace")"
  if [ -z "$mkt_name" ]; then
    add_issue ERROR marketplace_unnamed "marketplace.json has no top-level .name"
  else
    # Plugin names published by the marketplace.
    mapfile -t mkt_plugins < <(jq -r '.plugins[].name' "$marketplace" | sort)
    mkt_count=${#mkt_plugins[@]}

    # Enabled plugin keys for THIS marketplace (value not false), suffix stripped.
    mapfile -t enabled_plugins < <(
      jq -r --arg n "$mkt_name" '
        (.enabledPlugins // {})
        | to_entries[]
        | select(.value != false)
        | .key
        | select(endswith("@" + $n))
        | sub("@" + $n + "$"; "")
      ' "$settings" | sort
    )
    enabled_count=${#enabled_plugins[@]}

    # Check 1: marketplace registered as a source.
    if jq -e --arg n "$mkt_name" '(.extraKnownMarketplaces // {}) | has($n)' "$settings" >/dev/null; then
      registered="true"
    else
      add_issue ERROR marketplace_not_registered \
        "extraKnownMarketplaces is missing the '$mkt_name' source — enabled '@$mkt_name' plugins cannot resolve"
    fi

    # Build a lookup set of enabled plugins for membership tests.
    declare -A enabled_set=()
    for p in "${enabled_plugins[@]}"; do
      [ -n "$p" ] && enabled_set["$p"]=1
    done
    declare -A mkt_set=()
    for p in "${mkt_plugins[@]}"; do
      [ -n "$p" ] && mkt_set["$p"]=1
    done

    # Check 2: every marketplace plugin is enabled.
    for p in "${mkt_plugins[@]}"; do
      [ -n "$p" ] || continue
      if [ -z "${enabled_set[$p]:-}" ]; then
        add_issue ERROR plugin_not_enabled \
          "$p is published in marketplace.json but not enabled as '$p@$mkt_name' in .claude/settings.json"
      fi
    done

    # Check 3: every enabled plugin maps to a real marketplace plugin.
    for p in "${enabled_plugins[@]}"; do
      [ -n "$p" ] || continue
      if [ -z "${mkt_set[$p]:-}" ]; then
        add_issue ERROR enabled_plugin_dangling \
          "$p@$mkt_name is enabled in .claude/settings.json but no longer listed in marketplace.json"
      fi
    done
  fi
fi

# --- Status -------------------------------------------------------------------
overall_status="OK"
exit_severity=0
for line in "${issues[@]}"; do
  case "$line" in
    *SEVERITY=ERROR*) overall_status="ERROR"; exit_severity=1 ;;
  esac
done
if [ "$overall_status" = "OK" ] && [ "$issue_count" -gt 0 ]; then
  overall_status="WARN"
fi

# --- Output -------------------------------------------------------------------
if [ "$emit_issue_body" = true ]; then
  if [ "$issue_count" -gt 0 ]; then
    echo "## Plugin enablement drift"
    echo ""
    echo "\`scripts/check-enabled-plugins-drift.sh\` found $issue_count issue(s) between"
    echo "\`.claude-plugin/marketplace.json\` and \`.claude/settings.json\`."
    echo ""
    echo "| Severity | Type | Detail |"
    echo "|----------|------|--------|"
    for line in "${issues[@]}"; do
      sev="$(printf '%s' "$line" | sed -n 's/.*SEVERITY=\([A-Z]*\).*/\1/p')"
      typ="$(printf '%s' "$line" | sed -n 's/.*TYPE=\([a-z_]*\).*/\1/p')"
      msg="$(printf '%s' "$line" | sed -n 's/.*MSG=//p')"
      echo "| $sev | \`$typ\` | $msg |"
    done
    echo ""
    echo "Regenerate the enabled set from the marketplace:"
    echo '```bash'
    echo "ep=\$(jq -c '[.plugins[].name | . + \"@$mkt_name\"] | map({(.):true}) | add' .claude-plugin/marketplace.json)"
    echo "jq --argjson ep \"\$ep\" '.enabledPlugins = \$ep' .claude/settings.json > tmp && mv tmp .claude/settings.json"
    echo '```'
  fi
else
  echo "=== PLUGIN ENABLEMENT DRIFT ==="
  echo "JQ_AVAILABLE=$jq_available"
  echo "MARKETPLACE_NAME=$mkt_name"
  echo "MARKETPLACE_REGISTERED=$registered"
  echo "MARKETPLACE_PLUGINS=$mkt_count"
  echo "ENABLED_PLUGINS=$enabled_count"
  echo "STATUS=$overall_status"
  echo "ISSUE_COUNT=$issue_count"
  if [ "$issue_count" -gt 0 ]; then
    echo "ISSUES:"
    printf '%s\n' "${issues[@]}"
  fi
  echo "=== END PLUGIN ENABLEMENT DRIFT ==="
fi

if [ "$strict" = true ]; then
  exit "$exit_severity"
fi
exit 0
