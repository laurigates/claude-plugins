#!/usr/bin/env bash
# Bounded doc dependency sweep for blueprint-docs-currency (issue #2692).
#
# Given the staged diff, name the hand-written docs that may describe what the
# commit changes, so the author can update them in the SAME commit. It reports;
# it never edits. The bound is the point: a full-repo doc re-read is correct and
# never gets run, so this sweep stops at a stated cap.
#
# Rungs (one hop each; see "Stop rule" below):
#
#   <plugin>/skills/<skill>/...    -> <plugin>/README.md          (plugin_readme)
#   <plugin>/agents/<agent>.md        <plugin>/.claude-plugin/plugin.json
#   <plugin>/.claude-plugin/...                                   (plugin_manifest)
#                                     README.md, docs/PLUGIN-MAP.md,
#                                     .claude-plugin/marketplace.json (catalog)
#   <plugin>/<any other path>      -> <plugin>/README.md, plugin.json (no catalog)
#   .claude/rules/<rule>.md        -> CLAUDE.md / AGENTS.md       (rule_index)
#                                     every other tracked *.md that cites
#                                     `<rule>.md`                  (rule_backref)
#   anything else                  -> unmapped (counted, not swept)
#
# A plugin dir is a top-level dir named `*-plugin` or carrying
# `.claude-plugin/plugin.json`. The skill/plugin rung mirrors the staged-path
# derivation of the repo-root scripts/check-plugin-readme-currency.sh (dot-dirs
# skipped, set-vs-unset seam), which is not shipped with this plugin and so
# cannot be called from here. The catalog files are the three plugin-catalog
# surfaces that scripts/check-docs-index.sh (Checks 2-3, #1460) keeps in
# agreement; that script owns the skill/agent COUNT dimension, so this sweep
# names rows and never compares counts. The count-only d2 diagram is left to its
# Checks 4 and 6 for the same reason.
#
# Stop rule and cap:
#   - One hop. A candidate doc is never expanded into its own dependencies.
#   - Candidates are ordered plugin_readme, plugin_manifest, catalog,
#     rule_index, rule_backref, then by path. Candidates already staged are
#     covered and are counted, not examined. The first CANDIDATE_CAP unstaged
#     candidates are examined; the sweep then stops and reports the remainder
#     as one `cap_reached` finding with the count dropped. A cap hit means the
#     change is broad enough that a targeted sweep is the wrong tool.
#   - "Examined" means opened once to locate the entry lines that name the
#     change. The sweep opens no file outside the examined set. Discovery for
#     the rule rung is a single `git grep -l` over tracked Markdown, which is
#     git's own search and is not bounded by the cap; the cap bounds what the
#     sweep opens and what the author is asked to read.
#
# Output follows .claude/rules/structured-script-output.md: STATUS=WARN when at
# least one unstaged candidate or a cap hit is reported, STATUS=OK when there is
# nothing to review, STATUS=ERROR (exit 1) when the project is not a git work
# tree. WARN exits 0: the sweep is advisory.
#
# Usage:
#   docs-dependency-sweep.sh [--project-dir <path>] [--cap <N>]
#
#   --project-dir  Any path inside the repo to sweep (default: cwd). Resolved to
#                  the work-tree root, because staged paths are root-relative.
#   --cap          Upper bound on files examined (default 10; env
#                  DOCS_SWEEP_CAP). Must be a positive integer.
#
# Test seams:
#   DOCS_SWEEP_STAGED  Newline-separated staged paths, replacing
#                      `git diff --cached`. Gated on set-vs-unset, so an
#                      explicitly EMPTY value means "nothing staged" (the #2521
#                      lesson: an emptiness gate made that state inexpressible).
#   DOCS_SWEEP_TRACE   File that receives one line per file the sweep opens, so
#                      a test can prove it never reads outside the examined set.
set -uo pipefail

SECTION="DOCS DEPENDENCY SWEEP"
DEFAULT_CAP=10
CATALOG_FILES=(README.md docs/PLUGIN-MAP.md .claude-plugin/marketplace.json)

usage() {
  echo "Usage: docs-dependency-sweep.sh [--project-dir <path>] [--cap <N>]"
}

emit_error() {
  # emit_error <type> <msg> -- the one ERROR path; exits 1 per the contract.
  echo "=== ${SECTION} ==="
  echo "STATUS=ERROR"
  echo "ISSUE_COUNT=1"
  echo "ISSUES:"
  echo "  - SEVERITY=ERROR TYPE=$1 MSG=$2"
  echo "=== END ${SECTION} ==="
  exit 1
}

project_dir="$(pwd)"
cap="${DOCS_SWEEP_CAP:-$DEFAULT_CAP}"

