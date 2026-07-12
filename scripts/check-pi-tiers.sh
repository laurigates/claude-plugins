#!/usr/bin/env bash
# Drift guard for the pi (pi.dev) install-tier manifest (single source of
# truth: pi/tiers.yaml). Keeps the manifest in lockstep with the plugin
# marketplace and the on-disk skill tree so a tier assignment can't silently
# rot as plugins/skills come and go.
#
# Invariants:
#   1. Marketplace <-> manifest agree: every plugin in
#      .claude-plugin/marketplace.json appears in pi/tiers.yaml exactly once
#      (TYPE=plugin_unclassified when missing from the manifest,
#      TYPE=plugin_duplicate when listed more than once), and every plugin in
#      the manifest is a real marketplace plugin (TYPE=plugin_not_in_marketplace).
#   2. Every name under any `skills:` cherry-pick list resolves to a real
#      <plugin>/skills/<name>/SKILL.md (TYPE=skill_ref_missing).
#
# Emits the structured KEY=VALUE / STATUS= convention
# (.claude/rules/structured-script-output.md).
#
# Usage: bash scripts/check-pi-tiers.sh [--strict] [--root <repo-root>]
# --strict exits 1 on any issue (default: exit 1 only on ERROR).

set -uo pipefail

root_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
strict=false

while [ $# -gt 0 ]; do
  case "$1" in
    --strict) strict=true; shift ;;
    --root) root_dir="$2"; shift 2 ;;
    *) shift ;;
  esac
done

manifest="${root_dir}/pi/tiers.yaml"
marketplace="${root_dir}/.claude-plugin/marketplace.json"

echo "=== PI TIERS DRIFT ==="

pt_issue_count=0
pt_status="OK"
pt_issues_list=""

add_issue() {
  pt_issues_list="${pt_issues_list}  - SEVERITY=$1 TYPE=$2 MSG=$3\n"
  pt_issue_count=$((pt_issue_count + 1))
  if [ "$1" = "ERROR" ]; then
    pt_status="ERROR"
  elif [ "$1" = "WARN" ] && [ "$pt_status" = "OK" ]; then
    pt_status="WARN"
  fi
}

finish() {
  echo "STATUS=${pt_status}"
  echo "ISSUE_COUNT=${pt_issue_count}"
  if [ -n "$pt_issues_list" ]; then
    echo "ISSUES:"
    echo -e "$pt_issues_list" | sed '/^$/d'
  fi
  echo "=== END PI TIERS DRIFT ==="
  if [ "$pt_status" = "ERROR" ]; then exit 1; fi
  if [ "$strict" = "true" ] && [ "$pt_issue_count" -gt 0 ]; then exit 1; fi
  exit 0
}

command -v jq >/dev/null 2>&1 || add_issue "ERROR" "missing_jq" "jq is required to parse marketplace.json but is not installed"
for req in "$manifest" "$marketplace"; do
  if [ ! -f "$req" ]; then
    add_issue "ERROR" "missing_input" "required file not found: ${req}"
  fi
done
[ "$pt_status" = "ERROR" ] && finish

# ---------------------------------------------------------------------------
# Parse the manifest: emit one PLUGIN=<name> per plugin key and one
# SKILL=<plugin> <skill> per cherry-picked skill (tracking the current plugin).
# Plugin keys are 2-space-indented `<name>-plugin:` (block or flow form);
# skill items are 6-space-indented `- <name>` under a `skills:` list.
# ---------------------------------------------------------------------------
manifest_records="$(awk '
  /^  [a-z][a-z0-9-]*-plugin:/ {
    line=$0
    sub(/^  /, "", line)
    sub(/:.*/, "", line)
    plugin=line
    print "PLUGIN=" plugin
    next
  }
  /^      - [a-z][a-z0-9-]+[[:space:]]*$/ {
    skill=$2
    print "SKILL=" plugin " " skill
    next
  }
' "$manifest")"

# Manifest plugin set + duplicate detection.
declare -A manifest_plugin_count=()
while IFS= read -r line; do
  case "$line" in
    PLUGIN=*)
      p="${line#PLUGIN=}"
      manifest_plugin_count["$p"]=$(( ${manifest_plugin_count["$p"]:-0} + 1 ))
      ;;
  esac
done <<< "$manifest_records"

manifest_plugin_total=${#manifest_plugin_count[@]}

# Marketplace plugin set.
declare -A mkt_set=()
mkt_count=0
while IFS= read -r p; do
  [ -n "$p" ] || continue
  mkt_set["$p"]=1
  mkt_count=$((mkt_count + 1))
done < <(jq -r '.plugins[].name' "$marketplace" | sort)

# Check 1a: every marketplace plugin classified exactly once.
for p in "${!mkt_set[@]}"; do
  n=${manifest_plugin_count["$p"]:-0}
  if [ "$n" -eq 0 ]; then
    add_issue "ERROR" "plugin_unclassified" "$p is in marketplace.json but not classified in pi/tiers.yaml"
  elif [ "$n" -gt 1 ]; then
    add_issue "ERROR" "plugin_duplicate" "$p appears $n times in pi/tiers.yaml (expected exactly once)"
  fi
done

# Check 1b: every manifest plugin is a real marketplace plugin.
for p in "${!manifest_plugin_count[@]}"; do
  if [ -z "${mkt_set[$p]:-}" ]; then
    add_issue "ERROR" "plugin_not_in_marketplace" "$p is classified in pi/tiers.yaml but not published in marketplace.json"
  fi
done

# Check 2: every cherry-picked skill ref resolves to a real SKILL.md.
skill_ref_total=0
while IFS= read -r line; do
  case "$line" in
    SKILL=*)
      rest="${line#SKILL=}"
      plugin="${rest%% *}"
      skill="${rest#* }"
      skill_ref_total=$((skill_ref_total + 1))
      if [ ! -f "${root_dir}/${plugin}/skills/${skill}/SKILL.md" ]; then
        add_issue "ERROR" "skill_ref_missing" "${plugin}/skills/${skill}/SKILL.md referenced in pi/tiers.yaml does not exist"
      fi
      ;;
  esac
done <<< "$manifest_records"

echo "MARKETPLACE_PLUGINS=${mkt_count}"
echo "MANIFEST_PLUGINS=${manifest_plugin_total}"
echo "SKILL_REFS=${skill_ref_total}"

finish
