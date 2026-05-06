#!/usr/bin/env bash
# Lint taskwarrior-plugin docs for hyphenated tag names that silently break
# taskwarrior's parser.
#
# Taskwarrior parses `-` mid-token as exclude-filter syntax even inside a
# `+tag` argument: `+blocked-on-merge` is parsed as `+blocked` AND
# `-on-merge`, so the tag never lands and the literal string ends up
# appended to the description (urgency does not tick up). Quoting does not
# help — this is a parser quirk, not a shell issue.
#
# Use underscores or camelCase instead: `+blocked_on_merge`,
# `+blockedOnMerge`.
#
# Regression: hyphenated tags (`+blocked-on-merge`, `+pr-ready`,
# `+needs-review`, `+bulk-task`) appeared in task-add, task-status,
# task-coordinate, and the plugin README — all silently broken when
# copy-pasted (issue #1237).
#
# Lines starting with `>` (markdown blockquote) are skipped so the explicit
# "Tag naming gotcha" callouts can still cite the broken pattern as an
# example.
#
# Exit codes:
#   0 - no issues
#   1 - errors found

set -euo pipefail

errors=0

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
plugin_dir="$repo_root/taskwarrior-plugin"

if [ ! -d "$plugin_dir" ]; then
  echo "taskwarrior-plugin directory not found at $plugin_dir" >&2
  exit 1
fi

# Find markdown files inside the taskwarrior-plugin and scan for `+word-word`
# patterns on lines that are NOT blockquotes.
while IFS= read -r -d '' file; do
  while IFS=: read -r line_no content; do
    # Skip blockquote lines (the gotcha callout uses these to cite broken
    # examples on purpose).
    case "$content" in
      '>'* | *[[:space:]]'>'*) continue ;;
    esac
    printf "ERROR [taskwarrior-tag-hyphen]: %s:%s\n" "${file#"$repo_root"/}" "$line_no"
    printf "  Found: %s\n" "$content"
    printf "  Fix: rename the tag to use underscores or camelCase (e.g. +blocked_on_merge or +blockedOnMerge); hyphens silently fail to parse\n\n"
    errors=$((errors + 1))
  done < <(grep -nE '\+[a-z][a-z0-9_]*-[a-z]' "$file" || true)
done < <(find "$plugin_dir" -type f \( -name '*.md' \) -print0)

if [ "$errors" -gt 0 ]; then
  printf "Found %d hyphenated tag reference(s) in taskwarrior-plugin docs\n" "$errors"
  exit 1
fi

printf "All taskwarrior-plugin tag references OK\n"
exit 0
