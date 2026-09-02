#!/usr/bin/env bash
# Verify a `context: fork` skill never ends its body with a user-directed
# confirmation question.
#
# Background: a skill with `context: fork` runs in a forked subagent that
# cannot get an answer from the user — there is no channel back. A body that
# ends "Do you want me to proceed…?" / "would you like to review…?" /
# "shall I proceed?" produces the §C.8 early-stop pattern (state intent, never
# act) and violates the rule that a request to analyze is itself a change
# request, not a question (issue found in testing-plugin:test-analyze SKILL.md,
# 2026-09).
#
# Usage:
#   bash scripts/check-fork-skill-trailing-question.sh [--project-dir <path>] [skill.md ...]
#
#   --project-dir   Repo root to scan (default: git toplevel, else cwd).
#   skill.md ...    Explicit files to check (pre-commit style); when present,
#                   discovery is skipped and only these files are checked.
#
# Exit codes:
#   0 - no fork skill ends on a user-directed confirmation question
#   1 - at least one does

set -uo pipefail

proj_dir=""
explicit_files=()
while [ $# -gt 0 ]; do
  case "$1" in
    --project-dir) proj_dir="$2"; shift 2 ;;
    *) explicit_files+=("$1"); shift ;;
  esac
done

if [ -z "$proj_dir" ]; then
  proj_dir="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
fi

skill_files=()
plugin_dirs=()
if [ ${#explicit_files[@]} -gt 0 ]; then
  skill_files=("${explicit_files[@]}")
else
  cd "$proj_dir" || { echo "check-fork-skill-trailing-question.sh: cannot cd to $proj_dir" >&2; exit 2; }

  # Discovery runs from INSIDE proj_dir against RELATIVE paths (#2219/#2290) so
  # the `.claude/worktrees/*` prune cannot match the scan root itself.
  while IFS= read -r -d '' plugin_dir; do
    plugin_dirs+=("$plugin_dir")
  done < <(find . -maxdepth 1 -type d -name '*-plugin' -not -name '.claude-plugin' -print0)

  if [ ${#plugin_dirs[@]} -gt 0 ]; then
    while IFS= read -r -d '' skill_file; do
      skill_files+=("$skill_file")
    done < <(
      find "${plugin_dirs[@]}" -path '*/.claude/worktrees/*' -prune -o \
        \( -iname 'SKILL.md' \) -type f -print0
    )
  fi
fi

if [ ${#skill_files[@]} -eq 0 ]; then
  if [ ${#plugin_dirs[@]} -gt 0 ] && [ ${#explicit_files[@]} -eq 0 ]; then
    echo "SKILLS_SCANNED=0" >&2
    echo "⚠️  Found ${#plugin_dirs[@]} plugin director(ies) under $proj_dir but ZERO SKILL.md files." >&2
    echo "    This is a discovery misfire, not a clean tree — the guard checked nothing." >&2
    exit 1
  fi
  echo "SKILLS_SCANNED=0"
  echo "SCANNED_EMPTY=true"
  echo "No skill files found — nothing to check"
  exit 0
fi

# Confirmation-question phrases a fork skill must never end on. Case-insensitive.
QUESTION_RE='(do you want me to|would you like|shall i proceed|should i proceed|shall i continue|should i continue)'

errors=0
checked=0

for skill_file in "${skill_files[@]}"; do
  [ -f "$skill_file" ] || continue

  # Only skills that declare `context: fork` in frontmatter are in scope.
  frontmatter="$(awk '/^---$/{n++; next} n==1' "$skill_file")"
  if ! printf '%s\n' "$frontmatter" | grep -qE '^context:[[:space:]]*fork[[:space:]]*$'; then
    continue
  fi
  checked=$((checked + 1))

  # Last non-empty line of the BODY (after the closing frontmatter fence).
  last_line="$(awk '
    /^---$/ { n++; next }
    n>=2 { if (NF>0) last=$0 }
    END { print last }
  ' "$skill_file")"

  if printf '%s' "$last_line" | grep -qiE "$QUESTION_RE"; then
    errors=$((errors + 1))
    echo "❌ ${skill_file}: context: fork skill ends its body with a user-directed confirmation question — there is no channel back to the user in a forked subagent"
    echo "   Last line: ${last_line}"
  fi
done

echo "SKILLS_SCANNED=${checked}"
echo "ISSUE_COUNT=${errors}"

if [ "$errors" -gt 0 ]; then
  echo "STATUS=ERROR"
  exit 1
fi

echo "STATUS=OK"
exit 0
