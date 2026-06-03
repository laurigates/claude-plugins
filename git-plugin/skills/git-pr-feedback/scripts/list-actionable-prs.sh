#!/usr/bin/env bash
# List open PRs that have actionable feedback:
#   - Unresolved (non-outdated) review threads
#   - Failing or errored CI workflows
#   - Reviewer requested changes
#
# Automation-authored PRs (release-please, dependabot, renovate, image
# updaters, etc.) are excluded by default: they never carry human review
# feedback to address, and their CI failures are resolved by automation
# re-running rather than by hand edits (and release-please-protection forbids
# touching the changelog/version files anyway). Pass --include-automation to
# surface them, or extend the recognised author list via
# PR_FEEDBACK_AUTOMATION_AUTHORS (comma/space separated).
#
# Emits a JSON array sorted by most-recently-updated.
#
# Usage: list-actionable-prs.sh [--include-automation] <owner> <repo>
#
# Testing: set PR_FEEDBACK_FIXTURE=<path> to read a captured GraphQL response
# from a file instead of calling `gh api graphql` (no network/auth needed).
set -euo pipefail

include_automation=false
positional=()
while [ $# -gt 0 ]; do
  case "$1" in
    --include-automation) include_automation=true; shift ;;
    --) shift; while [ $# -gt 0 ]; do positional+=("$1"); shift; done ;;
    -*) echo "Unknown flag: $1" >&2; exit 2 ;;
    *) positional+=("$1"); shift ;;
  esac
done
set -- "${positional[@]:-}"

OWNER="${1:?Usage: list-actionable-prs.sh [--include-automation] <owner> <repo>}"
REPO="${2:?Usage: list-actionable-prs.sh [--include-automation] <owner> <repo>}"

# Well-known automation accounts, extensible per-project via env var. Any login
# ending in [bot] or -bot is also treated as automation (pattern match in jq).
default_automation="dependabot[bot] renovate[bot] release-please[bot] github-actions[bot] fvh-buildbot"
automation_json=$(
  printf '%s %s' "$default_automation" "${PR_FEEDBACK_AUTOMATION_AUTHORS:-}" \
    | tr ',' ' ' | tr -s '[:space:]' '\n' | grep -v '^$' \
    | jq -R . | jq -s 'unique'
)

# shellcheck disable=SC2016
graphql_query='
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
}'

if [ -n "${PR_FEEDBACK_FIXTURE:-}" ]; then
  raw=$(cat "$PR_FEEDBACK_FIXTURE")
else
  raw=$(gh api graphql -f query="$graphql_query" -F owner="$OWNER" -F repo="$REPO")
fi

printf '%s' "$raw" | jq \
  --argjson automation "$automation_json" \
  --argjson includeAutomation "$include_automation" '[
  .data.repository.pullRequests.nodes[]
  | . as $pr
  | ($pr.author.login // "") as $login
  | ((($automation | index($login)) != null)
      or ($login | test("\\[bot\\]$"))
      or ($login | test("-bot$"))) as $isAutomation
  | ($pr.reviewThreads.nodes | map(select(.isResolved == false and .isOutdated == false)) | length) as $unresolved
  | ($pr.commits.nodes[0].commit.statusCheckRollup.state // "PENDING") as $ci
  | (($ci == "FAILURE") or ($ci == "ERROR")) as $ciFailing
  | ($pr.reviewDecision == "CHANGES_REQUESTED") as $changesRequested
  | select(($ciFailing or ($unresolved > 0) or $changesRequested) and (($pr.isDraft // false) | not))
  | select($includeAutomation or ($isAutomation | not))
  | {
      number: $pr.number,
      title: $pr.title,
      url: $pr.url,
      author: $login,
      head: $pr.headRefName,
      ci: $ci,
      unresolved: $unresolved,
      reviewDecision: ($pr.reviewDecision // "NONE"),
      updatedAt: $pr.updatedAt
    }
]'
