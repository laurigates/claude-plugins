#!/usr/bin/env bash
# blueprint-sync-ids audit (read-only)
# Scans PRDs, ADRs, PRPs, and work-orders for frontmatter `id:` values,
# derives the expected ADR-NNNN / WO-NNN from each filename, flags
# MISMATCH/NEEDS_ID, and builds the reverse github_issues index from the
# manifest registry. This is the *audit* surface only — actual ID
# assignment and manifest mutation stay in the skill.
#
# Issue #2866 widened the audit. On a repo naming its ADRs `ADR-NNN-title.md`
# it reported STATUS=OK with ADR_WITH_ID=0 while a manual audit of the same
# tree found duplicate ids, a swapped registry pair, unregistered documents and
# stale counters. It now:
#   - accepts `NNNN-title.md` and `ADR-NNN(N)-title.md` ADR basenames, and
#     falls back to the frontmatter `id:` when the filename carries no number;
#   - resolves the ADR directory as docs/adrs, then docs/adr (the order
#     check-adr-numbers.sh uses);
#   - ERRORs `duplicate_id` when two documents of one kind share a frontmatter id;
#   - compares each document with `id_registry.documents` (WARN `unregistered`,
#     ERROR `id_path_mismatch`, ERROR `registry_path_missing`) and WARNs
#     `counter_stale` when a `last_*` counter is below the highest id on disk.
# The registry checks run ONLY when the manifest carries an `id_registry` with
# a `documents` map. Without one (this repo's own manifest has no id_registry)
# they are skipped entirely and REGISTRY_PRESENT=false is reported.
#
# Usage: bash blueprint-sync-ids.sh --project-dir <path> [--home-dir <path>]
#
# The doc-tree roots default to <project_dir>/docs/{prds,adrs,prps} and
# <project_dir>/docs/blueprint/work-orders. Tests plant a fixture tree and
# point --project-dir at it so the audit runs fully offline.
#
# Output follows .claude/rules/structured-script-output.md: STATUS=, ISSUE_COUNT=
# and, on WARN/ERROR, a bounded REASON= naming the first finding.

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
[ "$project_dir" = "/" ] || project_dir="${project_dir%/}"

echo "=== BLUEPRINT SYNC-IDS ==="

audit_status="OK"
issue_count=0
issues_list=""
has_error=0

add_issue() {
  # $1 severity, $2 type, $3 key/value detail
  issues_list="${issues_list}  - SEVERITY=$1 TYPE=$2 $3"$'\n'
  issue_count=$((issue_count + 1))
  [ "$1" = "ERROR" ] && has_error=1
  return 0
}

if ! command -v jq >/dev/null 2>&1; then
  echo "JQ_AVAILABLE=false"
  echo "STATUS=ERROR"
  echo "REASON=missing_tool: jq is required but not installed"
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

