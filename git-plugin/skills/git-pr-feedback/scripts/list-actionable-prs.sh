#!/usr/bin/env bash
# List open PRs that have actionable feedback:
#   - Unresolved (non-outdated) review threads
#   - Failing or errored CI workflows
#   - Reviewer requested changes
#   - Top-level feedback (issue #3129): a non-empty PR conversation comment or
#     a non-empty COMMENTED review body posted after the PR's latest commit
#     (commits(last:1).committedDate). Keyed on presence + recency only —
#     severity is never parsed from the prose. The skill's own SHA-bearing
#     replies (`Fixed in <sha>`, `Accepted in <sha>`, `Applied a variant in
#     <sha>`, `Partially addressed in <sha>`) are excluded so a feedback pass
#     does not re-flag its own output. Reported as `topLevelFeedback`.
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
              committedDate
              statusCheckRollup { state }
            }
          }
        }
        comments(last: 50) {
          nodes {
            author { login }
            body
            createdAt
          }
        }
        reviews(last: 50, states: [COMMENTED]) {
          nodes {
            author { login }
            state
            body
            submittedAt
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

# The skill's own SHA-bearing reply templates (REFERENCE.md "Reply Templates").
# Anchored at body start, so real feedback that merely quotes one still counts.
own_reply_re='^\s*(Fixed|Accepted|Applied a variant|Partially addressed) in `?[0-9a-f]{7,40}\b'

if [ -n "${PR_FEEDBACK_FIXTURE:-}" ]; then
  raw=$(cat "$PR_FEEDBACK_FIXTURE")
else
  raw=$(gh api graphql -f query="$graphql_query" -F owner="$OWNER" -F repo="$REPO")
fi

printf '%s' "$raw" | jq \
  --argjson automation "$automation_json" \
  --arg ownReply "$own_reply_re" \
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
  | ($pr.commits.nodes[0].commit.committedDate // "") as $lastCommitAt
  | (
      [ ($pr.comments.nodes // [])[] | {body, at: .createdAt} ]
      + [ ($pr.reviews.nodes // [])[] | select(.state == "COMMENTED") | {body, at: .submittedAt} ]
      | map(select(
          ((.body // "") | test("\\S"))
          and ((.at // "") > $lastCommitAt)
          and (((.body // "") | test($ownReply)) | not)
        ))
      | length
    ) as $topLevelFeedback
  | select(($ciFailing or ($unresolved > 0) or $changesRequested or ($topLevelFeedback > 0)) and (($pr.isDraft // false) | not))
  | select($includeAutomation or ($isAutomation | not))
  | {
      number: $pr.number,
      title: $pr.title,
      url: $pr.url,
      author: $login,
      head: $pr.headRefName,
      ci: $ci,
      unresolved: $unresolved,
      topLevelFeedback: $topLevelFeedback,
      reviewDecision: ($pr.reviewDecision // "NONE"),
      updatedAt: $pr.updatedAt
    }
]'
