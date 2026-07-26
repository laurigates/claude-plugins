#!/usr/bin/env bash
# check-adr-numbers.sh — detect ADR-number collisions and index drift.
#
# ADR numbers are chosen at branch time but only claimed at merge time, so two
# in-flight ADR PRs can pick the same number and both land (the FVH
# infrastructure #2015 collision: two 0038 ADRs). This is the lightweight
# validation-only guard from issue #1585 — no renaming automation, just
# collision + index-drift detection.
#
# ── Issue #2129: the guard reported STATUS=OK on a REAL ADR-0016 collision ─────
#
# Two files both claimed ADR-0016 and the guard could not see it, for two
# compounding structural reasons that this script now fixes:
#
#   1. Number derivation was BASENAME-only, so `docs/adrs/objs-format.md` with
#      frontmatter `id: ADR-0016` contributed no number at all. The collection
#      step now UNIONS the `NNNN-title.md` basename number with a frontmatter
#      `id: ADR-NNNN` claim, and reports which source a number came from (a bare
#      "ADR number 16 claimed by objs-format.md" is baffling otherwise).
#   2. The ADR directory resolved to a SINGLE directory, so two claimants in
#      `docs/adrs/` and `docs/blueprint/adrs/` were never compared. The scan now
#      takes a REPEATABLE `--adr-dir` and otherwise reads the directory SET from
#      the shared `validation` manifest block (issue #2128, via
#      ../../../scripts/get-validation-config.sh) — one config surface, not two.
#
# It reports four classes:
#   1. duplicate_adr_number  — two files (in any scanned directory) claim the
#      same number, by basename or by frontmatter id.                    ERROR
#   2. adr_number_collision  — a working-tree ADR claims a number a DIFFERENT
#      file already holds on the base ref (origin/main). This is the pre-merge
#      parallel-PR case — caught before the second PR merges.             ERROR
#   3. adr_registry_mismatch — a file claims ADR-NNNN but the manifest
#      `id_registry` maps NNNN to a different path. The registry is the only
#      place that resolves id -> path unambiguously: two files can both SAY
#      ADR-0016, but only one can be registered.                         ERROR
#   4. adr_missing_index_row — an ADR file is not referenced from the ADR
#      directory's README index (how the 0038 collision went unnoticed).  WARN
#
# Class 4 is repairable, not just reportable: `generate-adr-index.sh` rebuilds
# the index table from frontmatter between marker comments (`--check` for CI).
#
# Emits the structured KEY=VALUE / STATUS= / ISSUE_COUNT= convention
# (.claude/rules/structured-script-output.md). Exit 0 on OK/WARN, 1 on ERROR
# (parallel-safe per .claude/rules/parallel-safe-queries.md), 2 on a usage error.
#
# Multi-valued keys (ADR_DIRS) use a single TAB as the element delimiter, the
# same choice get-validation-config.sh documents: a path may contain a space, so
# space-joining would silently corrupt it.
#
# Backward compatibility: ADR_DIR= (the FIRST scanned directory, or `none`),
# ADR_COUNT= and INDEX= are still emitted with their #1585 meanings; the
# per-directory detail is additive (ADR_DIR_<n>*, ADR_DIRS, ADR_DIR_COUNT).
#
# Usage: check-adr-numbers.sh [--project-dir DIR] [--base-ref REF]
#                             [--adr-dir DIR]...
#
# `set -u` only (not `-euo pipefail`): this is a multi-section collector that
# must reach EVERY section, and a `producer | head`/`| grep -m1` SIGPIPE under
# pipefail would abort the run (.claude/rules/shell-scripting.md).
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_SCRIPT="$SCRIPT_DIR/../../../scripts/get-validation-config.sh"

project_dir="$(pwd)"
base_ref="origin/main"
cli_adr_dirs=()

usage() {
  printf 'usage: check-adr-numbers.sh [--project-dir DIR] [--base-ref REF] [--adr-dir DIR]...\n' >&2
}

need_value() { # <flag> <remaining-arg-count>
  if [ "$2" -lt 2 ]; then
    printf 'check-adr-numbers.sh: %s requires a value\n' "$1" >&2
    usage
    exit 2
  fi
}