# Project-relative form of a path under the project dir.
rel_of() {
  case "$1" in
    "$project_dir"/*) printf '%s' "${1#"$project_dir"/}" ;;
    *) printf '%s' "$1" ;;
  esac
}

# Every id seen on disk, one row per document:
#   kind<TAB>id<TAB>source<TAB>project-relative-path
# source is `frontmatter` (an `id:` claim) or `filename` (derived, no `id:`).
# Duplicate and registry checks read frontmatter rows; the counter check reads
# both, since a filename-derived ADR number is still taken.
id_rows=""
add_row() { # kind id source path
  id_rows="${id_rows}$1"$'\t'"$2"$'\t'"$3"$'\t'"$(rel_of "$4")"$'\n'
}

prd_dir="${project_dir}/docs/prds"
prp_dir="${project_dir}/docs/prps"
wo_dir="${project_dir}/docs/blueprint/work-orders"
manifest="${project_dir}/docs/blueprint/manifest.json"

adr_dir=""
for cand in docs/adrs docs/adr; do
  if [ -d "${project_dir}/${cand}" ]; then
    adr_dir="${project_dir}/${cand}"
    break
  fi
done

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
    add_row PRD "$existing_id" frontmatter "$doc_path"
  fi
done
echo "PRD_WITH_ID=${prd_with}"
echo "PRD_NEEDS_ID=${prd_missing}"

# --- ADRs: expected id from a `NNNN-` or `ADR-NNN(N)-` filename prefix, else
# the frontmatter id alone (issue #2866) ---
adr_with=0; adr_missing=0; adr_mismatch=0; adr_fm_only=0
if [ -n "$adr_dir" ]; then
  echo "ADR_DIR=$(rel_of "$adr_dir")"
  for doc_path in "${adr_dir}"/*.md; do
    [ -f "$doc_path" ] || continue
    fname="$(basename "$doc_path")"
    num="$(printf '%s' "$fname" | grep -oE '^[0-9]{4}')"
    [ -n "$num" ] || num="$(printf '%s' "$fname" | sed -nE 's/^[Aa][Dd][Rr]-([0-9]{3,4})-.*/\1/p')"
    existing_id="$(extract_id "$doc_path")"
    if [ -z "$num" ]; then
      # No number in the filename: the frontmatter id is the only claim. A
      # file with neither (README.md, a template) is not an ADR.
      [ -n "$existing_id" ] || continue
      adr_with=$((adr_with + 1))
      adr_fm_only=$((adr_fm_only + 1))
      add_row ADR "$existing_id" frontmatter "$doc_path"
      continue
    fi
    expected_id="ADR-${num}"
    # `ADR-001-x.md` may carry `id: ADR-001` or the canonical `id: ADR-0001`.
    expected_padded="ADR-$(printf '%04d' "$((10#$num))")"
    if [ -z "$existing_id" ]; then
      adr_missing=$((adr_missing + 1))
      add_issue WARN needs_id "DOC=${doc_path} KIND=ADR EXPECTED=${expected_id}"
      add_row ADR "$expected_id" filename "$doc_path"
    elif [ "$existing_id" != "$expected_id" ] && [ "$existing_id" != "$expected_padded" ]; then
      adr_mismatch=$((adr_mismatch + 1))
      add_issue ERROR id_mismatch "DOC=${doc_path} KIND=ADR HAS=${existing_id} EXPECTED=${expected_id}"
      add_row ADR "$existing_id" frontmatter "$doc_path"
    else
      adr_with=$((adr_with + 1))
      add_row ADR "$existing_id" frontmatter "$doc_path"
    fi
  done
else
  echo "ADR_DIR=none"
fi
echo "ADR_WITH_ID=${adr_with}"
echo "ADR_NEEDS_ID=${adr_missing}"
echo "ADR_MISMATCH=${adr_mismatch}"
echo "ADR_FRONTMATTER_ONLY=${adr_fm_only}"

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
    add_row PRP "$existing_id" frontmatter "$doc_path"
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
    add_row WO "$expected_id" filename "$doc_path"
  elif [ "$existing_id" != "$expected_id" ]; then
    wo_mismatch=$((wo_mismatch + 1))
    add_issue ERROR id_mismatch "DOC=${doc_path} KIND=WO HAS=${existing_id} EXPECTED=${expected_id}"
    add_row WO "$existing_id" frontmatter "$doc_path"
  else
    wo_with=$((wo_with + 1))
    add_row WO "$existing_id" frontmatter "$doc_path"
  fi
done
echo "WO_WITH_ID=${wo_with}"
echo "WO_NEEDS_ID=${wo_missing}"
echo "WO_MISMATCH=${wo_mismatch}"

total_docs=$((prd_with + prd_missing + adr_with + adr_missing + adr_mismatch + prp_with + prp_missing + wo_with + wo_missing + wo_mismatch))
total_needs=$((prd_missing + adr_missing + prp_missing + wo_missing))
echo "TOTAL_DOCS=${total_docs}"
echo "TOTAL_NEEDS_ID=${total_needs}"

# Shared awk helper: normalise an id so `PRP-010`, `prp-10` and `PRP-0010`
# compare equal (prefix upper-cased, number without leading zeros).
# shellcheck disable=SC2016  # awk program text, not a shell expansion
AWK_NORM='
function norm(s,   u, p, n) {
  u = toupper(s)
  if (u ~ /^[A-Z]+-[0-9]+$/) {
    p = u; sub(/-.*/, "", p)
    n = u; sub(/^[A-Z]+-0*/, "", n)
    if (n == "") n = "0"
    return p "-" n
  }
  return u
}'

# --- Duplicate frontmatter ids within a kind (issue #2866) ---
duplicate_ids=0
while IFS=$'\t' read -r d_kind d_id d_docs; do
  [ -n "${d_kind:-}" ] || continue
  duplicate_ids=$((duplicate_ids + 1))
  add_issue ERROR duplicate_id "KIND=${d_kind} ID=${d_id} DOCS=${d_docs}"
done < <(printf '%s' "$id_rows" | awk -F'\t' "$AWK_NORM"'
  $3 == "frontmatter" {
    k = $1 SUBSEP norm($2)
    if (!(k in first)) { first[k] = $2; order[++n] = k }
    if (!seen[k, $4]++) { docs[k] = docs[k] (docs[k] == "" ? "" : ",") $4; cnt[k]++ }
  }
  END {
    for (i = 1; i <= n; i++) {
      k = order[i]
      if (cnt[k] > 1) { split(k, parts, SUBSEP); print parts[1] "\t" first[k] "\t" docs[k] }
    }
  }')
echo "DUPLICATE_IDS=${duplicate_ids}"

# --- Manifest: reverse github_issues index + id_registry comparison ---
# Each document's `github_issues` array contributes a doc-id under every
# issue number. Reverses {DOC: [issues]} into {issue: [DOCs]}.
manifest_present=false
registry_present=false
gh_issue_mappings=0
if [ -f "$manifest" ] && jq empty "$manifest" >/dev/null 2>&1; then
  manifest_present=true
  gh_issue_mappings="$(jq -r '
    [ (.id_registry.documents // {}) | to_entries[]
      | .key as $doc | (.value.github_issues // [])[] | {issue: (. | tostring), doc: $doc} ]
    | group_by(.issue)
    | length
  ' "$manifest" 2>/dev/null || echo 0)"
  # Present only as an object `documents` map: a null, absent, or non-object
  # id_registry (this repo's own manifest has none) skips every registry check.
  if jq -e '((.id_registry // {}) | type) == "object"
            and (((.id_registry // {}).documents // null) | type) == "object"' \
       "$manifest" >/dev/null 2>&1; then
    registry_present=true
  fi
fi
echo "MANIFEST_PRESENT=${manifest_present}"
echo "GH_ISSUE_MAPPINGS=${gh_issue_mappings}"
echo "REGISTRY_PRESENT=${registry_present}"

reg_unregistered=0; reg_mismatch=0; reg_missing=0; counter_stale=0
if [ "$registry_present" = true ]; then
  # Registry rows: id<TAB>path. The path is empty for an entry that records
  # none; such an entry still registers its id, it just cannot be path-checked.
  reg_rows="$(jq -r '
    (.id_registry.documents // {}) | to_entries[]
    | [ .key,
        (if (.value | type) == "object" and ((.value.path // null) | type) == "string"
         then (.value.path | ltrimstr("./")) else "" end) ]
    | @tsv' "$manifest" 2>/dev/null)"

  # A document's frontmatter id against the registry entry for its path.
  while IFS=$'\t' read -r r_sev r_type r_detail; do
    [ -n "${r_sev:-}" ] || continue
    case "$r_type" in
      unregistered) reg_unregistered=$((reg_unregistered + 1)) ;;
      id_path_mismatch) reg_mismatch=$((reg_mismatch + 1)) ;;
    esac
    add_issue "$r_sev" "$r_type" "$r_detail"
  done < <(awk -F'\t' "$AWK_NORM"'
    FNR == NR {
      if ($1 != "") { by_id[norm($1)] = $2; if ($2 != "") by_path[$2] = $1 }
      next
    }
    $3 != "frontmatter" { next }
    {
      kind = $1; id = $2; p = $4
      if (p in by_path) {
        # The registry records this path under a different id: a swapped or
        # stale pair.
        if (norm(by_path[p]) != norm(id))
          print "ERROR\tid_path_mismatch\tDOC=" p " HAS=" id " REGISTRY=" by_path[p]
      } else if (norm(id) in by_id) {
        # The id is registered; it is a mismatch only when the entry names
        # another path.
        if (by_id[norm(id)] != "")
          print "ERROR\tid_path_mismatch\tDOC=" p " HAS=" id " REGISTRY_PATH=" by_id[norm(id)]
      } else {
        print "WARN\tunregistered\tDOC=" p " KIND=" kind " ID=" id
      }
    }' <(printf '%s\n' "$reg_rows") <(printf '%s' "$id_rows"))

  # A registry entry whose path is not on disk.
  while IFS=$'\t' read -r m_id m_path; do
    [ -n "${m_id:-}" ] || continue
    [ -n "${m_path:-}" ] || continue
    case "$m_path" in
      /*) m_abs="$m_path" ;;
      *) m_abs="${project_dir}/${m_path}" ;;
    esac
    if [ ! -e "$m_abs" ]; then
      reg_missing=$((reg_missing + 1))
      add_issue ERROR registry_path_missing "ID=${m_id} PATH=${m_path}"
    fi
  done < <(printf '%s\n' "$reg_rows")

  # `last_*` counters below the highest id of their kind on disk. Every
  # `last_<kind>` key present is checked (last_prd, last_prp, last_trp, ...).
  while IFS=$'\t' read -r c_key c_val; do
    [ -n "${c_key:-}" ] || continue
    c_kind="$(printf '%s' "${c_key#last_}" | tr '[:lower:]' '[:upper:]')"
    c_max="$(printf '%s' "$id_rows" | awk -F'\t' -v k="$c_kind" '
      toupper($1) == k && toupper($2) ~ /^[A-Z]+-[0-9]+$/ {
        n = $2; sub(/^[^-]*-0*/, "", n); n = n + 0; if (n > m) m = n
      }
      END { print m + 0 }')"
    if [ "$c_max" -gt "$c_val" ]; then
      counter_stale=$((counter_stale + 1))
      add_issue WARN counter_stale "COUNTER=${c_key} VALUE=${c_val} MAX_ON_DISK=${c_kind}-${c_max}"
    fi
  done < <(jq -r '
    (.id_registry // {}) | to_entries[]
    | select(.key | test("^last_[a-z]+$"))
    | select((.value | type) == "number")
    | "\(.key)\t\(.value | floor)"' "$manifest" 2>/dev/null)
fi
echo "REGISTRY_UNREGISTERED=${reg_unregistered}"
echo "REGISTRY_ID_PATH_MISMATCH=${reg_mismatch}"
echo "REGISTRY_PATH_MISSING=${reg_missing}"
echo "COUNTER_STALE=${counter_stale}"

if [ "$has_error" -eq 1 ]; then
  audit_status="ERROR"
elif [ "$issue_count" -gt 0 ]; then
  audit_status="WARN"
fi

echo "STATUS=${audit_status}"
# REASON= on the non-OK path: the first finding at the reported severity as
# "<TYPE>: <detail>", bounded, plus " (+N more)" when there are others.
if [ "$audit_status" != "OK" ]; then
  reason="$(printf '%s' "$issues_list" | awk -v sev="$audit_status" '
    index($0, "SEVERITY=" sev " ") && first == "" {
      line = $0
      sub(/^[[:space:]]*- SEVERITY=[A-Z]+ TYPE=/, "", line)
      sub(/ /, ": ", line)
      first = line
    }
    END { print first }' | tr -s '[:space:]' ' ' | cut -c1-180)"
  reason="${reason% }"
  [ "$issue_count" -gt 1 ] && reason="${reason} (+$((issue_count - 1)) more)"
  echo "REASON=${reason}"
fi
echo "ISSUE_COUNT=${issue_count}"
if [ -n "$issues_list" ]; then
  echo "ISSUES:"
  printf '%s' "$issues_list"
fi
echo "=== END BLUEPRINT SYNC-IDS ==="

[ "$audit_status" = "ERROR" ] && exit 1
exit 0
