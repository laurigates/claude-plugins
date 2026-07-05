#!/usr/bin/env bash
# List configure-plugin components from the components.yaml manifest and
# cross-check each entry against the skill directories on disk.
# The manifest is the single source of truth for the component roster;
# this script is how the orchestrator skills (configure-all, configure-select,
# configure-status) consume it without re-deriving the list in prose.
# Detection only — never mutates anything.
# Usage: bash list-components.sh [--manifest <path>] [--skills-dir <path>] [--domain <key>]

set -uo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
manifest="${script_dir}/../components.yaml"
skills_dir="${script_dir}/../.."
filter_domain=""

while [ $# -gt 0 ]; do
  case "$1" in
    --manifest) manifest="$2"; shift 2 ;;
    --skills-dir) skills_dir="$2"; shift 2 ;;
    --domain) filter_domain="$2"; shift 2 ;;
    *) shift ;;
  esac
done

echo "=== CONFIGURE COMPONENTS ==="

lc_issue_count=0
lc_status="OK"
lc_issues_list=""

add_issue() {
  lc_issues_list="${lc_issues_list}  - SEVERITY=$1 TYPE=$2 MSG=$3\n"
  lc_issue_count=$((lc_issue_count + 1))
  if [ "$1" = "ERROR" ]; then
    lc_status="ERROR"
  elif [ "$1" = "WARN" ] && [ "$lc_status" = "OK" ]; then
    lc_status="WARN"
  fi
}

if [ ! -f "$manifest" ]; then
  echo "MANIFEST=missing"
  echo "STATUS=ERROR"
  echo "ISSUE_COUNT=1"
  echo "ISSUES:"
  echo "  - SEVERITY=ERROR TYPE=manifest_missing MSG=components.yaml not found at ${manifest}"
  echo "=== END CONFIGURE COMPONENTS ==="
  exit 1
fi
echo "MANIFEST=${manifest}"

# ---------------------------------------------------------------------------
# Parse the flat manifest with awk (no yq dependency).
# Emits: component <name> <domain> <has_script> <types>
#        domain <key> <title...>
#        orchestrator/advisory/reference <name>
# ---------------------------------------------------------------------------
parsed="$(awk '
  /^domains:/        { section="domains"; next }
  /^components:/     { section="components"; next }
  /^orchestrators:/  { section="orchestrators"; next }
  /^advisory:/       { section="advisory"; next }
  /^reference_skills:/ { section="reference"; next }
  /^[a-z_]+:/        { section=""; next }
  section=="domains" && /^  [a-z-]+:/ {
    key=$1; sub(/:$/, "", key)
    title=$0; sub(/^  [a-z-]+:[ ]*/, "", title)
    print "domain", key, title
    next
  }
  section=="components" && /^  - name:/       { cname=$3; cdomain=""; cscript="false"; ctypes="all"; next }
  section=="components" && /^    domain:/     { cdomain=$2; next }
  section=="components" && /^    has_script:/ { cscript=$2; next }
  section=="components" && /^    types:/      {
    ctypes=$2
    print "component", cname, cdomain, cscript, ctypes
    next
  }
  (section=="orchestrators" || section=="advisory" || section=="reference") && /^  - / {
    print (section=="reference" ? "reference" : section=="advisory" ? "advisory" : "orchestrator"), $2
    next
  }
' "$manifest")"

component_count=0
domain_count=0

# Domains
while read -r kind key title; do
  [ "$kind" = "domain" ] || continue
  echo "DOMAIN=${key} TITLE=${title}"
  domain_count=$((domain_count + 1))
done <<< "$parsed"

# Components (manifest → disk check)
while read -r kind cname cdomain cscript ctypes; do
  [ "$kind" = "component" ] || continue
  if [ -n "$filter_domain" ] && [ "$cdomain" != "$filter_domain" ]; then
    continue
  fi
  if [ ! -f "${skills_dir}/${cname}/SKILL.md" ]; then
    add_issue "ERROR" "missing_on_disk" "manifest lists ${cname} but skills/${cname}/SKILL.md does not exist"
    continue
  fi
  if [ "$cscript" = "true" ] && [ ! -f "${skills_dir}/${cname}/scripts/${cname}.sh" ]; then
    add_issue "WARN" "script_missing" "${cname} has has_script=true but scripts/${cname}.sh is absent"
    cscript="false"
  fi
  echo "COMPONENT=${cname} DOMAIN=${cdomain} HAS_SCRIPT=${cscript} TYPES=${ctypes}"
  component_count=$((component_count + 1))
done <<< "$parsed"

# Non-component buckets (existence check only)
while read -r kind sname _; do
  case "$kind" in
    orchestrator|advisory|reference) ;;
    *) continue ;;
  esac
  if [ ! -f "${skills_dir}/${sname}/SKILL.md" ]; then
    add_issue "ERROR" "missing_on_disk" "manifest lists ${sname} (${kind}) but skills/${sname}/SKILL.md does not exist"
  fi
done <<< "$parsed"

# Disk → manifest check: every skill dir must be in exactly one bucket.
if [ -z "$filter_domain" ]; then
  all_manifest_names="$(printf '%s\n' "$parsed" | awk '$1=="component"||$1=="orchestrator"||$1=="advisory"||$1=="reference" {print $2}')"
  dupes="$(printf '%s\n' "$all_manifest_names" | sort | uniq -d)"
  if [ -n "$dupes" ]; then
    while read -r d; do
      [ -n "$d" ] && add_issue "ERROR" "duplicate_entry" "${d} appears in more than one manifest bucket"
    done <<< "$dupes"
  fi
  for skill_path in "${skills_dir}"/*/SKILL.md; do
    [ -f "$skill_path" ] || continue
    sdir="$(basename "$(dirname "$skill_path")")"
    if ! printf '%s\n' "$all_manifest_names" | grep -qx "$sdir"; then
      add_issue "ERROR" "unlisted_skill" "skills/${sdir} exists on disk but is not in components.yaml"
    fi
  done
fi

echo "COMPONENT_COUNT=${component_count}"
echo "DOMAIN_COUNT=${domain_count}"
echo "STATUS=${lc_status}"
echo "ISSUE_COUNT=${lc_issue_count}"
if [ -n "$lc_issues_list" ]; then
  echo "ISSUES:"
  echo -e "$lc_issues_list" | sed '/^$/d'
fi
echo "=== END CONFIGURE COMPONENTS ==="

[ "$lc_status" = "ERROR" ] && exit 1
exit 0
