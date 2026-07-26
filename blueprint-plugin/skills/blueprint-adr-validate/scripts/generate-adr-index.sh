#!/usr/bin/env bash
# generate-adr-index.sh — rebuild an ADR directory's README index from frontmatter.
#
# Issue #2129, item 4: `adr_missing_index_row` (check-adr-numbers.sh) could only
# ever WARN, and a rotted index is exactly how the original #1585 `0038`
# collision went unnoticed for a week. The same dogfooding run found
# `INDEX=absent` for one ADR directory while the other's README listed 8 of 25
# ADRs with a stale status. This turns that warning into a REPAIRABLE state.
#
# The table is regenerated between two marker comments so hand-written prose
# around it survives untouched:
#
#   <!-- ADR-INDEX:START -->
#   ...generated table...
#   <!-- ADR-INDEX:END -->
#
# Modes:
#   (default)  WRITE — regenerate the block in each directory's index file.
#              Markers absent => the block is appended (with markers) so the
#              directory becomes generator-managed from now on.
#   --check    READ-ONLY — exit non-zero when an on-disk block differs from the
#              generated one (CI gate). "Markers absent" and "no index file" are
#              reported as DISTINCT non-fatal states, never as a spurious diff.
#
# A number is taken from the `NNNN-title.md` basename OR a frontmatter
# `id: ADR-NNNN` claim, matching check-adr-numbers.sh's widened collection — so
# an ADR that names its number only in frontmatter still gets an index row.
#
# NOTE on the awk one-liner some repos use as a regeneration recipe: its END
# block prints a single row regardless of input, silently collapsing a 25-ADR
# index to one line. Rows here are emitted one-per-ADR inside the collection
# loop, and the regression test asserts ROW_COUNT == ADR_COUNT per directory.
#
# Emits the structured KEY=VALUE / STATUS= / ISSUE_COUNT= convention
# (.claude/rules/structured-script-output.md). Exit 0 on OK/WARN, 1 on ERROR
# (parallel-safe per .claude/rules/parallel-safe-queries.md), 2 on a usage error.
#
# Usage: generate-adr-index.sh [--project-dir DIR] [--adr-dir DIR]... [--check]
#                              [--index-file NAME]
#
# `set -u` only (not `-euo pipefail`): a multi-section collector must reach every
# section, and a `producer | head` SIGPIPE under pipefail aborts the run
# (.claude/rules/shell-scripting.md).
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_SCRIPT="$SCRIPT_DIR/../../../scripts/get-validation-config.sh"

MARKER_START='<!-- ADR-INDEX:START -->'
MARKER_END='<!-- ADR-INDEX:END -->'

project_dir="$(pwd)"
index_name="README.md"
check_only=false
cli_adr_dirs=()

usage() {
  printf 'usage: generate-adr-index.sh [--project-dir DIR] [--adr-dir DIR]... [--check] [--index-file NAME]\n' >&2
}

need_value() { # <flag> <remaining-arg-count>
  if [ "$2" -lt 2 ]; then
    printf 'generate-adr-index.sh: %s requires a value\n' "$1" >&2
    usage
    exit 2
  fi
}

while [ $# -gt 0 ]; do
  case "$1" in
    --project-dir) need_value "$1" $#; project_dir="$2"; shift 2 ;;
    --adr-dir)     need_value "$1" $#; cli_adr_dirs+=("$2"); shift 2 ;;
    --index-file)  need_value "$1" $#; index_name="$2"; shift 2 ;;
    --project-dir=*) project_dir="${1#*=}"; shift ;;
    --adr-dir=*)     cli_adr_dirs+=("${1#*=}"); shift ;;
    --index-file=*)  index_name="${1#*=}"; shift ;;
    --check)       check_only=true; shift ;;
    -h|--help)     usage; exit 0 ;;
    *) printf 'generate-adr-index.sh: unknown argument: %s\n' "$1" >&2; usage; exit 2 ;;
  esac
done

emit() { printf '%s\n' "$1"; }

echo "=== ADR INDEX GENERATION ==="
if [ "$check_only" = true ]; then emit "MODE=check"; else emit "MODE=write"; fi