while [ $# -gt 0 ]; do
  case "$1" in
    --project-dir)
      [ $# -ge 2 ] || { usage >&2; exit 2; }
      project_dir="$2"
      shift 2
      ;;
    --cap)
      [ $# -ge 2 ] || { usage >&2; exit 2; }
      cap="$2"
      shift 2
      ;;
    -h | --help)
      usage
      exit 0
      ;;
    *)
      echo "docs-dependency-sweep.sh: unknown argument: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

case "$cap" in
  '' | *[!0-9]*)
    echo "docs-dependency-sweep.sh: --cap must be a positive integer (got '${cap}')" >&2
    exit 2
    ;;
esac
cap=$((10#$cap))
if [ "$cap" -lt 1 ]; then
  echo "docs-dependency-sweep.sh: --cap must be a positive integer (got '${cap}')" >&2
  exit 2
fi

root="$(git -C "$project_dir" rev-parse --show-toplevel 2>/dev/null)" ||
  emit_error not_a_git_work_tree "${project_dir} is not inside a git work tree; staged paths cannot be read"

if [ -n "${DOCS_SWEEP_STAGED+set}" ]; then
  staged_raw="$DOCS_SWEEP_STAGED"
else
  staged_raw="$(git -C "$root" diff --cached --name-only --no-renames 2>/dev/null)" ||
    emit_error staged_diff_failed "git diff --cached failed in ${root}"
fi

declare -A staged=()
staged_list=()
while IFS= read -r staged_path; do
  [ -n "$staged_path" ] || continue
  [ -z "${staged[$staged_path]:-}" ] || continue
  staged["$staged_path"]=1
  staged_list+=("$staged_path")
done <<< "$staged_raw"

# --- candidate derivation (structural: stats files, never opens them) --------

declare -A cand_kind=() cand_source=() cand_sources=() cand_keys=() cand_seen=()

kind_rank() {
  case "$1" in
    plugin_readme) echo 1 ;;
    plugin_manifest) echo 2 ;;
    catalog) echo 3 ;;
    rule_index) echo 4 ;;
    *) echo 5 ;;
  esac
}

ere_escape() {
  printf '%s' "$1" | sed 's/[][\.*^$+?(){}|]/\\&/g'
}

# add_candidate <doc> <kind> <source> [ERE key...]
add_candidate() {
  local doc="$1" kind="$2" source="$3"
  shift 3
  [ -f "${root}/${doc}" ] || return 0
  if [ -z "${cand_kind[$doc]:-}" ]; then
    cand_kind["$doc"]="$kind"
    cand_source["$doc"]="$source"
    cand_sources["$doc"]=0
  elif [ "$(kind_rank "$kind")" -lt "$(kind_rank "${cand_kind[$doc]}")" ]; then
    cand_kind["$doc"]="$kind"
  fi
  if [ -z "${cand_seen[$doc|$source]:-}" ]; then
    cand_seen["$doc|$source"]=1
    cand_sources["$doc"]=$((cand_sources[$doc] + 1))
  fi
  local key
  for key in "$@"; do
    [ -n "$key" ] && cand_keys["$doc"]+="${key}"$'\n'
  done
}

