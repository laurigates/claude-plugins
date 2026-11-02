#!/usr/bin/env bash
# test-check-justfile-expert-gotchas.sh — regression tests for
# check-justfile-expert-gotchas.sh (issue #3305).
#
# Pins:
#   A. the real justfile-expert docs pass (exit 0)
#   B. SKILL.md without the references/gotchas.md link fails
#   C. a missing gotchas.md fails
#   D. invocation_directory() present only OUTSIDE its section still fails
#   E. dropping the backtick section's `--dry-run` warning fails
#   F. dropping the systemd-inhibit probe fails
#   G. both outputs satisfy the structured-output contract (--validate)

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
CHECK="${REPO_ROOT}/scripts/check-justfile-expert-gotchas.sh"
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
  cp "$REAL_SKILL/SKILL.md" "$d/tools-plugin/skills/justfile-expert/"
  if [ -f "$REAL_SKILL/references/gotchas.md" ]; then
    cp "$REAL_SKILL/references/gotchas.md" "$d/tools-plugin/skills/justfile-expert/references/"
  fi
  echo "$d"
}

run() { bash "$CHECK" --project-dir "$1" >/dev/null 2>&1; echo $?; }

# Remove every line containing <token> inside the "## <heading>" section.
strip_in_section() { # strip_in_section <file> <heading> <token>
  awk -v h="$2" -v t="$3" '
    index($0, h) == 1 { inside = 1; print; next }
    inside && /^## / { inside = 0 }
    inside && index($0, t) { next }
    { print }
  ' "$1" > "$1.tmp" && mv "$1.tmp" "$1"
}

G="tools-plugin/skills/justfile-expert/references/gotchas.md"

# A. real docs pass
d=$(mk_fixture A)
check "A: real docs exit 0" "0" "$(run "$d")"

# B. drop the SKILL.md link
d=$(mk_fixture B)
f="$d/tools-plugin/skills/justfile-expert/SKILL.md"
grep -vF '(references/gotchas.md)' "$f" > "$f.tmp"; mv "$f.tmp" "$f"
check "B: SKILL.md without gotchas link exit 1" "1" "$(run "$d")"

# C. gotchas.md missing
d=$(mk_fixture C)
rm -f "$d/$G"
check "C: missing gotchas.md exit 1" "1" "$(run "$d")"

# D. invocation_directory() only outside its section
d=$(mk_fixture D)
strip_in_section "$d/$G" "## Path arguments" 'invocation_directory()'
printf '\n## Elsewhere\n\nf := invocation_directory()\n' >> "$d/$G"
check "D: invocation_directory() only outside section exit 1" "1" "$(run "$d")"

# E. backtick section loses the --dry-run warning
d=$(mk_fixture E)
strip_in_section "$d/$G" "## Top-level backticks" '--dry-run'
check "E: backtick section without --dry-run exit 1" "1" "$(run "$d")"

# F. keep-awake section loses the systemd-inhibit probe
d=$(mk_fixture F)
strip_in_section "$d/$G" "## Keep-awake wrappers" 'systemd-inhibit --what=idle:sleep true'
check "F: keep-awake section without probe exit 1" "1" "$(run "$d")"

# G. structured-output contract on both the passing and failing outputs
if [ -f "$CONTRACT" ]; then
  out_ok=$(bash "$CHECK" --project-dir "$WORK/A" 2>/dev/null)
  out_err=$(bash "$CHECK" --project-dir "$WORK/C" 2>/dev/null)
  bash "$CONTRACT" --validate - >/dev/null 2>&1 <<<"$out_ok"
  check "G1: OK output satisfies contract" "0" "$?"
  bash "$CONTRACT" --validate - >/dev/null 2>&1 <<<"$out_err"
  check "G2: ERROR output satisfies contract" "0" "$?"
fi

printf '\n%s: %d passed, %d failed\n' "$(basename "$0")" "$pass" "$fail"
[ "$fail" -eq 0 ]
