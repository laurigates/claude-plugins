#!/usr/bin/env bash
# macos-disk-usage — usual-suspects fast-path scan.
#
# Extracts the mechanical "where does disk usually go" step of the
# macos-disk-usage skill into a deterministic artifact. Reads the public
# catalog (suspects.tsv) of KNOWN reclaim targets — dev caches, build-artifact
# dirs, VM images — du's the ones that exist on THIS machine, and emits a ranked
# rollup with the cleanup command and safety tier already attached. It also
# surfaces big directories NOT in the catalog, so real findings feed back into
# the catalog (grow it via PR, scrubbed to patterns).
#
# The agent still owns the judgment the catalog can't encode: reading the honest
# df/APFS/snapshot picture (Step 1), deciding which `decision`/`userdata` items
# to actually delete, and interpreting a `Capacity %` that lies. This script only
# does the repeatable measurement.
#
# The du/find core is portable BY DESIGN so the regression test runs offline on
# Linux CI against a PLANTED fixture home via the injectable seams:
#   --home-dir <path>   base for catalog `path` targets + default scan root
#   --root <path>       root(s) to scan for build-artifact dirs (repeatable)
#   --catalog <file>    catalog TSV (default: sibling suspects.tsv)
#   --min-mb <n>        unclassified-dir reporting threshold (default 500)
#   --top <n>           rows in the ranked table (default 25)
# The macOS-specific suspects are DATA (catalog rows); on Linux they simply don't
# exist and are skipped, so there is no Darwin guard here (the SKILL enforces it).
#
# Emits the structured KEY=value / STATUS= convention
# (.claude/rules/structured-script-output.md). Exit 0 on a clean run.
set -uo pipefail

home_dir=""
catalog=""
min_mb=500
top_n=25
roots=()

while [ $# -gt 0 ]; do
  case "$1" in
    --home-dir) home_dir="$2"; shift 2 ;;
    --root)     roots+=("$2"); shift 2 ;;
    --catalog)  catalog="$2"; shift 2 ;;
    --min-mb)   min_mb="$2"; shift 2 ;;
    --top)      top_n="$2"; shift 2 ;;
    *) shift ;;
  esac
done

: "${home_dir:=$HOME}"
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
: "${catalog:=${script_dir}/suspects.tsv}"
[ "${#roots[@]}" -gt 0 ] || roots=("$home_dir")
min_kb=$(( min_mb * 1024 ))

# KB -> human (input already in KB; 1 unit == 1 KiB).
hsize() {
  awk -v k="$1" 'BEGIN{
    u="KMGT"; s=k; i=1;
    while (s>=1024 && i<4) { s/=1024; i++ }
    if (i==1) printf "%d%s", s, substr(u,i,1);
    else      printf "%.1f%s", s, substr(u,i,1)
  }'
}

# Accumulators for the ranked table + tier totals. Newline-delimited
# "size_kb<TAB>tier<TAB>id<TAB>path" records; paths never contain a tab.
results=""
reported=""              # newline-delimited reported paths, for unclassified exclusion
safe_kb=0; decision_kb=0; userdata_kb=0

record() {  # size_kb tier id path
  results+="$1	$2	$3	$4
"
  reported+="$4
"
  case "$2" in
    safe)     safe_kb=$(( safe_kb + $1 )) ;;
    decision) decision_kb=$(( decision_kb + $1 )) ;;
    userdata) userdata_kb=$(( userdata_kb + $1 )) ;;
  esac
}

echo "=== MACOS DISK SUSPECTS SCAN ==="
echo "HOME_DIR=$home_dir"
echo "ROOTS=${roots[*]}"
echo "CATALOG=$catalog"
echo "MIN_MB=$min_mb"

if [ ! -f "$catalog" ]; then
  echo "STATUS=ERROR_NO_CATALOG"
  exit 1
fi

