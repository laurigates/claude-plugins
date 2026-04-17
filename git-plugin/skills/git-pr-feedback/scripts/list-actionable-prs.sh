#!/usr/bin/env bash
# List open PRs that have actionable feedback:
#   - Unresolved (non-outdated) review threads
#   - Failing or errored CI workflows
#   - Reviewer requested changes
#
# Emits a JSON array sorted by most-recently-updated.
#
# Usage: list-actionable-prs.sh <owner> <repo>
set -euo pipefail

OWNER="${1:?Usage: list-actionable-prs.sh <owner> <repo>}"
REPO="${2:?Usage: list-actionable-prs.sh <owner> <repo>}"

# shellcheck disable=SC2016
gh api graphql -f query='
query($owner: String!, $repo: String!) {
  repository(owner: $owner, name: $repo) {
    pullRequests(states: OPEN, first: 50, orderBy: {field: UPDATED_AT, direction: DESC}) {
      nodes {
        number
        title
        url
        isDraft
        author { login }
        headRefName
        reviewDecision
        updatedAt
        commits(last: 1) {
          nodes {
            commit {
              statusCheckRollup { state }
            }
          }
        }
        reviewThreads(first: 50) {
          nodes {
            isResolved
            isOutdated
          }
        }
      }
    }
  }
}' -F owner="$OWNER" -F repo="$REPO" | jq '[
  .data.repository.pullRequests.nodes[]
  | . as $pr
  | ($pr.reviewThreads.nodes | map(select(.isResolved == false and .isOutdated == false)) | length) as $unresolved
  | ($pr.commits.nodes[0].commit.statusCheckRollup.state // "PENDING") as $ci
  | (($ci == "FAILURE") or ($ci == "ERROR")) as $ciFailing
  | ($pr.reviewDecision == "CHANGES_REQUESTED") as $changesRequested
  | select(($ciFailing or ($unresolved > 0) or $changesRequested) and (($pr.isDraft // false) | not))
  | {
      number: $pr.number,
      title: $pr.title,
      url: $pr.url,
      author: $pr.author.login,
      head: $pr.headRefName,
      ci: $ci,
      unresolved: $unresolved,
      reviewDecision: ($pr.reviewDecision // "NONE"),
      updatedAt: $pr.updatedAt
    }
]'
