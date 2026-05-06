#!/usr/bin/env bash
# shellcheck disable=SC2016  # Grep pattern uses backticks and + literally, not as shell expansion
# Lint taskwarrior-plugin SKILL.md and README.md files for hyphenated tag examples.
#
# Background: taskwarrior parses `+blocked-on-merge` as `+blocked` AND `-on-merge`
# (the `-` mid-token triggers exclude-filter syntax), silently dropping the tag and
# appending the literal token to the description. Quoting does not help — this is
# a taskwarrior parser quirk, not a shell issue. Documented examples must use
# underscores (`+blocked_on_merge`) or camelCase (`+blockedOnMerge`).
#
# Regression: issue #1237 — task-add/task-status/task-coordinate skills and
# taskwarrior-plugin/README.md documented `+pr-ready`, `+needs-review`,
# `+blocked-on-merge`, and `+bulk-task` as if they worked. Tasks filed using those
# tag names ended up with `tags: null` and the literal token swallowed into
# the description.
#
# This check anchors only to taskwarrior-plugin files. Hyphens elsewhere in the
# repo are unrelated.
#
# Exit codes:
#   0 - no issues
#   1 - hyphenated taskwarrior tag examples found
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
target_dir="$repo_root/taskwarrior-plugin"

if [[ ! -d "$target_dir" ]]; then
  exit 0
fi

errors=0

# Match `+word-word` or `+word-word-word` patterns inside backticks. Skip the
# documented gotcha lines that intentionally show the broken syntax — those
# lines contain the phrase "parsed as" or "Use underscores" or "naming gotcha"
# or "Use underscores, not hyphens" nearby.
while IFS=: read -r match_file match_line match_content; do
  # Skip lines that are explaining the gotcha (i.e. callouts demonstrating
  # the broken form on purpose).
  if echo "$match_content" | grep -qE "parsed as|naming gotcha|not hyphens|does not help|Use underscores|exclude-filter"; then
    continue
  fi
  printf "ERROR [taskwarrior-tag-hyphen]: %s:%s\n" "$match_file" "$match_line"
  printf "  Found: %s\n" "$match_content"
  printf "  Fix: replace hyphens with underscores (e.g. +pr_ready, +blocked_on_merge)\n\n"
  errors=$((errors + 1))
done < <(grep -rn -E '\`\+[a-z]+-[a-z]+(-[a-z]+)?\`' \
  --include='SKILL.md' \
  --include='skill.md' \
  --include='README.md' \
  "$target_dir" 2>/dev/null || true)

if (( errors > 0 )); then
  printf "Found %d hyphenated taskwarrior tag example(s) in taskwarrior-plugin/\n" "$errors" >&2
  printf "Hyphens silently break taskwarrior tag parsing. See issue #1237 for details.\n" >&2
  exit 1
fi

exit 0