# --- Pass 1: fixed-path suspects -------------------------------------------
echo "--- FIXED-PATH SUSPECTS ---"
# shellcheck disable=SC2034  # regen,note are catalog columns for humans, not read here
while IFS=$'\t' read -r kind id target marker tier command regen note; do
  case "$kind" in \#*|kind|"") continue ;; esac
  [ "$kind" = "path" ] || continue
  case "$target" in
    /*) p="$target" ;;
    *)  p="$home_dir/$target" ;;
  esac
  [ -e "$p" ] || continue
  size=$(du -skx "$p" 2>/dev/null | awk 'NR==1{print $1}')
  [ -n "${size:-}" ] || continue
  cmd=${command//\{dir\}/$p}
  echo "SUSPECT id=$id tier=$tier size_kb=$size path=$p cmd=\"$cmd\""
  record "$size" "$tier" "$id" "$p"
done < "$catalog"

# --- Pass 2: build-artifact dirs under the scan roots ----------------------
echo "--- BUILD-ARTIFACT DIRS ---"
# shellcheck disable=SC2034  # regen,note are catalog columns for humans, not read here
while IFS=$'\t' read -r kind id target marker tier command regen note; do
  case "$kind" in \#*|kind|"") continue ;; esac
  [ "$kind" = "dir" ] || continue
  for root in "${roots[@]}"; do
    [ -d "$root" ] || continue
    while IFS= read -r d; do
      [ -n "$d" ] || continue
      parent=$(dirname "$d")
      if [ "$marker" != "-" ] && [ ! -e "$parent/$marker" ]; then
        continue
      fi
      size=$(du -skx "$d" 2>/dev/null | awk 'NR==1{print $1}')
      [ -n "${size:-}" ] || continue
      cmd=${command//\{dir\}/$d}
      cmd=${cmd//\{parent\}/$parent}
      echo "SUSPECT id=$id tier=$tier size_kb=$size path=$d cmd=\"$cmd\""
      record "$size" "$tier" "$id" "$d"
    done < <(find "$root" -type d -name "$target" -prune -print 2>/dev/null)
  done
done < "$catalog"

# --- Pass 3: unclassified big dirs (feedback loop) -------------------------
# A dir is "covered" when it equals, contains, or sits inside a reported path,
# so known suspects don't reappear here as noise. What survives is a candidate
# for a new catalog entry.
echo "--- UNCLASSIFIED (>= ${min_mb}M, not in catalog) ---"
is_covered() {  # candidate
  local c="$1" r
  while IFS= read -r r; do
    [ -n "$r" ] || continue
    [ "$c" = "$r" ] && return 0
    case "$c" in "$r"/*) return 0 ;; esac   # candidate inside a reported path
    case "$r" in "$c"/*) return 0 ;; esac   # candidate contains a reported path
  done <<EOF
$reported
EOF
  return 1
}
unclassified=""
for root in "${roots[@]}"; do
  [ -d "$root" ] || continue
  while IFS=$'\t' read -r kb path; do
    [ -n "${kb:-}" ] || continue
    [ "$kb" -ge "$min_kb" ] 2>/dev/null || continue
    [ "$path" = "$root" ] && continue
    is_covered "$path" && continue
    unclassified+="$kb	$path
"
  done < <(du -kx -d 2 "$root" 2>/dev/null)
done
if [ -n "$unclassified" ]; then
  # De-nest: biggest first, then skip any dir that is an ancestor or descendant
  # of one already emitted, so a parent and its child don't both appear.
  emitted=""
  count=0
  while IFS=$'\t' read -r kb path; do
    [ -n "${kb:-}" ] || continue
    [ "$count" -ge 15 ] && break
    skip=0
    while IFS= read -r e; do
      [ -n "$e" ] || continue
      case "$path" in "$e"/*) skip=1; break ;; esac
      case "$e" in "$path"/*) skip=1; break ;; esac
    done <<EOF
$emitted
EOF
    [ "$skip" -eq 1 ] && continue
    echo "UNKNOWN size_kb=$kb path=$path"
    emitted+="$path
"
    count=$(( count + 1 ))
  done < <(printf '%s' "$unclassified" | sort -rn)
else
  echo "UNKNOWN none"
fi

# --- Ranked table + tier totals --------------------------------------------
echo "--- RANKED (top ${top_n} by size) ---"
if [ -n "$results" ]; then
  rank=0
  printf '%s' "$results" | sort -rn | head -n "$top_n" | while IFS=$'\t' read -r kb tier id path; do
    [ -n "${kb:-}" ] || continue
    rank=$(( rank + 1 ))
    printf '%d\t%s\t%-8s\t%s\t%s\n' "$rank" "$(hsize "$kb")" "$tier" "$id" "$path"
  done
else
  echo "(no known suspects present)"
fi

echo "--- TIER TOTALS ---"
echo "TIER_SAFE_KB=$safe_kb"
echo "TIER_DECISION_KB=$decision_kb"
echo "TIER_USERDATA_KB=$userdata_kb"
echo "RECLAIMABLE_SAFE=$(hsize "$safe_kb")"
echo "RECLAIMABLE_DECISION=$(hsize "$decision_kb")"
echo "STATUS=OK"
