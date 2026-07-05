#!/usr/bin/env bash
# check-adr-numbers.sh — detect ADR-number collisions and index drift.
#
# ADR numbers are chosen at branch time but only claimed at merge time, so two
# in-flight ADR PRs can pick the same number and both land (the FVH
# infrastructure #2015 collision: two 0038 ADRs). This is the lightweight
# validation-only guard from issue #1585 — no renaming automation, just
# collision + index-drift detection.
#
# It reports three classes:
#   1. duplicate_adr_number  — two files in the working tree claim the same
#      number (post-merge collision, or a hand-numbering slip).            ERROR
#   2. adr_number_collision  — a working-tree ADR claims a number a DIFFERENT
#      filename already holds on the base ref (origin/main). This is the
#      pre-merge parallel-PR case — caught before the second PR merges.    ERROR
#   3. adr_missing_index_row — an ADR file is not referenced from the ADR
#      directory's README index (how the 0038 collision went unnoticed).  WARN
#
# Emits the structured KEY=VALUE / STATUS= / ISSUE_COUNT= convention
# (.claude/rules/structured-script-output.md). Exit 0 on OK/WARN, 1 on ERROR
# (parallel-safe per .claude/rules/parallel-safe-queries.md).
set -uo pipefail

project_dir="$(pwd)"
base_ref="origin/main"

while [ $# -gt 0 ]; do
  case "$1" in
    --project-dir) project_dir="$2"; shift 2 ;;
    --base-ref)    base_ref="$2"; shift 2 ;;
    --project-dir=*) project_dir="${1#*=}"; shift ;;
    --base-ref=*)    base_ref="${1#*=}"; shift ;;
    *) shift ;;
  esac
done

emit() { printf '%s\n' "$1"; }

echo "=== ADR NUMBER AUDIT ==="

# Locate the ADR directory — blueprint canonical is docs/adrs/, but docs/adr/
# is also common (the FVH infrastructure repo where #1585 originated uses it).
adr_dir=""
for cand in "$project_dir/docs/adrs" "$project_dir/docs/adr"; do
  if [ -d "$cand" ]; then adr_dir="$cand"; break; fi
done

if [ -z "$adr_dir" ]; then
  emit "ADR_DIR=none"
  emit "STATUS=OK"
  emit "ISSUE_COUNT=0"
  emit "=== END ADR NUMBER AUDIT ==="
  exit 0
fi

adr_rel="${adr_dir#"$project_dir"/}"
emit "ADR_DIR=$adr_rel"

# Normalize a "NNNN-title.md" basename to a bare integer, or empty if the file
# does not lead with a number (README.md, validation-report.md, templates).
adr_number() {
  local base="$1" num
  num="$(printf '%s' "$base" | sed -nE 's/^0*([0-9]+)[-_].*/\1/p')"
  [ -n "$num" ] && printf '%d' "$((10#$num))"
}

