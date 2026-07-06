#!/usr/bin/env bash
# shellcheck disable=SC2034  # file-level: lineno/lang are positional read fields required to reach the trailing `line` field
# Version-pin coverage guard (.claude/rules/version-pinning.md).
#
# Every executable version pin in skill markdown — GitHub Action refs (uses:),
# Docker base images (FROM), service/container images (image:), and pre-commit
# revisions (rev:) — should be a shape Renovate's customManagers can see and
# keep fresh. This guard fails when an executable pin is version-shaped but does
# NOT match a managed form (so Renovate would silently skip it and the pin would
# rot). It deliberately does NOT demand SHA pins: tag form is "covered" too, so
# the guard never deadlocks against Renovate's own digest-pinning first run.
#
# Only fenced code blocks are scanned, so illustrative version numbers in prose
# tables are ignored by design (see the "illustrative vs. managed" table in the
# rule). Fence detection comes from a real markdown parse (tree-sitter) via the
# shared scripts/lib/extract-md-elements.py helper — NOT a hand-rolled ``` toggle
# (that state machine shipped bug #1492).
#
# Emits the structured KEY=value / STATUS= convention
# (.claude/rules/structured-script-output.md).
#
# Usage:
#   check-version-pin-coverage.sh [--project-dir <path>] [--strict]
#
#   --project-dir   Repo root to scan (default: git toplevel, else cwd)
#   --strict        Exit 1 when an ERROR-severity pin is found (default: exit 0)
set -uo pipefail

proj_dir=""
strict=false

while [ $# -gt 0 ]; do
  case "$1" in
    --project-dir) proj_dir="$2"; shift 2 ;;
    --strict) strict=true; shift ;;
    *) shift ;;
  esac
done

if [ -z "$proj_dir" ]; then
  proj_dir="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
fi

issue_count=0
declare -a issues=()
files_scanned=0
uses_covered=0
from_covered=0
image_covered=0
rev_covered=0

add_issue() {
  # add_issue <severity> <type> <message>
  issues+=("  - SEVERITY=$1 TYPE=$2 MSG=$3")
  issue_count=$((issue_count + 1))
}

