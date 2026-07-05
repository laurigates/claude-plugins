#!/usr/bin/env bash
# shellcheck disable=SC2016   # file-level: single-quoted regexes deliberately contain literal backticks
# Drift guard for configure-plugin's component taxonomy (single source of
# truth: configure-plugin/skills/configure-all/components.yaml).
#
# Invariants (the three-way drift this catches shipped as: /configure:all
# hard-coding a 19-entry subset of 37 components, README and docs/flow.md
# disagreeing on domains, and configure-readme missing from the README):
#   1. Manifest ↔ disk agree (delegated to list-components.sh): every manifest
#      entry exists as a skill, every skill dir is in exactly one bucket.
#   2. Every /configure:<x> literal in configure-all/SKILL.md resolves to a
#      manifest entry — blocks reintroducing a hand-maintained component list.
#   3. docs/flow.md's "Domain → Skill mapping" table names every manifest
#      component, and every skill it names is in the manifest.
#   4. README.md mentions every skill in the manifest.
#
# Usage: bash scripts/check-configure-components.sh [--strict] [--root <repo-root>]
# --strict exits 1 on any issue (default behavior is identical; flag kept for
# symmetry with sibling guards).

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

plugin_dir="${root_dir}/configure-plugin"
skills_dir="${plugin_dir}/skills"
manifest="${skills_dir}/configure-all/components.yaml"
lister="${skills_dir}/configure-all/scripts/list-components.sh"
all_skill="${skills_dir}/configure-all/SKILL.md"
flow_md="${plugin_dir}/docs/flow.md"
readme="${plugin_dir}/README.md"

echo "=== CONFIGURE COMPONENTS DRIFT ==="

cc_issue_count=0
cc_status="OK"
cc_issues_list=""

add_issue() {
  cc_issues_list="${cc_issues_list}  - SEVERITY=$1 TYPE=$2 MSG=$3\n"
  cc_issue_count=$((cc_issue_count + 1))
  if [ "$1" = "ERROR" ]; then
    cc_status="ERROR"
  elif [ "$1" = "WARN" ] && [ "$cc_status" = "OK" ]; then
    cc_status="WARN"
  fi
}

finish() {
  echo "STATUS=${cc_status}"
  echo "ISSUE_COUNT=${cc_issue_count}"
  if [ -n "$cc_issues_list" ]; then
    echo "ISSUES:"
    echo -e "$cc_issues_list" | sed '/^$/d'
  fi
  echo "=== END CONFIGURE COMPONENTS DRIFT ==="
  if [ "$cc_status" = "ERROR" ]; then exit 1; fi
  if [ "$strict" = "true" ] && [ "$cc_issue_count" -gt 0 ]; then exit 1; fi
  exit 0
}

for req in "$manifest" "$lister" "$all_skill" "$flow_md" "$readme"; do
  if [ ! -f "$req" ]; then
    add_issue "ERROR" "missing_input" "required file not found: ${req}"
  fi
done
[ "$cc_status" = "ERROR" ] && finish

# ---------------------------------------------------------------------------
# Check 1: manifest ↔ disk (delegated)
# ---------------------------------------------------------------------------
lister_out="$(bash "$lister" --manifest "$manifest" --skills-dir "$skills_dir")" || true
lister_status="$(printf '%s\n' "$lister_out" | grep -m1 '^STATUS=' | cut -d= -f2)"
echo "MANIFEST_DISK_STATUS=${lister_status:-ERROR}"
if [ "${lister_status:-ERROR}" != "OK" ]; then
  while IFS= read -r line; do
    case "$line" in
      "  - SEVERITY="*) add_issue "ERROR" "manifest_disk_drift" "${line#  - }" ;;
    esac
  done <<< "$lister_out"
fi

components="$(printf '%s\n' "$lister_out" | awk -F'[= ]' '/^COMPONENT=/ {print $2}')"
# Full manifest name set (all buckets), for flow.md / README checks.
manifest_names="$(awk '
  /^components:/       { section="components"; next }
  /^orchestrators:/    { section="list"; next }
  /^advisory:/         { section="list"; next }
  /^reference_skills:/ { section="list"; next }
  /^[a-z_]+:/          { section=""; next }
  section=="components" && /^  - name:/ { print $3; next }
  section=="list" && /^  - /            { print $2; next }
' "$manifest")"

# ---------------------------------------------------------------------------
# Check 2: every /configure:<x> literal in configure-all/SKILL.md is a
# manifest entry (component or orchestrator). Blocks a hand-maintained list
# from drifting off the manifest again.
# ---------------------------------------------------------------------------
skill_refs="$(grep -ohE '/configure:[a-z][a-z0-9-]*' "$all_skill" | sed 's|/configure:||' | sort -u)"
unresolved=0
while read -r ref; do
  [ -n "$ref" ] || continue
  # /configure:X maps to skill dir configure-X, except dirs that already
  # carry their full name (config-sync).
  if printf '%s\n' "$manifest_names" | grep -qx "configure-${ref}"; then continue; fi
  if printf '%s\n' "$manifest_names" | grep -qx "$ref"; then continue; fi
  if printf '%s\n' "$manifest_names" | grep -qx "config-${ref}"; then continue; fi
  add_issue "ERROR" "skill_ref_unresolved" "configure-all/SKILL.md references /configure:${ref} which is not in components.yaml"
  unresolved=$((unresolved + 1))
done <<< "$skill_refs"
echo "SKILL_REFS_UNRESOLVED=${unresolved}"

# ---------------------------------------------------------------------------
# Check 3: docs/flow.md mapping table ↔ manifest
# ---------------------------------------------------------------------------
flow_names="$(grep -oE '`[a-z][a-z0-9-]*`' "$flow_md" | tr -d "\`" | sort -u)"
flow_missing=0
while read -r comp; do
  [ -n "$comp" ] || continue
  if ! printf '%s\n' "$flow_names" | grep -qx "$comp"; then
    add_issue "ERROR" "flow_missing_component" "docs/flow.md mapping table does not name ${comp}"
    flow_missing=$((flow_missing + 1))
  fi
done <<< "$components"
flow_dangling=0
while read -r fname; do
  [ -n "$fname" ] || continue
  # Only judge names that look like skills of this plugin.
  case "$fname" in
    configure-*|config-sync|*-standards|ci-workflows|claude-security-settings|openfeature|go-feature-flag|multi-repo-discipline) ;;
    *) continue ;;
  esac
  if ! printf '%s\n' "$manifest_names" | grep -qx "$fname"; then
    add_issue "ERROR" "flow_dangling_skill" "docs/flow.md names ${fname} which is not in components.yaml"
    flow_dangling=$((flow_dangling + 1))
  fi
done <<< "$flow_names"
echo "FLOW_MISSING=${flow_missing}"
echo "FLOW_DANGLING=${flow_dangling}"

# ---------------------------------------------------------------------------
# Check 4: README mentions every manifest skill
# ---------------------------------------------------------------------------
readme_missing=0
while read -r mname; do
  [ -n "$mname" ] || continue
  if ! grep -q "\`${mname}\`" "$readme"; then
    add_issue "ERROR" "readme_missing_skill" "README.md does not list ${mname}"
    readme_missing=$((readme_missing + 1))
  fi
done <<< "$manifest_names"
echo "README_MISSING=${readme_missing}"

finish
