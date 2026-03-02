#!/usr/bin/env bash
# PreToolUse hook for Bash tool - validates gh pr create includes issue closing keywords
#
# When creating a PR, checks that the PR body contains GitHub closing keywords
# (Closes #N, Fixes #N, Resolves #N) that auto-close issues when the PR merges.
#
# Strategy:
# 1. Guard: only fires on gh pr create commands
# 2. Extract body from --body-file (most common) or --body flag
# 3. If body has closing keywords, allow immediately
# 4. Check git log for issue references in commits being PR'd
# 5. If commits reference issues but body doesn't, block with guidance
# 6. If no evidence this PR closes specific issues, allow silently

set -euo pipefail

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty')
CWD=$(echo "$INPUT" | jq -r '.cwd // empty')

# Guard: only for gh pr create commands
if [ -z "$COMMAND" ]; then exit 0; fi
if ! echo "$COMMAND" | grep -qE '(^|\s)gh\s+pr\s+create'; then exit 0; fi

# Extract body content from --body-file (preferred pattern for multi-line bodies)
# Uses perl instead of grep -P for macOS BSD grep compatibility
BODY=""
if echo "$COMMAND" | grep -qE '\-\-body-file'; then
    BODY_FILE=$(echo "$COMMAND" | perl -ne 'if (/--body-file[= ](\S+)/) { print $1; }' 2>/dev/null || true)
    if [ -n "$BODY_FILE" ] && [ -f "$BODY_FILE" ]; then
        BODY=$(cat "$BODY_FILE")
    fi
fi

# Fall back to inline --body argument (single-quoted, then double-quoted)
if [ -z "$BODY" ] && echo "$COMMAND" | grep -qE '\-\-body\b'; then
    BODY=$(echo "$COMMAND" | perl -ne "if (/--body '([^']*)'/) { print \$1; }" 2>/dev/null || true)
    if [ -z "$BODY" ]; then
        BODY=$(echo "$COMMAND" | perl -ne 'if (/--body "([^"]*)"/) { print $1; }' 2>/dev/null || true)
    fi
fi

# Body already has closing keywords — allow
if [ -n "$BODY" ] && echo "$BODY" | grep -qiE '\b(closes?|fixes?|resolves?)[: ]+#[0-9]+'; then
    exit 0
fi

# Check git log for issue closing keywords in commits being PR'd
# Uses merge-base with origin/HEAD to find commits unique to this branch
COMMIT_ISSUES=""
if [ -n "$CWD" ] && git -C "$CWD" rev-parse --git-dir >/dev/null 2>&1; then
    BASE=$(git -C "$CWD" merge-base HEAD origin/HEAD 2>/dev/null || true)
    if [ -n "$BASE" ]; then
        COMMIT_ISSUES=$(git -C "$CWD" log --format='%s%n%b' "${BASE}..HEAD" 2>/dev/null \
            | grep -oiE '\b(closes?|fixes?|resolves?)[: ]+#[0-9]+' \
            | sort -u | head -5 || true)
    fi
fi

# No commit issue references — this PR may not be closing a specific issue, allow
if [ -z "$COMMIT_ISSUES" ]; then
    exit 0
fi

# Commits reference issues but PR body doesn't — block with specific guidance
ISSUE_LIST=$(echo "$COMMIT_ISSUES" | tr '\n' ' ' | sed 's/ $//')
echo "PR ISSUE LINKING: PR body is missing issue closing keywords.

Commits in this branch reference:  ${ISSUE_LIST}

Add closing keywords to the PR body to auto-close issues when the PR merges to the default branch:

  Fixes #N     — for bug fixes
  Closes #N    — for features and resolved issues
  Resolves #N  — for general resolution

For multiple issues, repeat the keyword:
  Fixes #1, Fixes #2

Keywords are case-insensitive. Colons are optional (Closes: #10 works).
Issue auto-close only triggers when merging to the repository's default branch." >&2
exit 2
