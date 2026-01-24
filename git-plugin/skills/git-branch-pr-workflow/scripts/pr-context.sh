#!/usr/bin/env bash
# PR Context Gathering Script
# Collects all information needed for PR creation in one execution.
# Usage: bash pr-context.sh [base-branch]
#
# Gathers: branch info, commit range, diff stats, CI status,
# and related issues. Replaces 5-7 individual tool calls.

set -uo pipefail

BASE_BRANCH="${1:-main}"

echo "=== PR CONTEXT ==="

# Current branch
current_branch=$(git branch --show-current 2>/dev/null || echo "DETACHED")
echo "HEAD_BRANCH=$current_branch"
echo "BASE_BRANCH=$BASE_BRANCH"

if [ "$current_branch" = "$BASE_BRANCH" ]; then
  echo "WARNING: Currently on base branch ($BASE_BRANCH)"
  echo "HINT: Push to remote feature branch with 'git push origin $BASE_BRANCH:<feature-branch>'"
fi
echo ""

# Remote tracking
echo "--- REMOTE STATUS ---"
if git rev-parse --verify "origin/$current_branch" >/dev/null 2>&1; then
  echo "REMOTE_BRANCH=origin/$current_branch"
  ahead=$(git rev-list --count "origin/$current_branch..HEAD" 2>/dev/null || echo "0")
  echo "UNPUSHED_COMMITS=$ahead"
  [ "$ahead" -gt 0 ] && echo "NEEDS_PUSH=true" || echo "NEEDS_PUSH=false"
else
  echo "REMOTE_BRANCH=none"
  echo "NEEDS_PUSH=true"
  echo "HINT: Push with 'git push -u origin $current_branch'"
fi
echo ""

# Commits since base
echo "--- COMMITS (since $BASE_BRANCH) ---"
if git rev-parse --verify "$BASE_BRANCH" >/dev/null 2>&1; then
  commit_count=$(git rev-list --count "$BASE_BRANCH..HEAD" 2>/dev/null || echo "0")
  echo "COUNT=$commit_count"
  echo "COMMITS:"
  git log --oneline "$BASE_BRANCH..HEAD" 2>/dev/null | head -20 | sed 's/^/  /'
else
  echo "COUNT=unknown"
  echo "HINT: Base branch '$BASE_BRANCH' not found locally. Try 'git fetch origin $BASE_BRANCH'"
fi
echo ""

# Diff stats against base
echo "--- DIFF STATS (vs $BASE_BRANCH) ---"
if git rev-parse --verify "$BASE_BRANCH" >/dev/null 2>&1; then
  git diff --stat "$BASE_BRANCH...HEAD" 2>/dev/null | tail -15

  echo ""
  echo "FILES_CHANGED:"
  git diff --name-only "$BASE_BRANCH...HEAD" 2>/dev/null | head -30 | sed 's/^/  /'

  # Insertions/deletions summary
  diffstat=$(git diff --shortstat "$BASE_BRANCH...HEAD" 2>/dev/null)
  echo ""
  echo "SHORTSTAT: $diffstat"
fi
echo ""

# Issue references in commits
echo "--- ISSUE REFERENCES ---"
refs=$(git log --oneline "$BASE_BRANCH..HEAD" 2>/dev/null | grep -oE "#[0-9]+" | sort -u)
if [ -n "$refs" ]; then
  echo "REFERENCED_ISSUES:"
  echo "$refs" | sed 's/^/  /'
else
  echo "REFERENCED_ISSUES: none"
fi

# Closing keywords in commits
closes=$(git log "$BASE_BRANCH..HEAD" --format="%B" 2>/dev/null | grep -iE "(close|fix|resolve)[sd]?\s+#[0-9]+" | head -5)
if [ -n "$closes" ]; then
  echo "CLOSING_KEYWORDS:"
  echo "$closes" | sed 's/^/  /'
fi
echo ""

# Conventional commit type summary
echo "--- COMMIT TYPE BREAKDOWN ---"
if git rev-parse --verify "$BASE_BRANCH" >/dev/null 2>&1; then
  git log --oneline "$BASE_BRANCH..HEAD" 2>/dev/null | \
    grep -oE "^[a-f0-9]+ (feat|fix|docs|style|refactor|test|chore|build|ci|perf|revert)" | \
    awk '{print $2}' | sort | uniq -c | sort -rn | sed 's/^/  /' || echo "  (non-conventional)"
fi
echo ""

# PR title suggestion based on commits
echo "--- PR SUGGESTIONS ---"
if [ "${commit_count:-0}" -eq 1 ]; then
  # Single commit: use its message as PR title
  echo "TITLE_SUGGESTION: $(git log --oneline -1 HEAD 2>/dev/null | sed 's/^[a-f0-9]* //')"
elif [ "${commit_count:-0}" -gt 1 ]; then
  # Multiple commits: suggest based on dominant type
  dominant_type=$(git log --oneline "$BASE_BRANCH..HEAD" 2>/dev/null | \
    grep -oE "^[a-f0-9]+ (feat|fix|docs|refactor|chore)" | \
    awk '{print $2}' | sort | uniq -c | sort -rn | head -1 | awk '{print $2}')
  echo "DOMINANT_TYPE=${dominant_type:-mixed}"
fi
echo ""

# Check for existing PR
echo "--- EXISTING PR ---"
if command -v gh >/dev/null 2>&1; then
  existing_pr=$(gh pr list --head "$current_branch" --json number,title,state 2>/dev/null | jq -r '.[0] // empty' 2>/dev/null)
  if [ -n "$existing_pr" ]; then
    echo "EXISTING_PR:"
    echo "  $existing_pr"
  else
    echo "EXISTING_PR=none"
  fi

  # CI checks on current branch
  if [ -n "$existing_pr" ]; then
    pr_num=$(echo "$existing_pr" | jq -r '.number' 2>/dev/null)
    if [ -n "$pr_num" ] && [ "$pr_num" != "null" ]; then
      echo ""
      echo "--- CI CHECKS ---"
      gh pr checks "$pr_num" --json name,state,conclusion 2>/dev/null | \
        jq -r '.[] | "\(.state)\t\(.conclusion // "pending")\t\(.name)"' 2>/dev/null | head -10 | sed 's/^/  /'
    fi
  fi
else
  echo "EXISTING_PR=unknown (gh CLI not available)"
fi

echo ""
echo "=== CONTEXT COMPLETE ==="
