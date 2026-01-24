#!/usr/bin/env bash
# Commit Context Gathering Script
# Collects all pre-commit context in a single execution.
# Usage: bash commit-context.sh [--with-issues]
#
# Gathers: status, staged diff stats, recent log, branch info,
# and optionally open GitHub issues for auto-linking.
# Replaces 4-6 individual tool calls with one.

set -uo pipefail

WITH_ISSUES=false
[ "${1:-}" = "--with-issues" ] && WITH_ISSUES=true

echo "=== COMMIT CONTEXT ==="

# Branch info
current_branch=$(git branch --show-current 2>/dev/null || echo "DETACHED")
echo "BRANCH=$current_branch"

# Status summary
echo ""
echo "--- STATUS ---"
git status --porcelain 2>/dev/null | head -30

staged_files=$(git diff --cached --name-only 2>/dev/null)
staged_count=$(echo "$staged_files" | grep -c "." 2>/dev/null || echo "0")
echo ""
echo "STAGED_COUNT=$staged_count"

if [ "$staged_count" -eq 0 ]; then
  # Show unstaged files that could be staged
  echo ""
  echo "--- UNSTAGED CHANGES ---"
  git diff --stat 2>/dev/null | tail -5
  echo ""
  echo "HINT: No files staged. Use 'git add <file>' to stage changes."
fi

# Staged diff stats
if [ "$staged_count" -gt 0 ]; then
  echo ""
  echo "--- STAGED DIFF STATS ---"
  git diff --cached --stat 2>/dev/null

  echo ""
  echo "--- STAGED FILES ---"
  echo "$staged_files" | sed 's/^/  /'

  # Detect change types for commit message suggestion
  echo ""
  echo "--- CHANGE ANALYSIS ---"
  new_files=$(git diff --cached --name-only --diff-filter=A 2>/dev/null | wc -l)
  modified_files=$(git diff --cached --name-only --diff-filter=M 2>/dev/null | wc -l)
  deleted_files=$(git diff --cached --name-only --diff-filter=D 2>/dev/null | wc -l)
  renamed_files=$(git diff --cached --name-only --diff-filter=R 2>/dev/null | wc -l)
  echo "ADDED=$new_files"
  echo "MODIFIED=$modified_files"
  echo "DELETED=$deleted_files"
  echo "RENAMED=$renamed_files"

  # Detect common scopes from file paths
  echo ""
  echo "--- DETECTED SCOPES ---"
  echo "$staged_files" | sed 's|/[^/]*$||' | sort -u | head -5 | sed 's/^/  /'
fi

# Recent commits (for style matching)
echo ""
echo "--- RECENT COMMITS (style reference) ---"
git log --oneline -n 8 2>/dev/null | sed 's/^/  /'

# Conventional commit detection
conv_count=$(git log --oneline -n 10 2>/dev/null | grep -cE "^[a-f0-9]+ (feat|fix|docs|style|refactor|test|chore|build|ci|perf|revert)(\(.+\))?:" || echo "0")
echo ""
echo "CONVENTIONAL_STYLE=$([ "$conv_count" -ge 5 ] && echo "yes" || echo "mixed")"

# Pre-commit hook detection
echo ""
echo "--- PRE-COMMIT ---"
if [ -f ".pre-commit-config.yaml" ]; then
  echo "CONFIGURED=true"
  if [ -f ".git/hooks/pre-commit" ] && grep -q "pre-commit" .git/hooks/pre-commit 2>/dev/null; then
    echo "INSTALLED=true"
  else
    echo "INSTALLED=false"
  fi
else
  echo "CONFIGURED=false"
fi

# Open issues (for auto-linking)
if [ "$WITH_ISSUES" = true ]; then
  echo ""
  echo "--- OPEN ISSUES ---"
  if command -v gh >/dev/null 2>&1; then
    gh issue list --state open --json number,title,labels --limit 20 2>/dev/null | \
      jq -r '.[] | "#\(.number) \(.title) [\(.labels | map(.name) | join(","))]"' 2>/dev/null | \
      head -15 | sed 's/^/  /' || echo "  (gh auth or repo not available)"
  else
    echo "  (gh CLI not available)"
  fi
fi

echo ""
echo "=== CONTEXT COMPLETE ==="
