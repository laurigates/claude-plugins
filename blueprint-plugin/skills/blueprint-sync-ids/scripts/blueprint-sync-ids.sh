#!/usr/bin/env bash
# blueprint-sync-ids audit (read-only)
# Scans PRDs, ADRs, PRPs, and work-orders for frontmatter `id:` values,
# derives the expected ADR-NNNN / WO-NNN from each filename, flags
# MISMATCH/NEEDS_ID, and builds the reverse github_issues index from the
# manifest registry. This is the *audit* surface only — actual ID
# assignment and manifest mutation stay in the skill.
#
# Usage: bash blueprint-sync-ids.sh --project-dir <path> [--home-dir <path>]
#
# The doc-tree roots default to <project_dir>/docs/{prds,adrs,prps} and
# <project_dir>/docs/blueprint/work-orders. Tests plant a fixture tree and
# point --project-dir at it so the audit runs fully offline.

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

echo "=== BLUEPRINT SYNC-IDS ==="

audit_status="OK"
issue_count=0
issues_list=""

add_issue() {
  # $1 severity, $2 type, rest message-ish key/values
  issues_list="${issues_list}  - SEVERITY=$1 TYPE=$2 $3\n"
  issue_count=$((issue_count + 1))
}

if ! command -v jq >/dev/null 2>&1; then
  echo "JQ_AVAILABLE=false"
  echo "STATUS=ERROR"
  echo "ISSUE_COUNT=1"
  echo "ISSUES:"
  echo "  - SEVERITY=ERROR TYPE=missing_tool MSG=jq is required but not installed"
  echo "=== END BLUEPRINT SYNC-IDS ==="
  exit 1
fi
echo "JQ_AVAILABLE=true"

# Extract a frontmatter id value (first match, trimmed).
extract_id() {
  head -50 "$1" 2>/dev/null | grep -m1 "^id:" | sed 's/^id:[[:space:]]*//' | tr -d '\r'
}

prd_dir="${project_dir}/docs/prds"
adr_dir="${project_dir}/docs/adrs"
prp_dir="${project_dir}/docs/prps"
wo_dir="${project_dir}/docs/blueprint/work-orders"
manifest="${project_dir}/docs/blueprint/manifest.json"

