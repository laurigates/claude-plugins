#!/usr/bin/env bash
# prune-worktrees.sh — the sweep's worktree clean-up: `git worktree prune` on the
# clone, then list the linked worktrees still registered under its worktrees dir
# that carry a name the sweep's own agents use.
#
# Usage:
#   prune-worktrees.sh --root DIR [--worktrees DIR] [--run-id ID]
#
#   --root DIR       the local clone the sweep ran against (required)
#   --worktrees DIR  where the sweep's agents made worktrees
#                    (default: <root>/.claude/worktrees)
#   --run-id ID      also list a harness-isolated run's worktrees, wf_<ID>-<n>
#                    (ID with or without its wf_ prefix)
#
# Only sweep names are listed: repair-<unit> and verify-<unit> (pr-fix, also
# under round2/), pr-sweep-verify-<pr>-<n> (pr-review), and wf_<ID>-<n> with
# --run-id. The default dir is the one every Claude Code session shares for its
# worktrees, so anything else there is a peer's; OTHER_WORKTREES counts those
# and names none. Another run can reuse a sweep name too, so the listing is a
# report, not a removal list.
#
# A script rather than `git -C <root> worktree prune` in SKILL.md: a skill grant
# for that command needs a wildcard before the subcommand, and such a grant also
# pre-approves `git -C <x> -c alias.worktree=... worktree prune`.
#
# prune drops only entries whose directory is already gone, so it never touches
# a live worktree. The script removes nothing itself and never forces anything;
# each WORKTREE_<i>= line is a sweep-named worktree that still exists. Only
# references/fix-redispatch.md removes any, and only its own unit's paths.
#
# Exit: 0 OK (remaining worktrees are a WARN, not an error), 1 ERROR, 2 usage.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=SCRIPTDIR/lib/summary.sh disable=SC1091
source "$SCRIPT_DIR/lib/summary.sh"

usage() {
  echo "Usage: prune-worktrees.sh --root DIR [--worktrees DIR] [--run-id ID]" >&2
  exit 2
}

root=""
wt_dir=""
run_id=""
while [ $# -gt 0 ]; do
  case "$1" in
    --root) [ $# -ge 2 ] || usage; root="$2"; shift 2 ;;
    --worktrees) [ $# -ge 2 ] || usage; wt_dir="$2"; shift 2 ;;
    --run-id) [ $# -ge 2 ] || usage; run_id="${2#wf_}"; shift 2 ;;
    -h|--help) usage ;;
    *) echo "Unknown argument: $1" >&2; exit 2 ;;
  esac
done
[ -n "$root" ] || usage
# The ID becomes part of a regex below: letters, digits and - only.
if [ -n "$run_id" ] && ! [[ "$run_id" =~ ^[A-Za-z0-9-]+$ ]]; then
  echo "Bad --run-id: $run_id" >&2
  exit 2
fi

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
mapfile -t under < <(git -C "$root" worktree list --porcelain | sed -n 's/^worktree //p' | grep -F -- "$wt_dir/" || true)
after=$(git -C "$root" worktree list --porcelain | grep -c '^worktree ')

# Sweep names only, one level below the dir (two under round2/).
own_re='^((round2/)?(repair|verify)-[^/]+|pr-sweep-verify-[^/]+'
[ -n "$run_id" ] && own_re="$own_re|wf_$run_id-[^/]+"
own_re="$own_re)\$"
left=()
others=0
for p in "${under[@]}"; do
  if [[ "${p#"$wt_dir/"}" =~ $own_re ]]; then left+=("$p"); else others=$((others + 1)); fi
done

summary_kv ROOT "$root"
summary_kv WORKTREES_DIR "$wt_dir"
summary_kv PRUNED "$((before - after))"
summary_kv REMAINING "${#left[@]}"
summary_kv OTHER_WORKTREES "$others"
i=1
for p in "${left[@]}"; do
  summary_kv "WORKTREE_$i" "$p"
  i=$((i + 1))
done
[ "${#left[@]}" -gt 0 ] &&
  summary_issue WARN worktrees_remain "${#left[@]} sweep-named worktree(s) remain: list them in the report, remove none (another session's run can reuse the names); dir $wt_dir"

summary_emit
[ "$(summary_status)" = "ERROR" ] && exit 1
exit 0