# --- Resolve the ADR directory SET (same precedence as check-adr-numbers.sh) ---
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
  if printf '%s\n' "$cfg" | grep -q '^STATUS=OK$'; then
    cfg_line="$(printf '%s\n' "$cfg" | grep -m1 '^ADR_DIRS=')"
    IFS=$'\t' read -r -a adr_candidates <<<"${cfg_line#ADR_DIRS=}"
    cfg_line="$(printf '%s\n' "$cfg" | grep -m1 '^SOURCE=')"
    dir_source="config:${cfg_line#SOURCE=}"
  else
    adr_candidates=(docs/adrs docs/adr)
    dir_source="default"
  fi
fi

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
emit "ADR_DIR_COUNT=${#adr_abs[@]}"
emit "INDEX_FILE=$index_name"

issues=""
issue_count=0
has_error=0
add_issue() { # severity type msg
  issues="${issues}  - SEVERITY=$1 TYPE=$2 MSG=$3"$'\n'
  issue_count=$((issue_count + 1))
  [ "$1" = "ERROR" ] && has_error=1
  return 0
}

if [ "${#adr_abs[@]}" -eq 0 ]; then
  emit "ADR_DIRS="
  emit "STATUS=OK"
  emit "ISSUE_COUNT=0"
  emit "=== END ADR INDEX GENERATION ==="
  exit 0
fi

adr_dirs_joined=""
for r in "${adr_rels[@]}"; do
  adr_dirs_joined="${adr_dirs_joined}${adr_dirs_joined:+$'\t'}${r}"
done
emit "ADR_DIRS=$adr_dirs_joined"

# --- Field extraction ---------------------------------------------------------
fm_field() { # <file> <field>
  head -50 "$1" | grep -m1 -i "^$2:" | sed 's/^[^:]*:[[:space:]]*//' | tr -d '\r'
}

adr_number() { # <basename>
  local base="$1" num
  num="$(printf '%s' "$base" | sed -nE 's/^0*([0-9]+)[-_].*/\1/p')"
  [ -n "$num" ] && printf '%d' "$((10#$num))"
}

adr_number_from_frontmatter() { # <file>
  local num
  num="$(head -50 "$1" | tr -d '\r' | sed -nE 's/^[Ii][Dd]:[[:space:]]*[Aa][Dd][Rr][-_ ]?0*([0-9]+).*/\1/p' | head -1)"
  [ -n "$num" ] && printf '%d' "$((10#$num))"
}

adr_title() { # <file>
  local f="$1" t
  t="$(fm_field "$f" title)"
  if [ -z "$t" ]; then
    t="$(grep -m1 -E '^#[[:space:]]+' "$f" 2>/dev/null | sed -E 's/^#+[[:space:]]*//; s/^[Aa][Dd][Rr][-_ ]?[0-9]+[[:space:]]*:[[:space:]]*//' | tr -d '\r')"
  fi
  [ -z "$t" ] && t="$(basename "$f" .md)"
  # Escape table-breaking pipes.
  printf '%s' "$t" | sed 's/|/\\|/g'
}

# --- Marker helpers -----------------------------------------------------------
has_markers() { # <file>
  grep -qF "$MARKER_START" "$1" 2>/dev/null && grep -qF "$MARKER_END" "$1" 2>/dev/null
}

extract_block() { # <file> -> the lines strictly between the markers
  awk -v s="$MARKER_START" -v e="$MARKER_END" '
    index($0, s) { inb = 1; next }
    index($0, e) { inb = 0; next }
    inb { print }
  ' "$1"
}

replace_block() { # <file> <block-file> -> new content on stdout
  awk -v s="$MARKER_START" -v e="$MARKER_END" -v bf="$2" '
    index($0, s) { print; while ((getline line < bf) > 0) print line; close(bf); inb = 1; next }
    index($0, e) { inb = 0; print; next }
    inb { next }
    { print }
  ' "$1"
}

TMP_DIR="$(mktemp -d)" || exit 1
[ -n "$TMP_DIR" ] || exit 1
trap 'rm -rf "$TMP_DIR"' EXIT

