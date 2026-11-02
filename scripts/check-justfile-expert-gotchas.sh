#!/usr/bin/env bash
# check-justfile-expert-gotchas.sh — semantic gate for justfile-expert's
# references/gotchas.md (issue #3305).
#
# Background: a justfile cleanup hit five just behaviours the skill did not
# mention: sub-justfile settings and nested `just -f {{quote(justfile())}}`
# calls, path arguments resolving against the justfile directory instead of
# the caller's, top-level backtick variables evaluated for every recipe (so an
# empty grep under `bash -euo pipefail` aborts unrelated recipes), keep-awake
# wrappers that run nothing when systemd-inhibit has no logind, and
# hard-coded personal notifiers / BSD-only `stat -f %z`.
#
# This is a SEMANTIC gate (.claude/rules/regression-testing.md): a bulk edit
# that "tightens" the file could drop the load-bearing tokens, or SKILL.md
# could lose its link and leave the file unreachable. The check asserts each
# token survives INSIDE its own section, not merely anywhere in the file.
#
# What counts as compliant:
#   - SKILL.md links references/gotchas.md
#   - gotchas.md has these `## ` sections, each naming its token:
#       "## Sub-justfiles"            -> `quote(justfile())`
#       "## Path arguments"           -> `invocation_directory()`
#       "## Top-level backticks"      -> `--dry-run` and `exits 0`
#       "## Keep-awake wrappers"      -> `systemd-inhibit --what=idle:sleep true`
#       "## Hooks instead of personal tools" -> `wc -c`
#
# Usage:
#   bash scripts/check-justfile-expert-gotchas.sh [--project-dir DIR]
#
# Output: STATUS= / ISSUE_COUNT= / REASON= per
# .claude/rules/structured-script-output.md.
#
# Exit codes:
#   0 - guidance intact
#   1 - a required link, section or token is missing
#   2 - usage error

set -uo pipefail

ROOT_DIR=""
while [ $# -gt 0 ]; do
  case "$1" in
    --project-dir) ROOT_DIR="${2:-}"; shift 2 ;;
    *) echo "Usage: check-justfile-expert-gotchas.sh [--project-dir DIR]" >&2; exit 2 ;;
  esac
done
[ -n "$ROOT_DIR" ] || ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"

SKILL_DIR="$ROOT_DIR/tools-plugin/skills/justfile-expert"
SKILL="$SKILL_DIR/SKILL.md"
GOT="$SKILL_DIR/references/gotchas.md"

issues=()

# extract_section <file> <heading> -> body until the next "## " heading
extract_section() {
  awk -v h="$2" '
    index($0, h) == 1 { inside = 1; next }
    inside && /^## / { inside = 0 }
    inside { print }
  ' "$1"
}

require_section_token() { # require_section_token <heading> <token>
  local body
  body="$(extract_section "$GOT" "$1")"
  if [ -z "${body//[[:space:]]/}" ]; then
    issues+=("references/gotchas.md: section '$1' missing or empty (#3305)")
    return
  fi
  if ! grep -qF -- "$2" <<<"$body"; then
    issues+=("references/gotchas.md: section '$1' does not mention '$2' (#3305)")
  fi
}

if [ ! -f "$SKILL" ]; then
  issues+=("SKILL.md: not found")
elif ! grep -qF '(references/gotchas.md)' "$SKILL"; then
  issues+=("SKILL.md: does not link references/gotchas.md (#3305)")
fi

if [ ! -f "$GOT" ]; then
  issues+=("references/gotchas.md: not found (#3305)")
else
  require_section_token "## Sub-justfiles" 'quote(justfile())'
  require_section_token "## Path arguments" 'invocation_directory()'
  require_section_token "## Top-level backticks" '--dry-run'
  require_section_token "## Top-level backticks" 'exits 0'
  require_section_token "## Keep-awake wrappers" 'systemd-inhibit --what=idle:sleep true'
  require_section_token "## Hooks instead of personal tools" 'wc -c'
fi

n=${#issues[@]}
echo "=== JUSTFILE EXPERT GOTCHAS ==="
if [ "$n" -eq 0 ]; then
  echo "STATUS=OK"
  echo "ISSUE_COUNT=0"
  echo "=== END JUSTFILE EXPERT GOTCHAS ==="
  exit 0
fi
reason="missing_token: ${issues[0]}"
[ "$n" -gt 1 ] && reason="${reason:0:180} (+$((n - 1)) more)"
echo "STATUS=ERROR"
echo "REASON=${reason:0:200}"
echo "ISSUE_COUNT=$n"
echo "ISSUES:"
for i in "${issues[@]}"; do echo "  - SEVERITY=ERROR TYPE=missing_token MSG=$i"; done
echo "=== END JUSTFILE EXPERT GOTCHAS ==="
exit 1
