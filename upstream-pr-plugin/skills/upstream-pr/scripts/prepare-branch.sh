#!/usr/bin/env bash
# Cut a branch from the upstream main branch and cherry-pick a commit onto it.
#
# Usage: prepare-branch.sh <topic-slug> <sha>
#
# Creates branch `<branch_prefix><topic-slug>` from `<upstream_remote>/main`
# (or `/master` as fallback), attempts to cherry-pick <sha>, and reports
# any conflicts that need manual resolution.
#
# Configuration (via .claude/upstream-pr.local.md or env vars):
#   UPSTREAM_REMOTE    remote name (default: "upstream")
#   UPSTREAM_REPO      target repo (auto-detected from remote URL)
#   BRANCH_PREFIX      branch name prefix (default: "pr-upstream/")
#
# Exit codes:
#   0  branch created and cherry-pick succeeded cleanly
#   1  cherry-pick produced conflicts (branch exists, ready for manual resolution)
#   2  invalid arguments, ineligible commit, or git precondition failure

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "$script_dir/lib/load-config.sh"
load_upstream_pr_config

if [[ $# -ne 2 ]]; then
    echo "usage: $0 <topic-slug> <sha>" >&2
    exit 2
fi

topic="$1"
sha="$2"
branch="${BRANCH_PREFIX}${topic}"

# --- Preconditions ---------------------------------------------------------

if [[ -n "$(git status --porcelain)" ]]; then
    echo "error: working tree has uncommitted changes; commit or stash first" >&2
    exit 2
fi

if git rev-parse --verify --quiet "refs/heads/$branch" >/dev/null; then
    echo "error: branch '$branch' already exists" >&2
    echo "delete it with: git branch -D $branch" >&2
    exit 2
fi

# --- Eligibility -----------------------------------------------------------

echo "==> Checking eligibility..."
elig_rc=0
"$script_dir/check-eligibility.sh" "$sha" || elig_rc=$?
case "$elig_rc" in
    0) ;;
    3)
        echo
        echo "Aborting — commit already applied upstream, nothing to PR." >&2
        exit 2
        ;;
    *)
        echo
        echo "Aborting — commit is not standalone-PR-able to upstream." >&2
        exit 2
        ;;
esac

# --- Branch + cherry-pick --------------------------------------------------

echo
echo "==> Fetching $UPSTREAM_REMOTE..."
git fetch "$UPSTREAM_REMOTE"

# Resolve the upstream main reference (main or master).
upstream_ref="${UPSTREAM_REMOTE}/main"
if ! git rev-parse --verify --quiet "$upstream_ref" >/dev/null; then
    upstream_ref="${UPSTREAM_REMOTE}/master"
fi

echo
echo "==> Creating branch '$branch' from $upstream_ref..."
git checkout -b "$branch" "$upstream_ref"

echo
echo "==> Cherry-picking $sha..."
if git cherry-pick "$sha"; then
    echo
    echo "SUCCESS — cherry-pick clean."
    echo
    echo "Next steps:"
    echo "  1. Review:  git diff $upstream_ref..HEAD"
    echo "  2. Scrub commit message:"
    echo "     bash $script_dir/scrub-commit.sh"
    echo "  3. Push:    git push origin $branch"
    if [[ -n "${UPSTREAM_REPO:-}" ]]; then
        local_owner=$(git remote get-url origin | sed -E 's#.*github\.com[:/]##; s#\.git$##; s#/.*##')
        echo "  4. Open PR: gh pr create --repo $UPSTREAM_REPO --base ${upstream_ref##*/} \\"
        echo "                --head ${local_owner}:$branch ..."
    else
        echo "  4. Open PR: gh pr create --repo <upstream-owner/repo> --base ${upstream_ref##*/} \\"
        echo "                --head <fork-owner>:$branch ..."
    fi
    exit 0
fi

echo
echo "CONFLICTS — resolve manually, then run 'git cherry-pick --continue'."
echo
echo "Conflicted files:"
git diff --name-only --diff-filter=U | sed 's/^/  - /'
echo
echo "Reminder: preserve upstream's surrounding shape, not ours."
echo
echo "If conflicts span >2 files with >20 blocks, abort and re-derive instead:"
echo "  git cherry-pick --abort"
echo "  git checkout -b $branch $upstream_ref"
echo "  # Re-apply the change against upstream's actual current files."
exit 1