# --- Collect working-tree ADRs: "number<TAB>basename" -------------------------
wt_pairs=""
adr_count=0
for f in "$adr_dir"/*.md; do
  [ -e "$f" ] || continue
  base="$(basename "$f")"
  num="$(adr_number "$base")"
  [ -n "$num" ] || continue
  adr_count=$((adr_count + 1))
  wt_pairs="${wt_pairs}${num}	${base}"$'\n'
done
emit "ADR_COUNT=$adr_count"

issues=""
issue_count=0
has_error=0
add_issue() { # severity type msg
  issues="${issues}  - SEVERITY=$1 TYPE=$2 MSG=$3"$'\n'
  issue_count=$((issue_count + 1))
  [ "$1" = "ERROR" ] && has_error=1
  return 0
}

# --- Check 1: duplicate numbers within the working tree -----------------------
dup_numbers="$(printf '%s' "$wt_pairs" | awk -F'\t' 'NF==2{c[$1]++} END{for(n in c) if(c[n]>1) print n}' | sort -n)"
for n in $dup_numbers; do
  files="$(printf '%s' "$wt_pairs" | awk -F'\t' -v n="$n" '$1==n{printf "%s ", $2}')"
  add_issue ERROR duplicate_adr_number "ADR number $n claimed by multiple files: ${files% }"
done

# --- Check 2: collision with a different filename on the base ref --------------
base_available=false
base_pairs=""
if git -C "$project_dir" rev-parse --verify --quiet "$base_ref" >/dev/null 2>&1; then
  base_available=true
  # git ls-tree paths are repo-relative; adr_rel is project-dir-relative. When
  # the project dir is the repo root these coincide (the common case).
  while IFS= read -r path; do
    [ -n "$path" ] || continue
    b="$(basename "$path")"
    num="$(adr_number "$b")"
    [ -n "$num" ] || continue
    base_pairs="${base_pairs}${num}	${b}"$'\n'
  done < <(git -C "$project_dir" ls-tree -r --name-only "$base_ref" -- "$adr_rel" 2>/dev/null)
fi
emit "BASE_REF=$base_ref"
emit "BASE_REF_AVAILABLE=$base_available"

if [ "$base_available" = true ]; then
  # For each working ADR, flag if the base ref holds the same number under a
  # basename that is NOT present in the working tree for that number.
  while IFS=$'\t' read -r wnum wbase; do
    [ -n "${wnum:-}" ] || continue
    while IFS=$'\t' read -r bnum bbase; do
      [ -n "${bnum:-}" ] || continue
      [ "$bnum" = "$wnum" ] || continue
      [ "$bbase" = "$wbase" ] && continue
      # base holds this number under a different filename. Confirm that other
      # filename is not itself in the working tree (i.e. it is a genuine
      # cross-boundary collision, not an unrelated rename we already track).
      if ! printf '%s' "$wt_pairs" | awk -F'\t' -v n="$wnum" -v b="$bbase" '$1==n && $2==b{f=1} END{exit !f}'; then
        add_issue ERROR adr_number_collision "ADR number $wnum in '$wbase' also claimed on $base_ref by '$bbase'"
      fi
    done < <(printf '%s' "$base_pairs")
  done < <(printf '%s' "$wt_pairs")
fi

# --- Check 3: ADRs missing from the README index ------------------------------
readme=""
for cand in "$adr_dir/README.md" "$adr_dir/readme.md"; do
  [ -f "$cand" ] && { readme="$cand"; break; }
done
if [ -n "$readme" ]; then
  emit "INDEX=$( [ -n "$readme" ] && echo present || echo absent )"
  while IFS=$'\t' read -r num base; do
    [ -n "${num:-}" ] || continue
    # Indexed if the README mentions the filename OR an ADR-NNNN / ADR NNNN token
    # matching this number (zero-padding-insensitive).
    padded="$(printf '%04d' "$num")"
    if grep -qF "$base" "$readme" 2>/dev/null; then continue; fi
    if grep -qiE "ADR[- ]0*${num}([^0-9]|\$)" "$readme" 2>/dev/null; then continue; fi
    if grep -qF "$padded" "$readme" 2>/dev/null; then continue; fi
    add_issue WARN adr_missing_index_row "ADR '$base' (number $num) is not referenced in $(basename "$readme")"
  done < <(printf '%s' "$wt_pairs")
else
  emit "INDEX=absent"
fi

# --- Roll-up ------------------------------------------------------------------
if [ "$has_error" -eq 1 ]; then
  status="ERROR"
elif [ "$issue_count" -gt 0 ]; then
  status="WARN"
else
  status="OK"
fi
emit "STATUS=$status"
emit "ISSUE_COUNT=$issue_count"
if [ "$issue_count" -gt 0 ]; then
  emit "ISSUES:"
  printf '%s' "$issues"
fi
emit "=== END ADR NUMBER AUDIT ==="

[ "$has_error" -eq 1 ] && exit 1
exit 0