while [ $# -gt 0 ]; do
  case "$1" in
    --project-dir) need_value "$1" $#; project_dir="$2"; shift 2 ;;
    --base-ref)    need_value "$1" $#; base_ref="$2"; shift 2 ;;
    --adr-dir)     need_value "$1" $#; cli_adr_dirs+=("$2"); shift 2 ;;
    --project-dir=*) project_dir="${1#*=}"; shift ;;
    --base-ref=*)    base_ref="${1#*=}"; shift ;;
    --adr-dir=*)     cli_adr_dirs+=("${1#*=}"); shift ;;
    -h|--help)     usage; exit 0 ;;
    # Fail fast on an unrecognised argument (the #2057 lesson): --adr-dir is what
    # BOUNDS the scan, so silently swallowing a typo'd flag would quietly narrow
    # the guard back to the config default and re-introduce a false OK.
    *) printf 'check-adr-numbers.sh: unknown argument: %s\n' "$1" >&2; usage; exit 2 ;;
  esac
done

emit() { printf '%s\n' "$1"; }

echo "=== ADR NUMBER AUDIT ==="

# --- Resolve the ADR directory SET --------------------------------------------
# Precedence: explicit --adr-dir flags > the shared `validation.adr_dirs` config
# > the hardcoded docs/adrs-then-docs/adr order #1585 used.
adr_candidates=()
dir_source="default"

if [ "${#cli_adr_dirs[@]}" -gt 0 ]; then
  adr_candidates=("${cli_adr_dirs[@]}")
  dir_source="cli"
else
  cfg=""
  if [ -f "$CONFIG_SCRIPT" ]; then
    cfg="$(bash "$CONFIG_SCRIPT" --project-dir "$project_dir")"
  fi
  # Trust the config only when it actually produced its contract; a broken or
  # missing reader falls back to the #1585 order rather than silently scanning
  # nothing (which would read as a clean OK).
  if printf '%s\n' "$cfg" | grep -q '^STATUS=OK$'; then
    # The documented consuming idiom from get-validation-config.sh's header.
    cfg_line="$(printf '%s\n' "$cfg" | grep -m1 '^ADR_DIRS=')"
    IFS=$'\t' read -r -a adr_candidates <<<"${cfg_line#ADR_DIRS=}"
    cfg_line="$(printf '%s\n' "$cfg" | grep -m1 '^SOURCE=')"
    # An explicitly-configured empty list is honoured as "scan nothing".
    dir_source="config:${cfg_line#SOURCE=}"
  else
    adr_candidates=(docs/adrs docs/adr)
    dir_source="default"
  fi
fi

# Keep the ones that exist, de-duplicated by absolute path.
adr_abs=()
adr_rels=()
seen_abs=""
for cand in "${adr_candidates[@]}"; do
  [ -n "$cand" ] || continue
  cand="${cand%/}"
  case "$cand" in
    /*) cand_abs="$cand" ;;
    *)  cand_abs="$project_dir/$cand" ;;
  esac
  [ -d "$cand_abs" ] || continue
  case "$seen_abs" in *"|$cand_abs|"*) continue ;; esac
  seen_abs="${seen_abs}|$cand_abs|"
  case "$cand_abs" in
    "$project_dir"/*) cand_rel="${cand_abs#"$project_dir"/}" ;;
    *) cand_rel="$cand_abs" ;;
  esac
  adr_abs+=("$cand_abs")
  adr_rels+=("$cand_rel")
done

emit "ADR_DIR_SOURCE=$dir_source"

if [ "${#adr_abs[@]}" -eq 0 ]; then
  emit "ADR_DIR=none"
  emit "ADR_DIRS="
  emit "ADR_DIR_COUNT=0"
  emit "STATUS=OK"
  emit "ISSUE_COUNT=0"
  emit "=== END ADR NUMBER AUDIT ==="
  exit 0
fi

# ADR_DIR= keeps its #1585 meaning (the first resolved directory).
emit "ADR_DIR=${adr_rels[0]}"
adr_dirs_joined=""
for r in "${adr_rels[@]}"; do
  adr_dirs_joined="${adr_dirs_joined}${adr_dirs_joined:+$'\t'}${r}"
done
emit "ADR_DIRS=$adr_dirs_joined"
emit "ADR_DIR_COUNT=${#adr_abs[@]}"

# --- Number derivation --------------------------------------------------------
# Normalize a "NNNN-title.md" basename to a bare integer, or empty if the file
# does not lead with a number (README.md, validation-report.md, templates).
adr_number() {
  local base="$1" num
  num="$(printf '%s' "$base" | sed -nE 's/^0*([0-9]+)[-_].*/\1/p')"
  [ -n "$num" ] && printf '%d' "$((10#$num))"
}

