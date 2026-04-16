#!/usr/bin/env bash
# Fetch all PR data (details, reviews, review threads, comments, CI checks)
# in a single GraphQL query to minimize API calls.
#
# Usage: fetch-pr-data.sh <owner> <repo> <pr-number>
set -euo pipefail

OWNER="${1:?Usage: fetch-pr-data.sh <owner> <repo> <pr-number>}"
REPO="${2:?Usage: fetch-pr-data.sh <owner> <repo> <pr-number>}"
PR="${3:?Usage: fetch-pr-data.sh <owner> <repo> <pr-number>}"

# GraphQL variables use $ syntax, single quotes prevent shell expansion
# shellcheck disable=SC2016
gh api graphql -f query='
query($owner: String!, $repo: String!, $pr: Int!) {
  repository(owner: $owner, name: $repo) {
    pullRequest(number: $pr) {
      number
      headRefName
      state
      reviewDecision
      commits(last: 1) {
        nodes {
          commit {
            statusCheckRollup {
              state
              contexts(first: 50) {
                nodes {
                  ... on CheckRun {
                    name
                    conclusion
                    status
                    detailsUrl
                  }
                }
              }
            }
          }
        }
      }
      reviews(first: 50) {
        nodes {
          author { login }
          state
          body
        }
      }
      reviewThreads(first: 100) {
        nodes {
          id
          isResolved
          isOutdated
          isCollapsed
          comments(first: 20) {
            nodes {
              id
              databaseId
              path
              line
              originalLine
              diffHunk
              body
              author { login }
              url
            }
          }
        }
      }
      comments(first: 100) {
        nodes {
          author { login }
          body
          createdAt
        }
      }
    }
  }
}' -F owner="$OWNER" -F repo="$REPO" -F pr="$PR"
