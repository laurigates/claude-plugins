#!/usr/bin/env bash
# Reject tool names that no longer exist from `allowed-tools:` / `tools:` grants.
#
# Four removed names had spread to 40 files: LS, BashOutput, KillShell,
# MultiEdit. None appears in https://code.claude.com/docs/en/tools (verified
# 2026-09-03, which lists 45 tools including their successors Glob, Bash, Edit).
# Two ALWAYS-LOADED authoring rules were minting them -- `agent-development.md`
# carried `LS` in two copy-paste `tools:` templates, and `skill-development.md`
# listed `BashOutput` in its "Development" tool set -- so the count grew with
# every skill written from those templates.
#
# Nothing was established to BREAK at load time: an unrecognised entry in a
# grant list is most likely inert. The cost is a template that keeps minting
# dead names, and wasted model round-trips when a run believes it has a tool it
# does not. All 40 sites turned out to be pure redundancy: every dead name's
# successor was already granted in the same list, so the sweep removed them
# without substituting anything and without any file losing a live tool.
#
# A DENYLIST, not an allowlist of live tools. An allowlist would have to name
# every current tool and would rot the day one is added -- the same disease as
# the hardcoded `v4` in the checkout gate this repo just fixed. A denylist of
# removed names only ever grows, and matches the shape of the sibling guards
# `lint-mcp-tool-references.sh` and `lint-package-references.sh`.
#
# Output follows .claude/rules/structured-script-output.md.
#
# Usage: check-dead-tool-grants.sh [--project-dir DIR]
#
# No --strict: every finding here is an ERROR. A flag accepted but ignored is
# the #2057 defect, so it is absent rather than inert.
#
# Exit codes: 0 clean, 1 a dead name is granted, 2 usage error.
set -uo pipefail

# name|successor|why
DENYLIST='LS|Glob|directory listing moved to Glob
BashOutput|Bash|background output now arrives as a file path in the tool result
KillShell|TaskStop|background work is stopped through the task tools
MultiEdit|Edit|Edit gained replace_all; MultiEdit was removed'

ROOT_DIR=""
while [ $# -gt 0 ]; do
  case "$1" in
    --project-dir)
      if [ -z "${2:-}" ] || [ ! -d "${2:-}" ]; then
        echo "check-dead-tool-grants.sh: --project-dir requires a directory" >&2
        exit 2
      fi
      ROOT_DIR="$(cd "$2" && pwd)"; shift 2 ;;
    -h|--help) sed -n '2,30p' "$0"; exit 0 ;;
    # Unknown args are REJECTED, never swallowed (#2057).
    *) echo "check-dead-tool-grants.sh: unknown argument: $1" >&2; exit 2 ;;
  esac
done
[ -n "$ROOT_DIR" ] || ROOT_DIR="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"

# Discovery runs from INSIDE the root against RELATIVE paths, so a scan root
# that is itself an agent worktree cannot match its own prune (#2219/#2290).
cd "$ROOT_DIR" || exit 2

files_scanned=0
grants_seen=0
issue_count=0
findings=""

while IFS= read -r f; do
  files_scanned=$((files_scanned + 1))
  # Only frontmatter-style grant lines, and the authoring-rule tables that seed
  # them. Prose naming a retired tool is documentation, not a grant.
  # shellcheck disable=SC2016
  # The `$` is an end-of-line anchor in the regex, not a shell expansion, so the
  # single quotes are load-bearing. Two shapes: a frontmatter grant line, and an
  # authoring-rule table row whose second cell is a backticked tool list -- that
  # second shape is how `skill-development.md` was minting BashOutput. A table
  # row WITHOUT backticks (`| LS | retired |`) is prose about the removal and is
  # deliberately not matched.
  while IFS= read -r line; do
    grants_seen=$((grants_seen + 1))
    while IFS='|' read -r name succ why; do
      [ -n "$name" ] || continue
      # Word-boundaried without \b, which is GNU-only (shell-scripting.md):
      # a grant entry is delimited by list punctuation or a backtick.
      if printf '%s' "$line" | grep -qE "(^|[,\` ])${name}([,\` ]|$)"; then
        issue_count=$((issue_count + 1))
        findings="${findings}  - SEVERITY=ERROR TYPE=dead_tool_grant FILE=${f#./} TOOL=${name} FIX=${succ} MSG=${why}
"
      fi
    done <<EOF
$DENYLIST
EOF
  done < <(grep -hE '^(allowed-tools|tools):|^\| *[A-Za-z ]+ *\| *`[A-Za-z, ()*]+` *\|' "$f" 2>/dev/null || true)
done < <(find . \
  -path '*/.git/*' -prune -o \
  -path '*/.claude/worktrees/*' -prune -o \
  -path './dist/*' -prune -o \
  -path '*/node_modules/*' -prune -o \
  -name '*.md' -print 2>/dev/null || true)

echo "=== DEAD TOOL GRANTS ==="
echo "FILES_SCANNED=$files_scanned"
echo "SCANNED_EMPTY=$([ "$files_scanned" -eq 0 ] && echo true || echo false)"
echo "GRANT_LINES=$grants_seen"
echo "DENYLIST_SIZE=$(printf '%s\n' "$DENYLIST" | grep -c .)"
echo "ISSUE_COUNT=$issue_count"
# A walk that opened nothing must never read as clean (#2219/#2290).
if [ "$files_scanned" -eq 0 ]; then
  echo "STATUS=ERROR"
  echo "ISSUES:"
  echo "  - SEVERITY=ERROR TYPE=nothing_scanned MSG=no markdown discovered under $ROOT_DIR"
  echo "=== END DEAD TOOL GRANTS ==="
  exit 1
fi
if [ "$issue_count" -gt 0 ]; then
  echo "STATUS=ERROR"
  echo "ISSUES:"
  printf '%s' "$findings"
else
  echo "STATUS=OK"
fi
echo "=== END DEAD TOOL GRANTS ==="

[ "$issue_count" -gt 0 ] && exit 1
exit 0