# Read a frontmatter `id: ADR-NNNN` claim (issue #2129). Uses the head-limited
# extraction idiom from .claude/rules/shell-scripting.md so a body mention of
# "id: ADR-…" far down the file is never mistaken for a claim.
adr_number_from_frontmatter_text() {
  local num
  num="$(head -50 | tr -d '\r' | sed -nE 's/^[Ii][Dd]:[[:space:]]*[Aa][Dd][Rr][-_ ]?0*([0-9]+).*/\1/p' | head -1)"
  [ -n "$num" ] && printf '%d' "$((10#$num))"
}

adr_number_from_frontmatter() {
  adr_number_from_frontmatter_text < "$1"
}

# Rows are "number<TAB>project-relative-path<TAB>source".
wt_rows=""
adr_count=0
frontmatter_claims=0

# add_claims <rel-path> <basename-num> <frontmatter-num>
# Prints one row per DISTINCT number the file claims, so a file whose basename
# and frontmatter agree never collides with itself.
add_claims() {
  local ac_rel="$1" ac_bnum="$2" ac_fnum="$3"
  if [ -n "$ac_bnum" ] && [ -n "$ac_fnum" ] && [ "$ac_bnum" = "$ac_fnum" ]; then
    printf '%s\t%s\t%s\n' "$ac_bnum" "$ac_rel" "basename+frontmatter"
    return 0
  fi
  [ -n "$ac_bnum" ] && printf '%s\t%s\t%s\n' "$ac_bnum" "$ac_rel" "basename"
  [ -n "$ac_fnum" ] && printf '%s\t%s\t%s\n' "$ac_fnum" "$ac_rel" "frontmatter"
  return 0
}

