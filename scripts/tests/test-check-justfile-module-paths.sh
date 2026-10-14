#!/usr/bin/env bash
# test-check-justfile-module-paths.sh — regression tests for
# check-justfile-module-paths.sh (issue #3060).
#
# Pins:
#   A. the real justfile-expert docs pass (exit 0, STATUS=OK)
#   B. dropping source_directory() from the module section fails
#   C. source_directory() present only OUTSIDE the module section still fails
#   D. dropping the `just <mod> <recipe>` testing advice fails
#   E. dropping source_directory() from key-capabilities.md fails
#   F. both outputs satisfy the structured-output contract (--validate)

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
CHECK="${REPO_ROOT}/scripts/check-justfile-module-paths.sh"
CONTRACT="${REPO_ROOT}/scripts/check-structured-output-contract.sh"
REAL_SKILL="${REPO_ROOT}/tools-plugin/skills/justfile-expert"

pass=0
fail=0
check() { # check <description> <expected> <actual>
  if [ "$2" = "$3" ]; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    printf 'FAIL: %s\n  expected: %s\n  actual:   %s\n' "$1" "$2" "$3" >&2
  fi
}

[ -f "$CHECK" ] || { echo "missing script: $CHECK" >&2; exit 1; }

WORK="$(mktemp -d)"
[ -n "$WORK" ] || { echo "mktemp failed" >&2; exit 1; }
trap 'rm -rf "$WORK"' EXIT

mk_fixture() { # mk_fixture <name> -> echoes the fixture project dir
  local d="$WORK/$1"
  mkdir -p "$d/tools-plugin/skills/justfile-expert/references"
  cp "$REAL_SKILL/REFERENCE.md" "$d/tools-plugin/skills/justfile-expert/"
  cp "$REAL_SKILL/references/key-capabilities.md" "$d/tools-plugin/skills/justfile-expert/references/"
  echo "$d"
}

run() { bash "$CHECK" --project-dir "$1" >/dev/null 2>&1; echo $?; }

# Remove every line containing <token> between "## Module System" and the next "## ".
strip_in_module() { # strip_in_module <file> <token>
  awk -v t="$2" '
    index($0, "## Module System") == 1 { inside = 1; print; next }
    inside && /^## / { inside = 0 }
    inside && index($0, t) { next }
    { print }
  ' "$1" > "$1.tmp" && mv "$1.tmp" "$1"
}

# A. real docs pass
d=$(mk_fixture A)
check "A: real docs exit 0" "0" "$(run "$d")"

# B. strip source_directory() from the module section
d=$(mk_fixture B)
strip_in_module "$d/tools-plugin/skills/justfile-expert/REFERENCE.md" 'source_directory()'
check "B: module section without source_directory() exit 1" "1" "$(run "$d")"

# C. same as B, but source_directory() still appears elsewhere in the file
d=$(mk_fixture C)
f="$d/tools-plugin/skills/justfile-expert/REFERENCE.md"
strip_in_module "$f" 'source_directory()'
printf '\n## Elsewhere\n\nsd := source_directory()\n' >> "$f"
check "C: source_directory() only outside module section exit 1" "1" "$(run "$d")"

# D. strip the testing advice
d=$(mk_fixture D)
strip_in_module "$d/tools-plugin/skills/justfile-expert/REFERENCE.md" 'just <mod> <recipe>'
check "D: missing 'just <mod> <recipe>' advice exit 1" "1" "$(run "$d")"

# E. strip source_directory() from key-capabilities.md
d=$(mk_fixture E)
f="$d/tools-plugin/skills/justfile-expert/references/key-capabilities.md"
grep -vF 'source_directory()' "$f" > "$f.tmp"; mv "$f.tmp" "$f"
check "E: key-capabilities without source_directory() exit 1" "1" "$(run "$d")"

# F. structured-output contract on both the passing and failing outputs
if [ -f "$CONTRACT" ]; then
  out_ok=$(bash "$CHECK" --project-dir "$WORK/A" 2>/dev/null)
  out_err=$(bash "$CHECK" --project-dir "$WORK/B" 2>/dev/null)
  printf '%s\n' "$out_ok" | bash "$CONTRACT" --validate - >/dev/null 2>&1
  check "F1: OK output satisfies contract" "0" "$?"
  printf '%s\n' "$out_err" | bash "$CONTRACT" --validate - >/dev/null 2>&1
  check "F2: ERROR output satisfies contract" "0" "$?"
fi

printf '\n%s: %d passed, %d failed\n' "$(basename "$0")" "$pass" "$fail"
[ "$fail" -eq 0 ]
