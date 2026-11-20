#!/usr/bin/env bash
# prefetch-heads.sh — make every PR head commit and base branch in a roster (or
# one review run) present in the local clone, before any agent reads it.
#
# The pr-review finders read git objects only (diff, show) and never fetch, so
# concurrent agents never race on FETCH_HEAD. This script is the one fetch.
#
# Usage:
#   prefetch-heads.sh [--root DIR] <roster-or-run.json>
#
#   --root DIR  the local clone (default: the current directory). Its origin
#               must point at the roster's repo; a clone of another repository
#               is refused.
#
# Input: any JSON with .prs[] rows carrying number, head_sha and base
# (list-sweep-prs.sh output, or one plan-review-runs.sh runs[] element), and a
# top-level .repo "owner/name" (a run element has none; then the check is
# skipped unless --repo is given).
#
# Per run: one `git fetch origin <base>...` for the bases, SHAs fetched by id in
# chunks of 20, then `+refs/pull/<n>/head:refs/pr-sweep/<n>` for any SHA still
# missing. A SHA missing after both is an ERROR row; the caller must not review
# that PR.
#
# Exit: 0 OK, 1 ERROR, 2 usage.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=SCRIPTDIR/lib/summary.sh disable=SC1091
source "$SCRIPT_DIR/lib/summary.sh"

usage() {
  echo "Usage: prefetch-heads.sh [--root DIR] [--repo OWNER/NAME] <roster-or-run.json>" >&2
  exit 2
}

root="."
repo_arg=""
positional=()
while [ $# -gt 0 ]; do
  case "$1" in
    --root) [ $# -ge 2 ] || usage; root="$2"; shift 2 ;;
    --repo) [ $# -ge 2 ] || usage; repo_arg="$2"; shift 2 ;;
    -h|--help) usage ;;
    --) shift; while [ $# -gt 0 ]; do positional+=("$1"); shift; done ;;
    -*) echo "Unknown flag: $1" >&2; exit 2 ;;
    *) positional+=("$1"); shift ;;
  esac
done
[ "${#positional[@]}" -eq 1 ] || usage
input="${positional[0]}"

summary_init "PR SWEEP PREFETCH"
fail() {
  summary_issue ERROR "$1" "$2"
  summary_emit
  exit 1
}

command -v jq >/dev/null 2>&1 || fail missing_tool "jq is required but not installed"
command -v git >/dev/null 2>&1 || fail missing_tool "git is required but not installed"
[ -f "$input" ] || fail missing_input "input not found: $input"
jq -e '.prs | type == "array"' "$input" >/dev/null 2>&1 || fail bad_input "input has no .prs array: $input"
{ [ -n "$root" ] && [ -d "$root" ]; } || fail bad_root "root is not a directory: $root"
git -C "$root" rev-parse --git-dir >/dev/null 2>&1 || fail bad_root "root is not a git clone: $root"

repo="${repo_arg:-$(jq -r '.repo // ""' "$input")}"
origin=$(git -C "$root" remote get-url origin 2>/dev/null || true)
[ -n "$origin" ] || fail no_origin "root has no origin remote: $root"
if [ -n "$repo" ]; then
  # github.com/<owner>/<name>, with or without .git, over https or ssh; a local
  # path origin (tests, mirrors) must end in <name> or <name>.git.
  origin_lc=$(printf '%s' "$origin" | tr '[:upper:]' '[:lower:]')
  repo_lc=$(printf '%s' "$repo" | tr '[:upper:]' '[:lower:]')
  origin_ok=false
  case "$origin_lc" in
    *"github.com/$repo_lc" | *"github.com/$repo_lc.git" | *"github.com:$repo_lc" | *"github.com:$repo_lc.git") origin_ok=true ;;
    *github.com*) ;;
    *"/${repo_lc##*/}" | *"/${repo_lc##*/}.git") origin_ok=true ;;
  esac
  $origin_ok || fail origin_mismatch "origin $origin is not $repo; pass the clone of $repo as --root"
fi

mapfile -t bases < <(jq -r '[.prs[].base // empty] | unique | .[]' "$input")
mapfile -t rows < <(jq -r '.prs[] | "\(.number) \(.head_sha // "")"' "$input")
summary_kv ROOT "$root"
summary_kv REPO "$repo"
summary_kv PRS "${#rows[@]}"
summary_kv BASES "$(IFS=,; echo "${bases[*]:-}")"

if [ "${#bases[@]}" -gt 0 ]; then
  git -C "$root" fetch -q origin "${bases[@]}" >/dev/null 2>&1 ||
    summary_issue ERROR base_fetch_failed "git fetch origin ${bases[*]} failed"
fi

have() { git -C "$root" cat-file -e "${1}^{commit}" >/dev/null 2>&1; }

missing=()
for row in "${rows[@]}"; do
  sha="${row#* }"
  [[ "$sha" =~ ^[0-9a-f]{40}$ ]] || { summary_issue ERROR bad_head_sha "PR ${row%% *} has no 40-hex head_sha"; continue; }
  have "$sha" || missing+=("$row")
done

# Fetch by id, 20 at a time; a server that refuses one id fails the batch, so
# the per-PR fallback below catches whatever is still absent.
for ((i = 0; i < ${#missing[@]}; i += 20)); do
  batch=()
  for row in "${missing[@]:i:20}"; do batch+=("${row#* }"); done
  git -C "$root" fetch -q origin "${batch[@]}" >/dev/null 2>&1 || true
done

fetched=0
absent=()
for row in "${missing[@]}"; do
  n="${row%% *}"
  sha="${row#* }"
  if ! have "$sha"; then
    git -C "$root" fetch -q origin "+refs/pull/${n}/head:refs/pr-sweep/${n}" >/dev/null 2>&1 || true
  fi
  if have "$sha"; then fetched=$((fetched + 1)); else absent+=("$n"); fi
done

summary_kv FETCHED "$fetched"
summary_kv ALREADY_PRESENT "$(( ${#rows[@]} - ${#missing[@]} ))"
summary_kv MISSING "$(IFS=,; echo "${absent[*]:-}")"
[ "${#absent[@]}" -gt 0 ] && summary_issue ERROR head_missing "head commit not fetchable for PR(s) $(IFS=,; echo "${absent[*]}"); do not review them"

summary_emit
[ "$(summary_status)" = "ERROR" ] && exit 1
exit 0
