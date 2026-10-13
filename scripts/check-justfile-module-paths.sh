#!/usr/bin/env bash
# check-justfile-module-paths.sh — semantic gate for justfile-expert's
# module path-function guidance (issue #3060).
#
# Background: justfile-expert recommended `justfile_directory()` for paths and
# its Module System section never mentioned `source_directory()` /
# `source_file()`. Inside a module (`mod name 'dir'`), `justfile()` and
# `justfile_directory()` resolve to the ROOT justfile, so a module recipe that
# builds paths from them points at the wrong directory. The bug hides when the
# module is tested with `just --justfile <mod>/justfile` or `cd <mod> && just`,
# because the module then becomes the root.
#
# This is a SEMANTIC gate (.claude/rules/regression-testing.md): a bulk edit
# that "tightens" the module section could silently drop the distinction. The
# check asserts the load-bearing tokens survive INSIDE the module section, not
# merely anywhere in the file.
#
# What counts as compliant:
#   - REFERENCE.md `## Module System` section (to the next `## `) names both
#     `source_directory()` and `justfile_directory()`, and the
#     `just <mod> <recipe>` testing advice.
#   - references/key-capabilities.md `**Module System**` block names
#     `source_directory()`.
#
# Usage:
#   bash scripts/check-justfile-module-paths.sh [--project-dir DIR]
#
# Output: STATUS= / ISSUE_COUNT= / REASON= per
# .claude/rules/structured-script-output.md.
#
# Exit codes:
#   0 - guidance intact
#   1 - a required token is missing
#   2 - usage error

set -uo pipefail

ROOT_DIR=""
while [ $# -gt 0 ]; do
  case "$1" in
    --project-dir) ROOT_DIR="${2:-}"; shift 2 ;;
    *) echo "Usage: check-justfile-module-paths.sh [--project-dir DIR]" >&2; exit 2 ;;
  esac
done
[ -n "$ROOT_DIR" ] || ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"

SKILL_DIR="$ROOT_DIR/tools-plugin/skills/justfile-expert"
REF="$SKILL_DIR/REFERENCE.md"
CAP="$SKILL_DIR/references/key-capabilities.md"

issues=()

# extract_block <file> <start-line-prefix> <stop-regex>
extract_block() {
  awk -v h="$2" -v stop="$3" '
    index($0, h) == 1 { inside = 1; next }
    inside && $0 ~ stop { inside = 0 }
    inside { print }
  ' "$1"
}

require_token() { # require_token <file-label> <body> <token> <desc>
  if ! grep -qF -- "$3" <<<"$2"; then
    issues+=("$1: $4")
  fi
}

if [ ! -f "$REF" ]; then
  issues+=("REFERENCE.md: not found")
else
  mod="$(extract_block "$REF" "## Module System" '^## ')"
  if [ -z "${mod//[[:space:]]/}" ]; then
    issues+=("REFERENCE.md: '## Module System' section missing or empty")
  else
    require_token "REFERENCE.md" "$mod" 'source_directory()' "module section does not mention source_directory() (#3060)"
    require_token "REFERENCE.md" "$mod" 'justfile_directory()' "module section does not contrast justfile_directory() (#3060)"
    require_token "REFERENCE.md" "$mod" 'just <mod> <recipe>' "module section lacks the 'just <mod> <recipe>' testing advice (#3060)"
  fi
fi

if [ ! -f "$CAP" ]; then
  issues+=("references/key-capabilities.md: not found")
else
  cap="$(extract_block "$CAP" "**Module System**" '^\*\*')"
  require_token "references/key-capabilities.md" "$cap" 'source_directory()' "Module System block does not mention source_directory() (#3060)"
fi

n=${#issues[@]}
echo "=== JUSTFILE MODULE PATHS ==="
if [ "$n" -eq 0 ]; then
  echo "STATUS=OK"
  echo "ISSUE_COUNT=0"
  echo "=== END JUSTFILE MODULE PATHS ==="
  exit 0
fi
reason="missing_token: ${issues[0]}"
[ "$n" -gt 1 ] && reason="${reason:0:180} (+$((n - 1)) more)"
echo "STATUS=ERROR"
echo "REASON=${reason:0:200}"
echo "ISSUE_COUNT=$n"
echo "ISSUES:"
for i in "${issues[@]}"; do echo "  - SEVERITY=ERROR TYPE=missing_token MSG=$i"; done
echo "=== END JUSTFILE MODULE PATHS ==="
exit 1
