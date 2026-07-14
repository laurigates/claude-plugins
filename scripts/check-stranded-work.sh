#!/usr/bin/env bash
# Find work that exists on a remote branch but never landed on the default branch.
#
# Two strand shapes, both observed in this repo:
#
#   1. AUTOCLOSE  — a stacked PR (base != default) whose base PR was squash-merged
#      and its branch deleted. GitHub closes the child PR instead of retargeting it,
#      and a closed PR whose base ref is gone CANNOT be reopened. Signature: PR is
#      closed-unmerged AND its base ref 404s. (claude-plugins #2049, 2026-07-12.)
#
#   2. NO_PR      — a branch pushed with real commits for which a PR was never opened
#      at all. No event ever fires for these, so only a sweep like this finds them.
#      (claude/add-function-calling-NYn76, claude/pip-to-uv-hook-POuYM.)
#
# A PR closed-unmerged whose base ref still EXISTS is a deliberate human close
# (duplicate, superseded, rejected) and is NOT reported. That single check is what
# separates the accidents from the decisions — 11 of 26 dead branches in the
# 2026-07-12 sweep were deliberate closes.
#
# Output follows .claude/rules/structured-script-output.md.
#
# Usage:
#   scripts/check-stranded-work.sh [--repo <owner/name>]...  # default: current repo
#   scripts/check-stranded-work.sh --issue-body              # markdown for gh issue create
#   scripts/check-stranded-work.sh --fixture <file.json>     # classify fixture (tests)
set -euo pipefail

REPOS=()
ISSUE_BODY=false
FIXTURE=""
MIN_AGE_DAYS=7

while [ $# -gt 0 ]; do
  case "$1" in
    --repo) REPOS+=("$2"); shift 2 ;;
    --issue-body) ISSUE_BODY=true; shift ;;
    --fixture) FIXTURE="$2"; shift 2 ;;
    --min-age-days) MIN_AGE_DAYS="$2"; shift 2 ;;
    -h|--help) sed -n '2,25p' "$0"; exit 0 ;;
    *) echo "unknown arg: $1" >&2; exit 2 ;;
  esac
done

# A branch pushed minutes ago with no PR yet is someone mid-work, not a strand.
# Only the never-PR'd class needs this grace period; an auto-closed PR is broken
# the moment it happens, so it is reported regardless of age.
CUTOFF="$(date -u -v-"${MIN_AGE_DAYS}"d +%F 2>/dev/null || date -u -d "${MIN_AGE_DAYS} days ago" +%F)"

