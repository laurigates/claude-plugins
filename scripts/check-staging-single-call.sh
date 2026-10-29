#!/usr/bin/env bash
# Guard the `git add` staging guidance this marketplace hands to agents.
#
# Background (issue #3042): `git-plugin/skills/git-local-hazards/SKILL.md`
# taught "one pathspec per `git add`". An agent following it literally writes
# `git add A && git add B` — the exact chained index-writer shape the
# `bash-antipatterns.sh` git-chain block refuses. PR #3089 reworded the hook's
# block message to prescribe one form:
#
#   1. git status --short     (confirm which paths are present)
#   2. git add -- A B C       (ONE git add of the confirmed-present paths)
#   3. git commit             (a separate call, never chained to the add)
#
# Prose that still says "one pathspec per" contradicts that message, so the
# agent is taught a shape and then blocked for using it.
#
# Rules (all ERROR):
#   (1) one_pathspec_per  — a plugin markdown file or a `.claude/rules/*.md`
#       rule says "one pathspec per" (case-insensitive).
#   (2) single_call_form_missing — `git-plugin/skills/git-local-hazards/SKILL.md`
#       no longer carries BOTH `git status --short` and `git add -- ` (the
#       prescribed form), so a reword that drops the replacement also fails.
#   (3) nothing_scanned   — plugin dirs exist but zero markdown was discovered
#       (#2219): a misfired walk must not read as a clean pass.
#
# Release-please CHANGELOG.md files are skipped: they name fixes, they do not
# give guidance, and they must not be hand-edited.
#
# Usage:
#   bash scripts/check-staging-single-call.sh
#   bash scripts/check-staging-single-call.sh --root <dir>   # test seam
#
# Exit codes: 0 STATUS=OK, 1 STATUS=ERROR, 2 unknown argument.

set -uo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"

while [ $# -gt 0 ]; do
  case "$1" in
    --root)
      shift
      [ $# -gt 0 ] || { echo "check-staging-single-call.sh: --root needs a value" >&2; exit 2; }
      ROOT_DIR="$1"
      ;;
    -h | --help)
      echo "usage: check-staging-single-call.sh [--root <dir>]" >&2
      exit 0
      ;;
    *)
      echo "check-staging-single-call.sh: unknown argument: $1" >&2
      exit 2
      ;;
  esac
  shift
done

SKILL_REL="git-plugin/skills/git-local-hazards/SKILL.md"
issues=()
discovered=0
scanned=0

# Walk from inside ROOT_DIR with relative paths so a worktree prune cannot
# match the scan root itself (regression-testing.md, worktree-root discovery).
collect_md() {
  (
    cd "$ROOT_DIR" || exit 0
    for plugin_dir in *-plugin; do
      [ -d "$plugin_dir" ] || continue
      find "$plugin_dir" \
        -path '*/.claude/worktrees/*' -prune -o \
        -path '*/dist/*' -prune -o \
        -name '*.md' -type f -print
    done
    [ -d .claude/rules ] && find .claude/rules -maxdepth 1 -name '*.md' -type f -print
  )
}

while IFS= read -r rel; do
  [ -n "$rel" ] || continue
  discovered=$((discovered + 1))
  [ "$(basename "$rel")" = "CHANGELOG.md" ] && continue
  scanned=$((scanned + 1))
  while IFS=: read -r lineno _; do
    [ -n "$lineno" ] || continue
    issues+=("SEVERITY=ERROR TYPE=one_pathspec_per FILE=$rel LINE=$lineno MSG=teaches 'one pathspec per git add', which produces the blocked 'git add A && git add B' chain; prescribe 'git status --short' then ONE 'git add -- A B C' then 'git commit' as a separate call (#3042)")
  done < <(grep -niH -- 'one pathspec per' "$ROOT_DIR/$rel" 2>/dev/null | cut -d: -f2- || true)
done < <(collect_md)

if [ -f "$ROOT_DIR/$SKILL_REL" ]; then
  if ! grep -qF -- 'git status --short' "$ROOT_DIR/$SKILL_REL" || ! grep -qF -- 'git add -- ' "$ROOT_DIR/$SKILL_REL"; then
    issues+=("SEVERITY=ERROR TYPE=single_call_form_missing FILE=$SKILL_REL MSG=must prescribe the single-call staging form: 'git status --short' and one 'git add -- A B C' (#3042)")
  fi
fi

plugin_dirs=0
for d in "$ROOT_DIR"/*-plugin; do
  [ -d "$d" ] && plugin_dirs=$((plugin_dirs + 1))
done
if [ "$plugin_dirs" -gt 0 ] && [ "$discovered" -eq 0 ]; then
  issues+=("SEVERITY=ERROR TYPE=nothing_scanned MSG=$plugin_dirs plugin dirs but zero markdown discovered; scan misfired (see #2219)")
fi

echo "=== STAGING SINGLE CALL ==="
echo "ROOT=$ROOT_DIR"
echo "FILES_SCANNED=$scanned"
echo "SCANNED_EMPTY=$([ "$discovered" -eq 0 ] && echo true || echo false)"
echo "ISSUE_COUNT=${#issues[@]}"
if [ ${#issues[@]} -gt 0 ]; then
  echo "STATUS=ERROR"
  first_type="${issues[0]#*TYPE=}"
  first_type="${first_type%% *}"
  reason="$(printf '%s: %s' "$first_type" "${issues[0]#*MSG=}" | tr -s '[:space:]' ' ' | cut -c1-180)"
  [ ${#issues[@]} -gt 1 ] && reason="$reason (+$((${#issues[@]} - 1)) more)"
  echo "REASON=$reason"
  echo "ISSUES:"
  for issue in "${issues[@]}"; do
    echo "  - $issue"
  done
  echo "=== END STAGING SINGLE CALL ==="
  exit 1
fi
echo "STATUS=OK"
echo "=== END STAGING SINGLE CALL ==="
exit 0
