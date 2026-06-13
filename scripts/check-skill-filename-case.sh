#!/usr/bin/env bash
# Verify every skill file is named exactly `SKILL.md` (case-sensitive).
#
# Background: Claude Code matches the skill filename `SKILL.md` case-sensitively,
# so a skill stored as lowercase `skill.md` silently fails to load on any
# case-sensitive filesystem (Linux, CI, contributors on ext4/btrfs). On macOS's
# case-insensitive APFS the bug is invisible — `SKILL.md` resolves to `skill.md`.
# 45 skills shipped with the lowercase name before this guard (issue #1606); the
# same bug also broke the OpenCode export (rulesync matches case-sensitively too).
#
# Detection uses `git ls-files` rather than `find`, so the result does not depend
# on the running filesystem's case sensitivity — git reports its stored name.
#
# Usage:
#   bash scripts/check-skill-filename-case.sh
#
# Exit codes:
#   0 - every skill file is named SKILL.md
#   1 - one or more skill files use a non-canonical name
set -euo pipefail

cd "$(dirname "$0")/.." || exit 1

echo "=== SKILL FILENAME CASE ==="

# All tracked skill files matching skill.md case-insensitively, minus the
# canonical SKILL.md. Anything left is an offender.
offenders=()
while IFS= read -r f; do
  [ -n "$f" ] || continue
  offenders+=("$f")
done < <(git ls-files | grep -iE '/skills/.*/skill\.md$' | grep -v '/SKILL\.md$' || true)

issue_count=${#offenders[@]}
echo "ISSUE_COUNT=$issue_count"

if [ "$issue_count" -gt 0 ]; then
  echo "STATUS=ERROR"
  echo "ISSUES:"
  for f in "${offenders[@]}"; do
    echo "  - SEVERITY=ERROR FILE=$f MSG=rename to SKILL.md (case-sensitive); Claude Code will not load it on a case-sensitive filesystem"
  done
  echo "=== END SKILL FILENAME CASE ==="
  exit 1
fi

echo "STATUS=OK"
echo "=== END SKILL FILENAME CASE ==="