total_rows=0
for i in "${!adr_abs[@]}"; do
  dir_abs="${adr_abs[$i]}"
  dir_rel="${adr_rels[$i]}"
  n=$((i + 1))
  emit "ADR_DIR_${n}=$dir_rel"

  # Collect "number<TAB>row" so ordering is numeric, not lexical.
  rows_file="$TMP_DIR/rows.$n"
  : > "$rows_file"
  adr_files=0
  for f in "$dir_abs"/*.md; do
    [ -e "$f" ] || continue
    base="$(basename "$f")"
    [ "$base" = "$index_name" ] && continue
    num="$(adr_number "$base")"
    [ -n "$num" ] || num="$(adr_number_from_frontmatter "$f")"
    [ -n "$num" ] || continue
    adr_files=$((adr_files + 1))
    adr_id="$(printf 'ADR-%04d' "$num")"
    adr_status="$(fm_field "$f" status)"
    [ -n "$adr_status" ] || adr_status="-"
    printf '%s\t| [%s](%s) | %s | %s |\n' \
      "$num" "$adr_id" "$base" "$(adr_title "$f")" "$adr_status" >> "$rows_file"
  done

  block_file="$TMP_DIR/block.$n"
  {
    printf '%s\n' "<!-- generated by /blueprint:adr-validate — regenerate with scripts/generate-adr-index.sh -->"
    printf '\n'
    printf '| ADR | Title | Status |\n'
    printf '| --- | ----- | ------ |\n'
    sort -n -k1,1 "$rows_file" | cut -f2-
  } > "$block_file"

  row_count="$(grep -c '^| \[ADR-' "$block_file" 2>/dev/null)"
  [ -n "$row_count" ] || row_count=0
  total_rows=$((total_rows + row_count))
  emit "ADR_DIR_${n}_ADR_COUNT=$adr_files"
  emit "ADR_DIR_${n}_ROW_COUNT=$row_count"

  index_path="$dir_abs/$index_name"

  if [ "$adr_files" -eq 0 ]; then
    emit "ADR_DIR_${n}_STATE=no_adrs"
    continue
  fi

  if [ ! -f "$index_path" ]; then
    if [ "$check_only" = true ]; then
      emit "ADR_DIR_${n}_STATE=index_absent"
      add_issue WARN adr_index_absent "no $index_name in $dir_rel — run generate-adr-index.sh to create it"
    else
      {
        printf '# Architecture Decision Records\n\n'
        printf '%s\n' "$MARKER_START"
        cat "$block_file"
        printf '%s\n' "$MARKER_END"
      } > "$index_path"
      emit "ADR_DIR_${n}_STATE=index_created"
    fi
    continue
  fi

  if ! has_markers "$index_path"; then
    if [ "$check_only" = true ]; then
      # A distinct, NON-fatal state: with no markers there is nothing to diff,
      # so reporting drift here would be a spurious failure.
      emit "ADR_DIR_${n}_STATE=markers_absent"
      add_issue WARN adr_index_markers_absent "$dir_rel/$index_name has no $MARKER_START / $MARKER_END markers — run generate-adr-index.sh to adopt them"
    else
      {
        cat "$index_path"
        printf '\n%s\n' "$MARKER_START"
        cat "$block_file"
        printf '%s\n' "$MARKER_END"
      } > "$TMP_DIR/new.$n"
      mv "$TMP_DIR/new.$n" "$index_path"
      emit "ADR_DIR_${n}_STATE=markers_inserted"
      add_issue WARN adr_index_markers_inserted "$dir_rel/$index_name gained a generated block; remove any hand-maintained table above it"
    fi
    continue
  fi

  on_disk="$(extract_block "$index_path")"
  generated="$(cat "$block_file")"
  if [ "$on_disk" = "$generated" ]; then
    if [ "$check_only" = true ]; then
      emit "ADR_DIR_${n}_STATE=in_sync"
    else
      emit "ADR_DIR_${n}_STATE=unchanged"
    fi
    continue
  fi

  if [ "$check_only" = true ]; then
    emit "ADR_DIR_${n}_STATE=drifted"
    add_issue ERROR adr_index_drift "$dir_rel/$index_name is out of date — run generate-adr-index.sh to regenerate ($adr_files ADRs)"
  else
    replace_block "$index_path" "$block_file" > "$TMP_DIR/new.$n"
    mv "$TMP_DIR/new.$n" "$index_path"
    emit "ADR_DIR_${n}_STATE=written"
  fi
done

emit "TOTAL_ROWS=$total_rows"

if [ "$has_error" -eq 1 ]; then
  gen_status="ERROR"
elif [ "$issue_count" -gt 0 ]; then
  gen_status="WARN"
else
  gen_status="OK"
fi
emit "STATUS=$gen_status"
emit "ISSUE_COUNT=$issue_count"
if [ "$issue_count" -gt 0 ]; then
  emit "ISSUES:"
  printf '%s' "$issues"
fi
emit "=== END ADR INDEX GENERATION ==="

[ "$has_error" -eq 1 ] && exit 1
exit 0
