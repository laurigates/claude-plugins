#!/usr/bin/env bash
# Lint plugin skill files for references to MCP tool names that aren't
# shipped by the corresponding MCP server.
#
# Skills that document `mcp__<server>__<tool>` names in their body or
# `allowed-tools` create silent failures when the referenced tool isn't
# actually exposed by that server. The user can't bypass via ToolSearch
# either — the schema simply doesn't exist. The agent typically falls
# back to a `gh api graphql` form after a wasted round trip.
#
# This script encodes a denylist of known-unavailable references. Add a
# new entry whenever a skill is found referencing an MCP tool that the
# server doesn't actually ship.
#
# Lines starting with `>` (markdown blockquote) are skipped so the
# documented gotcha callouts in regression-testing.md and similar files
# can still cite the broken form as an example.
#
# Regression: git-pr-feedback referenced `mcp__github__resolve_review_thread`
# in Step 6, Step 1A.7.4, the Agentic Optimizations table, REFERENCE.md
# resolution criteria, and `allowed-tools` — but the standard github MCP
# server does not expose that tool. Use `gh api graphql` with the
# `resolveReviewThread` mutation instead (issue #1429).
#
# Exit codes:
#   0 - no issues
#   1 - errors found
set -euo pipefail

errors=0

repo_root="$(cd "$(dirname "$0")/.." && pwd)"

# Denylist of (tool-name, suggested-fix) pairs. Each pair is two adjacent
# entries in the same array so bash 3.2 (macOS default) still works without
# associative arrays.
denylist=(
  "mcp__github__resolve_review_thread"
  "use gh api graphql with the resolveReviewThread mutation: gh api graphql -f query='mutation(\$id:ID!){resolveReviewThread(input:{threadId:\$id}){thread{isResolved}}}' -F id=\"\$THREAD_ID\""
)

# Iterate over the denylist in pairs.
i=0
while [ $i -lt ${#denylist[@]} ]; do
  tool="${denylist[$i]}"
  fix="${denylist[$((i + 1))]}"

  while IFS= read -r -d '' file; do
    while IFS=: read -r line_no content; do
      # Skip blockquote lines (gotcha callouts cite the broken form on purpose).
      case "$content" in
        '>'* | *[[:space:]]'>'*) continue ;;
      esac
      printf "ERROR [unavailable-mcp-tool]: %s:%s\n" "${file#./}" "$line_no"
      printf "  Found: %s\n" "$content"
      printf "  Tool:  %s (not exposed by its MCP server)\n" "$tool"
      printf "  Fix:   %s\n\n" "$fix"
      errors=$((errors + 1))
    done < <(grep -nF "$tool" "$file" || true)
  done < <(cd "$repo_root" && find . -type f \
              \( -name 'SKILL.md' -o -name 'skill.md' -o -name 'REFERENCE.md' \) \
              -not -path './.claude/worktrees/*' \
              -not -path '*/node_modules/*' \
              -print0)

  i=$((i + 2))
done

if [ "$errors" -gt 0 ]; then
  printf "Found %d unavailable-MCP-tool reference(s) in skill files\n" "$errors"
  exit 1
fi

printf "All MCP tool references in skill files OK\n"
exit 0