# Branches owned by bots regenerate themselves; they are never "stranded".
is_bot_branch() {
  case "$1" in
    renovate/*|dependabot/*|release-please--*|pre-commit-ci-update-config) return 0 ;;
    *) return 1 ;;
  esac
}

# --- Collect ------------------------------------------------------------------
# Emits one JSON object per branch:
#   {repo, branch, sha, ahead, pr_number, pr_merged, pr_closed, base_exists, last_commit}
#
# `ahead` uses `git cherry`, NOT `git rev-list`: a squash-merge rewrites the SHA, so
# ancestry says "unmerged" for work that fully landed. `git cherry` marks a commit '-'
# when an equivalent patch is already upstream, which survives squash and cherry-pick.
# Ancestry/tree containment ALSO produces false "not contained" once the default branch
# drifts over the same files — do not reintroduce it here.
collect() {
  local repo="$1" default sha ahead pr_json pr_number pr_merged pr_closed base base_exists last

  default="$(gh repo view "$repo" --json defaultBranchRef --jq '.defaultBranchRef.name')"

  gh api "repos/$repo/branches" --paginate --jq '.[].name' | while read -r branch; do
    [ "$branch" = "$default" ] && continue
    is_bot_branch "$branch" && continue

    sha="$(gh api "repos/$repo/branches/$branch" --jq '.commit.sha')"
    last="$(gh api "repos/$repo/commits/$sha" --jq '.commit.committer.date[0:10]')"

    # Commits on the branch with no patch-equivalent upstream.
    if git rev-parse --git-dir >/dev/null 2>&1 && git cat-file -e "$sha" 2>/dev/null; then
      ahead="$(git cherry "origin/$default" "$sha" 2>/dev/null | grep -c '^+' || true)"
    else
      # Not fetched locally (cross-repo sweep): fall back to the compare API, which
      # reports ahead_by against the default branch.
      ahead="$(gh api "repos/$repo/compare/$default...$branch" --jq '.ahead_by' 2>/dev/null || echo 0)"
    fi
    [ "${ahead:-0}" -eq 0 ] && continue

    pr_json="$(gh pr list -R "$repo" --head "$branch" --state all --limit 1 \
      --json number,state,mergedAt,baseRefName 2>/dev/null || echo '[]')"

    pr_number="$(jq -r '.[0].number // ""' <<<"$pr_json")"
    pr_merged=false; pr_closed=false; base_exists=true

    if [ -n "$pr_number" ]; then
      [ "$(jq -r '.[0].mergedAt // "null"' <<<"$pr_json")" != "null" ] && pr_merged=true
      [ "$(jq -r '.[0].state' <<<"$pr_json")" = "CLOSED" ] && pr_closed=true
      base="$(jq -r '.[0].baseRefName' <<<"$pr_json")"
      # A 404 on the base ref is the auto-close fingerprint.
      gh api "repos/$repo/branches/$base" >/dev/null 2>&1 || base_exists=false
    fi

    jq -nc --arg repo "$repo" --arg branch "$branch" --arg sha "$sha" \
           --argjson ahead "$ahead" --arg pr "$pr_number" --arg last "$last" \
           --argjson merged "$pr_merged" --argjson closed "$pr_closed" \
           --argjson base_exists "$base_exists" \
      '{repo:$repo, branch:$branch, sha:$sha, ahead:$ahead, last_commit:$last,
        pr_number:(if $pr == "" then null else ($pr|tonumber) end),
        pr_merged:$merged, pr_closed:$closed, base_exists:$base_exists}'
  done
}

# --- Classify -----------------------------------------------------------------
# Pure function over the collected JSON — this is what the regression test drives.
# ISO dates compare correctly as plain strings, so no date math is needed here.
classify() {
  jq -s --arg cutoff "$CUTOFF" '
    map(
      . + {verdict:
        (if .pr_merged then "landed"
         elif .pr_closed and (.base_exists | not) then "stranded_autoclose"
         elif .pr_closed then "closed_deliberate"
         elif .pr_number != null then "open_pr"
         elif .last_commit > $cutoff then "in_flight"
         else "stranded_no_pr" end)}
    )
  '
}

# --- Report -------------------------------------------------------------------
main() {
  local data
  if [ -n "$FIXTURE" ]; then
    data="$(jq -c '.[]' "$FIXTURE" | classify)"
  else
    [ ${#REPOS[@]} -eq 0 ] && REPOS=("$(gh repo view --json nameWithOwner --jq .nameWithOwner)")
    data="$(for r in "${REPOS[@]}"; do collect "$r"; done | classify)"
  fi

  local autoclose no_pr count
  autoclose="$(jq '[.[] | select(.verdict == "stranded_autoclose")]' <<<"$data")"
  no_pr="$(jq '[.[] | select(.verdict == "stranded_no_pr")]' <<<"$data")"
  count=$(( $(jq 'length' <<<"$autoclose") + $(jq 'length' <<<"$no_pr") ))

  if [ "$ISSUE_BODY" = true ]; then
    [ "$count" -eq 0 ] && exit 0   # nothing to report; workflow skips issue creation
    echo "Branches carrying commits that never reached the default branch."
    echo
    if [ "$(jq 'length' <<<"$autoclose")" -gt 0 ]; then
      echo "## Auto-closed with unlanded work"
      echo
      echo "A stacked PR whose base branch was merged and deleted. GitHub closed it instead of"
      echo "retargeting, and it **cannot be reopened**. Recover by rebasing onto the default branch"
      echo "and filing a fresh PR."
      echo
      echo "| Repo | Branch | PR | Commits | Last commit |"
      echo "|------|--------|----|---------|-------------|"
      jq -r '.[] | "| \(.repo) | `\(.branch)` | #\(.pr_number) | \(.ahead) | \(.last_commit) |"' <<<"$autoclose"
      echo
    fi
    if [ "$(jq 'length' <<<"$no_pr")" -gt 0 ]; then
      echo "## Pushed but never PR'd"
      echo
      echo "No PR was ever opened, so no event ever fired for these. Content may still have landed"
      echo "via another PR — **verify against the default branch before acting**."
      echo
      echo "| Repo | Branch | Commits | Last commit |"
      echo "|------|--------|---------|-------------|"
      jq -r '.[] | "| \(.repo) | `\(.branch)` | \(.ahead) | \(.last_commit) |"' <<<"$no_pr"
      echo
    fi
    echo "### Recovery"
    echo
    echo 'Rebase onto the default branch, dropping commits already squashed into it, then refile:'
    echo
    echo '```'
    echo 'git rebase --onto origin/main <already-merged-sha> <branch>'
    echo 'git log --oneline origin/main..<branch>   # expect ONLY the unlanded commits'
    echo 'git push --force-with-lease origin <sha>:<branch>'
    echo 'gh pr create --base main --head <branch>'
    echo '```'
    echo
    echo 'If the work is redundant, delete the branch instead. Record the SHA first — deletion is'
    # shellcheck disable=SC2016  # literal markdown backticks, not a shell expansion
    echo 'reversible via `git push origin <sha>:refs/heads/<branch>`.'
    echo
    echo "cc @laurigates"
    exit 0
  fi

  echo "=== STRANDED WORK ==="
  jq -r '.[] | select(.verdict | startswith("stranded")) |
    "BRANCH=\(.branch) REPO=\(.repo) VERDICT=\(.verdict) AHEAD=\(.ahead) PR=\(.pr_number // "none") LAST=\(.last_commit)"' <<<"$data"
  echo
  echo "=== SUMMARY ==="
  echo "SCANNED=$(jq 'length' <<<"$data")"
  echo "STRANDED_AUTOCLOSE=$(jq 'length' <<<"$autoclose")"
  echo "STRANDED_NO_PR=$(jq 'length' <<<"$no_pr")"
  echo "LANDED=$(jq '[.[] | select(.verdict == "landed")] | length' <<<"$data")"
  echo "CLOSED_DELIBERATE=$(jq '[.[] | select(.verdict == "closed_deliberate")] | length' <<<"$data")"
  echo "OPEN_PR=$(jq '[.[] | select(.verdict == "open_pr")] | length' <<<"$data")"
  echo "IN_FLIGHT=$(jq '[.[] | select(.verdict == "in_flight")] | length' <<<"$data")"
  echo "STRANDED_COUNT=$count"
  echo "STATUS=$([ "$count" -eq 0 ] && echo PASS || echo WARN)"
}

main