mapped=0
unmapped=0
for staged_path in "${staged_list[@]}"; do
  top="${staged_path%%/*}"
  if [ "$staged_path" != "$top" ] && [[ "$top" != .* ]] &&
    { [[ "$top" == *-plugin ]] || [ -f "${root}/${top}/.claude-plugin/plugin.json" ]; }; then
    rest="${staged_path#"$top"/}"
    case "$rest" in
      README.md | CHANGELOG.md)
        # A doc target, not a source.
        unmapped=$((unmapped + 1))
        continue
        ;;
    esac
    sub="${rest%%/*}"
    short="${top%-plugin}"
    keys=()
    advertised=false
    case "$sub" in
      skills)
        name="${rest#skills/}"
        name="${name%%/*}"
        keys=("$(ere_escape "$name")" "$(ere_escape "/${short}:${name#"${short}"-}")")
        advertised=true
        ;;
      agents)
        name="${rest#agents/}"
        name="${name%%/*}"
        name="${name%.md}"
        keys=("$(ere_escape "$name")")
        advertised=true
        ;;
      .claude-plugin)
        advertised=true
        ;;
      *)
        keys=("$(ere_escape "${staged_path##*/}")")
        ;;
    esac
    add_candidate "${top}/README.md" plugin_readme "$staged_path" ${keys[@]+"${keys[@]}"}
    add_candidate "${top}/.claude-plugin/plugin.json" plugin_manifest "$staged_path" ${keys[@]+"${keys[@]}"}
    if [ "$advertised" = true ]; then
      for catalog in "${CATALOG_FILES[@]}"; do
        add_candidate "$catalog" catalog "$staged_path" "$(ere_escape "$top")" ${keys[@]+"${keys[@]}"}
      done
    fi
    mapped=$((mapped + 1))
  elif [[ "$staged_path" == .claude/rules/*.md ]]; then
    rule_re="(^|[^A-Za-z0-9_.-])$(ere_escape "${staged_path##*/}")"
    while IFS= read -r ref; do
      if [ -z "$ref" ] || [ "$ref" = "$staged_path" ]; then
        continue
      fi
      kind=rule_backref
      case "$ref" in CLAUDE.md | AGENTS.md) kind=rule_index ;; esac
      add_candidate "$ref" "$kind" "$staged_path" "$rule_re"
    done < <(git -C "$root" grep -l -I -E -e "$rule_re" -- '*.md' ':(exclude)*CHANGELOG.md' 2>/dev/null)
    mapped=$((mapped + 1))
  else
    unmapped=$((unmapped + 1))
  fi
done

# --- bounded examination ------------------------------------------------------

entry_lines=""
entry_count=0
# examine <doc> -- the ONLY place the sweep reads a file's content.
examine() {
  local doc="$1" key nums
  local -a args=()
  [ -z "${DOCS_SWEEP_TRACE:-}" ] || printf '%s\n' "$doc" >> "$DOCS_SWEEP_TRACE"
  while IFS= read -r key; do
    [ -n "$key" ] && args+=(-e "$key")
  done <<< "${cand_keys[$doc]:-}"
  if [ ${#args[@]} -eq 0 ]; then
    entry_lines="-"
    entry_count=0
    return 0
  fi
  nums="$(grep -hnE "${args[@]}" -- "${root}/${doc}" 2>/dev/null | cut -d: -f1)"
  if [ -z "$nums" ]; then
    entry_lines="none"
    entry_count=0
  else
    entry_count="$(printf '%s\n' "$nums" | wc -l | tr -d ' ')"
    entry_lines="$(printf '%s\n' "$nums" | head -n 5 | paste -sd, -)"
  fi
}

ordered_docs=()
if [ ${#cand_kind[@]} -gt 0 ]; then
  while IFS=$'\t' read -r _rank doc; do
    ordered_docs+=("$doc")
  done < <(for doc in "${!cand_kind[@]}"; do
    printf '%s\t%s\n' "$(kind_rank "${cand_kind[$doc]}")" "$doc"
  done | LC_ALL=C sort -t $'\t' -k1,1n -k2,2)
fi

covered=0
examined=0
dropped=0
first_dropped=""
review_rows=()
for doc in ${ordered_docs[@]+"${ordered_docs[@]}"}; do
  if [ -n "${staged[$doc]:-}" ]; then
    covered=$((covered + 1))
    continue
  fi
  if [ "$examined" -ge "$cap" ]; then
    dropped=$((dropped + 1))
    [ -n "$first_dropped" ] || first_dropped="$doc"
    continue
  fi
  examine "$doc"
  examined=$((examined + 1))
  review_rows+=("  - SEVERITY=WARN TYPE=review_candidate DOC=${doc} KIND=${cand_kind[$doc]} SOURCE=${cand_source[$doc]} SOURCES=${cand_sources[$doc]} ENTRY_LINES=${entry_lines} ENTRY_COUNT=${entry_count} MSG=may describe the staged change; update it in this commit or confirm it is unaffected")
done

issue_rows=()
if [ "$dropped" -gt 0 ]; then
  issue_rows+=("  - SEVERITY=WARN TYPE=cap_reached CAP=${cap} DROPPED=${dropped} FIRST_DROPPED=${first_dropped} MSG=${dropped} candidate doc(s) past the cap were not examined; the change is broad, so review them by hand or re-run with a larger --cap")
fi
issue_rows+=(${review_rows[@]+"${review_rows[@]}"})

issue_count=${#issue_rows[@]}
status=OK
[ "$issue_count" -eq 0 ] || status=WARN

echo "=== ${SECTION} ==="
echo "STAGED_PATHS=${#staged_list[@]}"
echo "MAPPED_PATHS=${mapped}"
echo "UNMAPPED_PATHS=${unmapped}"
echo "CANDIDATE_CAP=${cap}"
echo "CANDIDATES_TOTAL=${#ordered_docs[@]}"
echo "CANDIDATES_STAGED=${covered}"
echo "FILES_EXAMINED=${examined}"
echo "CANDIDATES_DROPPED=${dropped}"
echo "STATUS=${status}"
echo "ISSUE_COUNT=${issue_count}"
if [ "$issue_count" -gt 0 ]; then
  echo "ISSUES:"
  printf '%s\n' "${issue_rows[@]}"
fi
echo "=== END ${SECTION} ==="
exit 0