for i in "${!adr_abs[@]}"; do
  dir_abs="${adr_abs[$i]}"
  dir_rel="${adr_rels[$i]}"
  dir_count=0
  for f in "$dir_abs"/*.md; do
    [ -e "$f" ] || continue
    base="$(basename "$f")"
    bnum="$(adr_number "$base")"
    fnum="$(adr_number_from_frontmatter "$f")"
    [ -n "$bnum" ] || [ -n "$fnum" ] || continue
    if [ -z "$bnum" ] && [ -n "$fnum" ]; then
      frontmatter_claims=$((frontmatter_claims + 1))
    fi
    dir_count=$((dir_count + 1))
    adr_count=$((adr_count + 1))
    wt_rows="${wt_rows}$(add_claims "$dir_rel/$base" "$bnum" "$fnum")"$'\n'
  done
  emit "ADR_DIR_$((i + 1))=$dir_rel"
  emit "ADR_DIR_$((i + 1))_COUNT=$dir_count"
done

emit "ADR_COUNT=$adr_count"
# Files whose ONLY number claim comes from frontmatter — invisible to the #1585
# basename-only guard, which is exactly how the ADR-0016 collision hid.
emit "FRONTMATTER_ONLY_CLAIMS=$frontmatter_claims"

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
dup_numbers="$(printf '%s' "$wt_rows" | awk -F'\t' 'NF==3 && !seen[$1"\t"$2]++ {c[$1]++} END{for(n in c) if(c[n]>1) print n}' | sort -n)"
for n in $dup_numbers; do
  files="$(printf '%s' "$wt_rows" | awk -F'\t' -v n="$n" '$1==n && !s[$2]++ {printf "%s (%s), ", $2, $3}')"
  add_issue ERROR duplicate_adr_number "ADR number $n claimed by multiple files: ${files%, }"
done

# --- Check 2: collision with a different file on the base ref -----------------
# PATH FRAMES (the #1585 note said "these coincide when the project dir is the
# repo root"; widening to N directories makes getting it right cheaper than
# narrowing). Run every git call with `-C "$project_dir"` and keep BOTH the
# pathspec and the output in the PROJECT-dir frame:
#   * `ls-tree -- <relative-pathspec>` resolves the pathspec against the cwd and
#     prints cwd-relative paths (it needs `--full-name` to print repo-relative),
#     so `docs/adrs` in, `docs/adrs/x.md` out — already our row frame.
#   * `<rev>:<path>` for `git show` is REPO-root-relative UNLESS it starts with
#     `./`, hence the `./` prefix below.
base_available=false
base_rows=""
if git -C "$project_dir" rev-parse --verify --quiet "$base_ref" >/dev/null 2>&1; then
  base_available=true
  for dir_rel in "${adr_rels[@]}"; do
    # An ADR dir outside the project dir is not addressable in this frame; skip
    # its base comparison rather than guess (the deliberate narrowing).
    case "$dir_rel" in /*) continue ;; esac
    while IFS= read -r brel; do
      [ -n "$brel" ] || continue
      case "$brel" in *.md) ;; *) continue ;; esac
      b_bnum="$(adr_number "$(basename "$brel")")"
      b_fnum="$(git -C "$project_dir" show "$base_ref:./$brel" 2>/dev/null | adr_number_from_frontmatter_text)"
      [ -n "$b_bnum" ] || [ -n "$b_fnum" ] || continue
      base_rows="${base_rows}$(add_claims "$brel" "$b_bnum" "$b_fnum")"$'\n'
    done < <(git -C "$project_dir" ls-tree -r --name-only "$base_ref" -- "$dir_rel" 2>/dev/null)
  done
fi
emit "BASE_REF=$base_ref"
emit "BASE_REF_AVAILABLE=$base_available"

if [ "$base_available" = true ]; then
  # For each working ADR, flag if the base ref holds the same number under a
  # path that is NOT present in the working tree for that number.
  while IFS=$'\t' read -r wnum wrel wsrc; do
    [ -n "${wnum:-}" ] || continue
    while IFS=$'\t' read -r bnum brel bsrc; do
      [ -n "${bnum:-}" ] || continue
      [ "$bnum" = "$wnum" ] || continue
      [ "$brel" = "$wrel" ] && continue
      # base holds this number under a different path. Confirm that other path
      # is not itself in the working tree (i.e. it is a genuine cross-boundary
      # collision, not an unrelated rename we already track).
      if ! printf '%s' "$wt_rows" | awk -F'\t' -v n="$wnum" -v b="$brel" '$1==n && $2==b{f=1} END{exit !f}'; then
        add_issue ERROR adr_number_collision "ADR number $wnum in '$wrel' ($wsrc) also claimed on $base_ref by '$brel' ($bsrc)"
      fi
    done < <(printf '%s' "$base_rows")
  done < <(printf '%s' "$wt_rows")
fi

# --- Check 3: the manifest id_registry is the arbiter -------------------------
# Two files can both SAY ADR-0016; only one can be REGISTERED. This catches the
# #2129 collision in one comparison and needs no filename convention at all.
# Degrades SILENTLY (REGISTRY=absent, no issue, exit 0) when there is no
# manifest, no jq, or no id_registry — this repo's own manifest has no
# id_registry key, and that path must stay quiet.
manifest=""
for cand in "$project_dir/docs/blueprint/manifest.json" "$project_dir/docs/blueprint/.manifest.json"; do
  if [ -f "$cand" ]; then manifest="$cand"; break; fi
done

registry_state=absent
registry_rows=""
if [ -n "$manifest" ] && command -v jq >/dev/null 2>&1; then
  if jq -e '(.id_registry.documents | type) == "object"' "$manifest" >/dev/null 2>&1; then
    registry_rows="$(jq -r '
      .id_registry.documents | to_entries[]
      | select(.key | test("^ADR-0*[0-9]+$"))
      | select((.value | type) == "object")
      | select((.value.path | type) == "string")
      | [ (.key | capture("^ADR-0*(?<n>[0-9]+)$").n), .value.path ]
      | @tsv' "$manifest" 2>/dev/null)"
    registry_state=present
  fi
fi
registry_count="$(printf '%s' "$registry_rows" | awk 'NF>0' | wc -l | tr -d ' ')"
emit "REGISTRY=$registry_state"
emit "REGISTRY_ADR_COUNT=$registry_count"

if [ "$registry_state" = present ]; then
  while IFS=$'\t' read -r rnum rpath; do
    [ -n "${rnum:-}" ] || continue
    [ -n "${rpath:-}" ] || continue
    rnum_i="$((10#$rnum))"
    rpath="${rpath#./}"
    while IFS=$'\t' read -r wnum wrel wsrc; do
      [ -n "${wnum:-}" ] || continue
      [ "$wnum" = "$rnum_i" ] || continue
      [ "$wrel" = "$rpath" ] && continue
      # Tolerate a registry path recorded with a different directory prefix for
      # the SAME document (basename match) — that is ID-sync's business, not a
      # collision. A different basename is a genuine competing claim.
      [ "$(basename "$wrel")" = "$(basename "$rpath")" ] && continue
      add_issue ERROR adr_registry_mismatch "file '$wrel' claims ADR-$(printf '%04d' "$wnum") ($wsrc) but the manifest id_registry maps $(printf '%04d' "$wnum") to '$rpath'"
    done < <(printf '%s' "$wt_rows")
    # `printf '%s\n'` — jq's output arrives WITHOUT a trailing newline after
    # command substitution, and `while read` drops an unterminated last line.
  done < <(printf '%s\n' "$registry_rows")
fi

# --- Check 4: ADRs missing from the README index ------------------------------
first_index_state=""
for i in "${!adr_abs[@]}"; do
  dir_abs="${adr_abs[$i]}"
  dir_rel="${adr_rels[$i]}"
  readme=""
  for cand in "$dir_abs/README.md" "$dir_abs/readme.md"; do
    [ -f "$cand" ] && { readme="$cand"; break; }
  done
  if [ -n "$readme" ]; then
    emit "ADR_DIR_$((i + 1))_INDEX=present"
    [ -n "$first_index_state" ] || first_index_state=present
    while IFS=$'\t' read -r num rel src; do
      [ -n "${num:-}" ] || continue
      case "$rel" in "$dir_rel"/*) ;; *) continue ;; esac
      rbase="$(basename "$rel")"
      [ "$rbase" = "$(basename "$readme")" ] && continue
      # Indexed if the README mentions the filename OR an ADR-NNNN / ADR NNNN
      # token matching this number (zero-padding-insensitive).
      padded="$(printf '%04d' "$num")"
      if grep -qF "$rbase" "$readme" 2>/dev/null; then continue; fi
      if grep -qiE "ADR[- ]0*${num}([^0-9]|\$)" "$readme" 2>/dev/null; then continue; fi
      if grep -qF "$padded" "$readme" 2>/dev/null; then continue; fi
      add_issue WARN adr_missing_index_row "ADR '$rel' (number $num, $src) is not referenced in $dir_rel/$(basename "$readme")"
    done < <(printf '%s' "$wt_rows")
  else
    emit "ADR_DIR_$((i + 1))_INDEX=absent"
    [ -n "$first_index_state" ] || first_index_state=absent
  fi
done
# INDEX= keeps its #1585 meaning (the FIRST directory's index state).
emit "INDEX=${first_index_state:-absent}"

# --- Roll-up ------------------------------------------------------------------
if [ "$has_error" -eq 1 ]; then
  audit_status="ERROR"
elif [ "$issue_count" -gt 0 ]; then
  audit_status="WARN"
else
  audit_status="OK"
fi
emit "STATUS=$audit_status"
emit "ISSUE_COUNT=$issue_count"
if [ "$issue_count" -gt 0 ]; then
  emit "ISSUES:"
  printf '%s' "$issues"
fi
emit "=== END ADR NUMBER AUDIT ==="

[ "$has_error" -eq 1 ] && exit 1
exit 0