# Managed-form predicates (mirror the renovate.json customManager regexes).
is_managed_uses_ref() {
  # $1 = the text after "uses: " up to end of line
  local rest="$1"
  # SHA pin + version comment:  owner/repo@<40hex> # vX.Y.Z
  [[ "$rest" =~ @[0-9a-f]{40}[\"\'\ ].*#[[:space:]]*v?[0-9] ]] && return 0
  [[ "$rest" =~ @[0-9a-f]{40}([[:space:]]+#[[:space:]]*v?[0-9]) ]] && return 0
  # Tag form: @vX...  or  @<digits>.<...>  (needs a dot to avoid matching a SHA)
  [[ "$rest" =~ @v[0-9] ]] && return 0
  [[ "$rest" =~ @[0-9][0-9A-Za-z._+-]*\.[0-9A-Za-z._+-]+ ]] && return 0
  return 1
}

is_floating_or_local_ref() {
  # Floating tags and local/non-pinned refs are intentionally out of scope.
  local rest="$1"
  [[ "$rest" =~ @(main|master|stable|nightly|latest|HEAD)([[:space:]]|$|\") ]] && return 0
  [[ "$rest" =~ uses:[[:space:]]+\.?/ ]] && return 0       # local action ./path
  [[ "$rest" =~ uses:[[:space:]]+docker:// ]] && return 0  # docker:// ref
  return 1
}

is_version_shaped_ref() {
  # Looks like a deliberate version pin (so an unmanaged one is a real gap).
  local rest="$1"
  [[ "$rest" =~ @v[0-9] ]] && return 0
  [[ "$rest" =~ @[0-9] ]] && return 0
  [[ "$rest" =~ @[0-9a-f]{40} ]] && return 0
  return 1
}

# Discover files to scan. Prune agent worktree copies (.claude/worktrees/*) —
# they are full repo checkouts created by concurrently-running isolated agents,
# so descending into them re-scans every skill file N× and litters WARN output
# with their paths (#1492). The guard only ever audits the real tree.
declare -a scan_files=()
while IFS= read -r -d '' file; do
  scan_files+=("$file")
done < <(find "$proj_dir" -path '*/.claude/worktrees/*' -prune -o \
           -path '*/skills/*' -name '*.md' -type f -print0 2>/dev/null)
files_scanned=${#scan_files[@]}

# Fence-awareness comes from a real markdown parse (tree-sitter via the shared
# scripts/lib/extract-md-elements.py helper), replacing the hand-rolled ``` /
# ~~~ toggle state machine that shipped bug #1492. The helper emits one
# `fence_line` record per raw source line INSIDE a fenced code block:
#   fence_line<TAB>file<TAB>lineno<TAB>language<TAB>text
# so this loop only ever sees lines a correct CommonMark/GFM parse considers
# fenced. Illustrative version numbers in prose tables are never fenced, so they
# are excluded by construction (the "illustrative vs. managed" rule).
if [ "$files_scanned" -gt 0 ]; then
  script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  helper="$script_dir/lib/extract-md-elements.py"
  if ! command -v uv >/dev/null 2>&1; then
    echo "check-version-pin-coverage: 'uv' not found on PATH; cannot parse markdown structure" >&2
    echo "  (the fence-aware scan uses scripts/lib/extract-md-elements.py via 'uv run')" >&2
    exit 2
  fi
  prev_file=""
  last_repo=""
  rel=""
  while IFS=$'\t' read -r rectype file lineno lang line; do
    [ "$rectype" = "fence_line" ] || continue
    if [ "$file" != "$prev_file" ]; then
      prev_file="$file"
      last_repo=""
      rel="${file#"$proj_dir"/}"
    fi

    # --- GitHub Action refs ---------------------------------------------------
    if [[ "$line" =~ uses:[[:space:]]+[^[:space:]]+@ ]]; then
      if is_floating_or_local_ref "$line"; then
        :  # intentionally unpinned
      elif is_managed_uses_ref "$line"; then
        uses_covered=$((uses_covered + 1))
      elif is_version_shaped_ref "$line"; then
        add_issue ERROR uses_uncovered \
          "$rel: version-shaped 'uses:' ref not in a Renovate-managed form (use @vX.Y.Z tag or @<sha> # vX.Y.Z): ${line#"${line%%uses:*}"}"
      fi
    fi

    # --- Docker base images ---------------------------------------------------
    if [[ "$line" =~ ^[[:space:]]*FROM[[:space:]]+[^[:space:]]+:[^[:space:]@]+ ]]; then
      from_covered=$((from_covered + 1))
    fi

    # --- Service/container images --------------------------------------------
    if [[ "$line" =~ image:[[:space:]]+[\"\']?[^[:space:]\"\']+:[^[:space:]@\"\']+ ]]; then
      image_covered=$((image_covered + 1))
    fi

    # --- pre-commit repo + rev -----------------------------------------------
    if [[ "$line" =~ repo:[[:space:]]+(https://)?github\.com/ ]]; then
      last_repo="github"
    elif [[ "$line" =~ repo:[[:space:]]+ ]]; then
      last_repo="other"
    fi
    if [[ "$line" =~ ^[[:space:]]*rev:[[:space:]]+[^[:space:]]+ ]]; then
      if [ "$last_repo" = "github" ]; then
        rev_covered=$((rev_covered + 1))
      elif [ "$last_repo" = "other" ]; then
        add_issue WARN rev_non_github \
          "$rel: pre-commit 'rev:' under a non-github.com repo — Renovate github-tags cannot manage it"
      fi
      last_repo=""
    fi

    # --- Known-unmanaged version surfaces (informational) --------------------
    if [[ "$line" =~ (node-version|python-version|go-version|ruby-version):[[:space:]]+[\"\']?[0-9] ]]; then
      add_issue WARN runtime_version_unmanaged \
        "$rel: runtime-version selector is not a Renovate-managed surface (illustrative only): ${line#"${line%%[!  ]*}"}"
    fi
    if [[ "$line" =~ additional_dependencies:.*@[0-9] ]]; then
      add_issue WARN npm_in_precommit_unmanaged \
        "$rel: pinned npm dep in additional_dependencies is out of scope for v1 (see version-pinning.md)"
    fi
  done < <(printf '%s\n' "${scan_files[@]}" \
             | uv run --quiet "$helper" --types fence_line --files-from - 2>/dev/null)
fi

# --- Status -------------------------------------------------------------------
overall_status="OK"
exit_severity=0
for line in "${issues[@]:-}"; do
  case "$line" in
    *SEVERITY=ERROR*) overall_status="ERROR"; exit_severity=1 ;;
  esac
done
if [ "$overall_status" = "OK" ] && [ "$issue_count" -gt 0 ]; then
  overall_status="WARN"
fi

# --- Output -------------------------------------------------------------------
echo "=== VERSION PIN COVERAGE ==="
echo "FILES_SCANNED=$files_scanned"
echo "USES_COVERED=$uses_covered"
echo "FROM_COVERED=$from_covered"
echo "IMAGE_COVERED=$image_covered"
echo "REV_COVERED=$rev_covered"
echo "STATUS=$overall_status"
echo "ISSUE_COUNT=$issue_count"
if [ "$issue_count" -gt 0 ]; then
  echo "ISSUES:"
  printf '%s\n' "${issues[@]}"
fi
echo "=== END VERSION PIN COVERAGE ==="

if [ "$strict" = true ]; then
  exit "$exit_severity"
fi
exit 0