# --- PRDs: id present or NEEDS_ID (no filename derivation) ---
prd_with=0; prd_missing=0
for doc_path in "${prd_dir}"/*.md; do
  [ -f "$doc_path" ] || continue
  existing_id="$(extract_id "$doc_path")"
  if [ -z "$existing_id" ]; then
    prd_missing=$((prd_missing + 1))
    add_issue WARN needs_id "DOC=${doc_path} KIND=PRD"
  else
    prd_with=$((prd_with + 1))
  fi
done
echo "PRD_WITH_ID=${prd_with}"
echo "PRD_NEEDS_ID=${prd_missing}"

# --- ADRs: expected ADR-NNNN from a 4-digit filename prefix ---
adr_with=0; adr_missing=0; adr_mismatch=0
for doc_path in "${adr_dir}"/*.md; do
  [ -f "$doc_path" ] || continue
  fname="$(basename "$doc_path")"
  num="$(printf '%s' "$fname" | grep -oE '^[0-9]{4}')"
  [ -n "$num" ] || continue
  expected_id="ADR-${num}"
  existing_id="$(extract_id "$doc_path")"
  if [ -z "$existing_id" ]; then
    adr_missing=$((adr_missing + 1))
    add_issue WARN needs_id "DOC=${doc_path} KIND=ADR EXPECTED=${expected_id}"
  elif [ "$existing_id" != "$expected_id" ]; then
    adr_mismatch=$((adr_mismatch + 1))
    add_issue ERROR id_mismatch "DOC=${doc_path} KIND=ADR HAS=${existing_id} EXPECTED=${expected_id}"
  else
    adr_with=$((adr_with + 1))
  fi
done
echo "ADR_WITH_ID=${adr_with}"
echo "ADR_NEEDS_ID=${adr_missing}"
echo "ADR_MISMATCH=${adr_mismatch}"

# --- PRPs: id present or NEEDS_ID (no filename derivation) ---
prp_with=0; prp_missing=0
for doc_path in "${prp_dir}"/*.md; do
  [ -f "$doc_path" ] || continue
  existing_id="$(extract_id "$doc_path")"
  if [ -z "$existing_id" ]; then
    prp_missing=$((prp_missing + 1))
    add_issue WARN needs_id "DOC=${doc_path} KIND=PRP"
  else
    prp_with=$((prp_with + 1))
  fi
done
echo "PRP_WITH_ID=${prp_with}"
echo "PRP_NEEDS_ID=${prp_missing}"

# --- Work-Orders: expected WO-NNN from a 3-digit filename prefix ---
wo_with=0; wo_missing=0; wo_mismatch=0
for doc_path in "${wo_dir}"/*.md; do
  [ -f "$doc_path" ] || continue
  fname="$(basename "$doc_path")"
  num="$(printf '%s' "$fname" | grep -oE '^[0-9]{3}')"
  [ -n "$num" ] || continue
  expected_id="WO-${num}"
  existing_id="$(extract_id "$doc_path")"
  if [ -z "$existing_id" ]; then
    wo_missing=$((wo_missing + 1))
    add_issue WARN needs_id "DOC=${doc_path} KIND=WO EXPECTED=${expected_id}"
  elif [ "$existing_id" != "$expected_id" ]; then
    wo_mismatch=$((wo_mismatch + 1))
    add_issue ERROR id_mismatch "DOC=${doc_path} KIND=WO HAS=${existing_id} EXPECTED=${expected_id}"
  else
    wo_with=$((wo_with + 1))
  fi
done
echo "WO_WITH_ID=${wo_with}"
echo "WO_NEEDS_ID=${wo_missing}"
echo "WO_MISMATCH=${wo_mismatch}"

total_docs=$((prd_with + prd_missing + adr_with + adr_missing + adr_mismatch + prp_with + prp_missing + wo_with + wo_missing + wo_mismatch))
total_needs=$((prd_missing + adr_missing + prp_missing + wo_missing))
echo "TOTAL_DOCS=${total_docs}"
echo "TOTAL_NEEDS_ID=${total_needs}"

# --- Reverse github_issues index from the manifest documents registry ---
# Each document's `github_issues` array contributes a doc-id under every
# issue number. Reverses {DOC: [issues]} into {issue: [DOCs]}.
manifest_present=false
gh_issue_mappings=0
if [ -f "$manifest" ] && jq empty "$manifest" >/dev/null 2>&1; then
  manifest_present=true
  gh_issue_mappings="$(jq -r '
    [ (.id_registry.documents // {}) | to_entries[]
      | .key as $doc | (.value.github_issues // [])[] | {issue: (. | tostring), doc: $doc} ]
    | group_by(.issue)
    | length
  ' "$manifest" 2>/dev/null || echo 0)"
fi
echo "MANIFEST_PRESENT=${manifest_present}"
echo "GH_ISSUE_MAPPINGS=${gh_issue_mappings}"

if [ "$adr_mismatch" -gt 0 ] || [ "$wo_mismatch" -gt 0 ]; then
  audit_status="ERROR"
elif [ "$total_needs" -gt 0 ]; then
  audit_status="WARN"
fi

echo "STATUS=${audit_status}"
echo "ISSUE_COUNT=${issue_count}"
if [ -n "$issues_list" ]; then
  echo "ISSUES:"
  printf '%b' "$issues_list" | sed '/^$/d'
fi
echo "=== END BLUEPRINT SYNC-IDS ==="

[ "$audit_status" = "ERROR" ] && exit 1
exit 0
