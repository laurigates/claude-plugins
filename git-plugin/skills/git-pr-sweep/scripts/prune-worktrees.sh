#!/usr/bin/env bash
# prune-worktrees.sh — the sweep's worktree clean-up: `git worktree prune` on the
# clone, then list the linked worktrees still registered under its worktrees dir.
#
# Usage:
#   prune-worktrees.sh --root DIR [--worktrees DIR]
#
#   --root DIR       the local clone the sweep ran against (required)
#   --worktrees DIR  where the sweep's agents made worktrees
#                    (default: <root>/.claude/worktrees)
#
# A script rather than `git -C <root> worktree prune` in SKILL.md: a skill grant
# for that command needs a wildcard before the subcommand, and such a grant also
# pre-approves `git -C <x> -c alias.worktree=... worktree prune`.
#
# prune drops only entries whose directory is already gone, so it never touches
# a live worktree. The script removes nothing itself and never forces anything;
# each WORKTREE_<i>= line is a worktree that still exists, for the caller to
# remove with `git -C <root> worktree remove <path>` or leave for its owner.
#
# Exit: 0 OK (remaining worktrees are a WARN, not an error), 1 ERROR, 2 usage.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=SCRIPTDIR/lib/summary.sh disable=SC1091
source "$SCRIPT_DIR/lib/summary.sh"

usage() {
  echo "Usage: prune-worktrees.sh --root DIR [--worktrees DIR]" >&2
  exit 2
}

root=""
wt_dir=""
while [ $# -gt 0 ]; do
  case "$1" in
    --root) [ $# -ge 2 ] || usage; root="$2"; shift 2 ;;
    --worktrees) [ $# -ge 2 ] || usage; wt_dir="$2"; shift 2 ;;
    -h|--help) usage ;;
    *) echo "Unknown argument: $1" >&2; exit 2 ;;
  esac
done
[ -n "$root" ] || usage

summary_init "PR SWEEP PRUNE"
fail() {
  summary_issue ERROR "$1" "$2"
  summary_emit
  exit 1
}

command -v git >/dev/null 2>&1 || fail missing_tool "git is required but not installed"
[ -d "$root" ] || fail bad_root "root is not a directory: $root"
git -C "$root" rev-parse --git-dir >/dev/null 2>&1 || fail bad_root "root is not a git clone: $root"
root=$(cd -P -- "$root" && pwd -P) || fail bad_root "cannot resolve root: $root"
wt_dir="${wt_dir:-$root/.claude/worktrees}"
# Compare resolved paths: git lists worktrees by their real path.
[ -d "$wt_dir" ] && wt_dir=$(cd -P -- "$wt_dir" && pwd -P)

before=$(git -C "$root" worktree list --porcelain | grep -c '^worktree ')
git -C "$root" worktree prune >/dev/null 2>&1 || fail prune_failed "git -C $root worktree prune failed"
mapfile -t left < <(git -C "$root" worktree list --porcelain | sed -n 's/^worktree //p' | grep -F -- "$wt_dir/" || true)
after=$(git -C "$root" worktree list --porcelain | grep -c '^worktree ')

summary_kv ROOT "$root"
summary_kv WORKTREES_DIR "$wt_dir"
summary_kv PRUNED "$((before - after))"
summary_kv REMAINING "${#left[@]}"
i=1
for p in "${left[@]}"; do
  summary_kv "WORKTREE_$i" "$p"
  i=$((i + 1))
done
[ "${#left[@]}" -gt 0 ] &&
  summary_issue WARN worktrees_remain "${#left[@]} worktree(s) still registered under $wt_dir; remove each with git worktree remove (never --force) or leave it for its owner"

summary_emit
[ "$(summary_status)" = "ERROR" ] && exit 1
exit 0
